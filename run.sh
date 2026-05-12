#!/usr/bin/env bash
# run.sh — Boot and validate a GentooHA artifact produced by build.sh
# Supports: WSL2 import+boot (Linux/Windows), VirtualBox VHD/VDI boot (x64)
# Usage: bash run.sh [--non-interactive] [platform] [flavor] [start_step]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Detect environment ────────────────────────────────────────────────────────
detect_env() {
    if [[ -n "${MSYSTEM:-}" || -n "${MINGW_PREFIX:-}" ]]; then
        echo "windows-bash"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    else
        echo "linux"
    fi
}
ENV_TYPE="$(detect_env)"

# ── Defaults ──────────────────────────────────────────────────────────────────
NON_INTERACTIVE=false
PLATFORM="${PLATFORM:-x64}"
FLAVOR="${FLAVOR:-debug}"
START_STEP="${START_STEP:-1}"
DISTRO_NAME="GentooHA"
WSL_INSTALL_DIR="C:\\Users\\tamus\\AppData\\Local\\GentooHA"

# ── Argument parsing ──────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --non-interactive) NON_INTERACTIVE=true ;;
        x64|pi3|pi4|pizero2|bbb|pbv2) PLATFORM="$arg" ;;
        live|installer|debug) FLAVOR="$arg" ;;
        [1-9]) START_STEP="$arg" ;;
    esac
done

# ── If running from Git Bash on Windows, delegate to run.cmd via WSL ─────────
if [[ "$ENV_TYPE" == "windows-bash" ]]; then
    echo "[run.sh] Git Bash detected — delegating to WSL2..."
    if ! command -v wsl.exe &>/dev/null; then
        echo "ERROR: WSL2 not found. Install WSL2 and retry." >&2
        exit 1
    fi
    exec wsl.exe -d Debian -u root -- bash -lc "cd /mnt/c/Users/tamus/projects/linux/home_assistant_1; PLATFORM=$PLATFORM FLAVOR=$FLAVOR START_STEP=$START_STEP bash run.sh $([ "$NON_INTERACTIVE" == true ] && echo '--non-interactive')"
fi

# ── Interactive prompts ───────────────────────────────────────────────────────
prompt() {
    local var="$1" msg="$2" default="$3"
    if [[ "$NON_INTERACTIVE" == true ]]; then
        eval "$var=\"$default\""
        return
    fi
    read -rp "$msg [$default]: " val
    eval "$var=\"${val:-$default}\""
}

echo "============================================================"
echo " GentooHA Run / Boot / Validate"
echo "============================================================"
echo ""

if [[ "$NON_INTERACTIVE" != true ]]; then
    prompt PLATFORM "Platform (x64 / pi3 / pi4 / pizero2 / bbb / pbv2)" "$PLATFORM"
    prompt FLAVOR   "Flavor  (live / installer / debug)" "$FLAVOR"
fi

# ── For x64, ask whether to boot in VirtualBox or WSL2 ───────────────────────
USE_VIRTUALBOX=false
if [[ "$PLATFORM" == "x64" && "$NON_INTERACTIVE" != true ]]; then
    read -rp "Boot in VirtualBox disk (v) or WSL2 import (w)? [v]: " virt_choice
    virt_choice="${virt_choice:-v}"
    if [[ "${virt_choice,,}" == "v" ]]; then
        USE_VIRTUALBOX=true
    fi
elif [[ "$PLATFORM" == "x64" ]]; then
    # non-interactive: prefer VDI, then VHD
    [[ -f "$SCRIPT_DIR/artifacts/gentooha-${PLATFORM}-${FLAVOR}.vdi" || -f "$SCRIPT_DIR/artifacts/gentooha-${PLATFORM}-${FLAVOR}.vhd" ]] && USE_VIRTUALBOX=true
fi

if [[ "$NON_INTERACTIVE" != true && "$USE_VIRTUALBOX" != true ]]; then
    prompt START_STEP "Start at step (1=import, 2=wsl-conf, 3=iptables, 4=services, 5=validate)" "$START_STEP"
fi

# ── VirtualBox boot path (x64 VHD/VDI) ───────────────────────────────────────
if [[ "$USE_VIRTUALBOX" == true ]]; then
    VM_DISK="$SCRIPT_DIR/artifacts/gentooha-${PLATFORM}-${FLAVOR}.vdi"
    [[ -f "$VM_DISK" ]] || VM_DISK="$SCRIPT_DIR/artifacts/gentooha-${PLATFORM}-${FLAVOR}.vhd"
    VBOXMANAGE=""
    for p in "/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" \
              "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"; do
        [[ -f "$p" ]] && { VBOXMANAGE="$p"; break; }
    done
    if [[ -z "$VBOXMANAGE" ]]; then
        echo "ERROR: VBoxManage.exe not found. Install VirtualBox or use WSL2 path." >&2
        exit 1
    fi
    if [[ ! -f "$VM_DISK" ]]; then
        echo "ERROR: VirtualBox disk not found: $SCRIPT_DIR/artifacts/gentooha-${PLATFORM}-${FLAVOR}.vhd or .vdi"
        echo "       Run build.sh first to produce the artifact." >&2
        exit 1
    fi
    VM="${DISTRO_NAME}"
    echo "[VirtualBox] Registering/configuring VM: $VM"
    "$VBOXMANAGE" showvminfo "$VM" &>/dev/null || {
        "$VBOXMANAGE" createvm --name "$VM" --ostype Gentoo_64 --register
        "$VBOXMANAGE" modifyvm "$VM" --memory 4096 --cpus 2 --firmware bios \
            --graphicscontroller vboxvga --accelerate3d off \
            --nic1 nat \
            --natpf1 "ha-ui,tcp,,8123,,8123" \
            --natpf1 "ssh,tcp,,2222,,22"
        "$VBOXMANAGE" storagectl "$VM" --name SATA --add sata --bootable on
    }
    # VBoxManage.exe needs a Windows-style path, not a WSL /mnt/c path
    VM_DISK_WIN="$(wslpath -w "$VM_DISK" 2>/dev/null || echo "$VM_DISK")"
    echo "[VirtualBox] Attaching: $VM_DISK_WIN"
    "$VBOXMANAGE" closemedium disk "$VM_DISK_WIN" &>/dev/null || true
    "$VBOXMANAGE" storageattach "$VM" --storagectl SATA --port 0 --device 0 \
        --type hdd --medium "$VM_DISK_WIN"
    echo "[VirtualBox] Starting VM (headless)..."
    "$VBOXMANAGE" startvm "$VM" --type headless
    echo ""
    echo "VM is booting. Connect via:"
    echo "  SSH:  ssh -p 2222 root@127.0.0.1"
    echo "  UI:   http://localhost:8123  (after Supervisor pulls images)"
    exit 0
fi

# ── Resolve artifact ──────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "x64" ]]; then
    ARTIFACT_EXT="vhd"
else
    ARTIFACT_EXT="img"
fi

ARTIFACT="$SCRIPT_DIR/artifacts/gentooha-${PLATFORM}-${FLAVOR}.${ARTIFACT_EXT}"
if [[ "$PLATFORM" == "x64" && ! -f "$ARTIFACT" ]]; then
    ALT_ARTIFACT="$SCRIPT_DIR/artifacts/gentooha-${PLATFORM}-${FLAVOR}.vdi"
    [[ -f "$ALT_ARTIFACT" ]] && ARTIFACT="$ALT_ARTIFACT"
fi

if [[ ! -f "$ARTIFACT" ]]; then
    echo "WARNING: Artifact not found: $ARTIFACT"
    echo "         Run build.sh first to produce the artifact."
    if [[ "$NON_INTERACTIVE" != true ]]; then
        read -rp "Continue anyway? (y/N): " cont
        [[ "${cont,,}" == "y" ]] || exit 0
    fi
fi

# ── Step functions ────────────────────────────────────────────────────────────

step_import() {
    echo "[1] Importing GentooHA as WSL2 distro..."
    local tarball="/var/lib/ha-gentoo-hybrid/downloads/gentoo-ha-fixed.tar.gz"

    if ! wsl.exe -d "$DISTRO_NAME" -- echo ok &>/dev/null; then
        echo "    Exporting rootfs tarball from Debian build environment..."
        wsl.exe -d Debian -u root -- bash -c "
            mkdir -p /var/lib/ha-gentoo-hybrid/downloads
            tar --numeric-owner -czf $tarball -C /mnt/gentoo \
                --exclude=./proc --exclude=./sys --exclude=./dev \
                --exclude=./run --exclude=./tmp .
            ls -lh $tarball
        "
        local win_tarball
        win_tarball="$(wslpath -w "\\\\wsl.localhost\\Debian\\${tarball}")" 2>/dev/null || \
        win_tarball="\\\\wsl\$\\Debian\\${tarball//\//\\}"
        echo "    Importing into WSL2 as $DISTRO_NAME..."
        mkdir -p "$WSL_INSTALL_DIR" 2>/dev/null || true
        wsl.exe --import "$DISTRO_NAME" "$WSL_INSTALL_DIR" "$win_tarball" --version 2
        echo "    Import complete."
    else
        echo "    $DISTRO_NAME already exists."
        if [[ "$NON_INTERACTIVE" != true ]]; then
            read -rp "    Reimport (unregister + import fresh)? (y/N): " reimport
            if [[ "${reimport,,}" == "y" ]]; then
                wsl.exe --unregister "$DISTRO_NAME"
                echo "    Unregistered. Reimporting..."
                step_import
                return
            fi
        fi
    fi
}

step_wsl_conf() {
    echo "[2] Ensuring /etc/wsl.conf has systemd=true..."
    local result
    result="$(wsl.exe -d "$DISTRO_NAME" -- bash -c "grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null && echo OK || echo MISSING")"
    if [[ "$result" == "OK" ]]; then
        echo "    /etc/wsl.conf already correct."
    else
        echo "    Writing /etc/wsl.conf..."
        wsl.exe -d "$DISTRO_NAME" -- bash -c "printf '[boot]\nsystemd=true\n\n[automount]\nenabled=true\noptions=metadata\n\n[interop]\nenabled=true\n' > /etc/wsl.conf && echo WRITTEN"
        echo "    Restarting WSL to apply systemd=true..."
        wsl.exe --shutdown
        sleep 8
        local pid1
        pid1="$(wsl.exe -d "$DISTRO_NAME" -- bash -c "ps -p 1 -o comm= 2>/dev/null || echo unknown")"
        echo "    PID1=$pid1"
        [[ "$pid1" == "systemd" ]] && echo "    systemd confirmed as PID 1." || echo "WARNING: PID1 is not systemd."
    fi
}

step_iptables() {
    echo "[3] Configuring iptables legacy mode for Docker..."
    wsl.exe -d "$DISTRO_NAME" -- bash -c "
        if command -v update-alternatives >/dev/null 2>&1; then
            update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
            update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
            echo IPTABLES=legacy-via-update-alternatives
        elif command -v iptables-legacy >/dev/null 2>&1; then
            echo IPTABLES=legacy-binaries-present
        else
            echo 'WARNING: no iptables-legacy found — Docker networking may fail'
        fi
    "
}

step_services() {
    echo "[4] Starting Docker and HA services..."

    echo "    Waiting for systemd..."
    local state i
    for i in $(seq 1 12); do
        state="$(wsl.exe -d "$DISTRO_NAME" -- systemctl is-system-running 2>/dev/null || echo unknown)"
        echo "    systemd: $state (attempt $i/12)"
        [[ "$state" == "running" || "$state" == "degraded" ]] && break
        if [[ "$state" == "initializing" || "$state" == "starting" ]]; then
            wsl.exe -d "$DISTRO_NAME" -- bash -c "
                systemd-machine-id-setup 2>/dev/null || true
                dbus-uuidgen --ensure=/etc/machine-id 2>/dev/null || true
                systemctl mask systemd-firstboot.service 2>/dev/null || true
                systemctl daemon-reload 2>/dev/null || true
            " 2>/dev/null || true
        fi
        sleep 5
    done

    echo "    Starting Docker..."
    wsl.exe -d "$DISTRO_NAME" -- systemctl start docker
    echo "--- docker status ---"
    wsl.exe -d "$DISTRO_NAME" -- systemctl status docker --no-pager -l

    echo "--- os-agent status ---"
    wsl.exe -d "$DISTRO_NAME" -- systemctl start os-agent 2>/dev/null || true
    wsl.exe -d "$DISTRO_NAME" -- systemctl status os-agent --no-pager -l

    echo "--- hassio-supervisor status ---"
    wsl.exe -d "$DISTRO_NAME" -- systemctl start hassio-supervisor 2>/dev/null || true
    wsl.exe -d "$DISTRO_NAME" -- systemctl status hassio-supervisor --no-pager -l

    wsl.exe -d "$DISTRO_NAME" -- bash -c "sysctl -w net.ipv4.ip_forward=1" 2>/dev/null || true
}

step_validate() {
    echo "[5] Validating Home Assistant stack..."
    if [[ -f "$SCRIPT_DIR/scripts/validation/validate_ha_stack.sh" ]]; then
        wsl.exe -d "$DISTRO_NAME" -- bash -lc "bash /mnt/c$(echo "$SCRIPT_DIR" | sed 's|C:||I;s|\\|/|g')/scripts/validation/validate_ha_stack.sh" || true
    else
        echo "    No validate_ha_stack.sh found — skipping."
    fi

    echo ""
    echo "============================================================"
    echo " GentooHA is running."
    echo " Enter distro:     wsl -d $DISTRO_NAME"
    echo " Watch HA startup: wsl -d $DISTRO_NAME -- journalctl -fu hassio-supervisor"
    echo " Home Assistant:   http://localhost:8123"
    echo "   (available after Supervisor finishes pulling its image)"
    echo "============================================================"
}

# ── VirtualBox path for x64 ───────────────────────────────────────────────────
run_virtualbox() {
    local vboxmanage
    vboxmanage="$(command -v VBoxManage 2>/dev/null || echo '/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe')"

    echo "[run] Booting VirtualBox VDI: $ARTIFACT"
    if [[ ! -f "$ARTIFACT" ]]; then
        echo "ERROR: VDI not found: $ARTIFACT" >&2
        exit 1
    fi

    local vm="GentooHA"
    "$vboxmanage" showvminfo "$vm" &>/dev/null || \
        "$vboxmanage" createvm --name "$vm" --ostype Gentoo_64 --register

    "$vboxmanage" modifyvm "$vm" \
        --memory 4096 --cpus 2 --firmware bios \
        --graphicscontroller vboxvga --accelerate3d off \
        --uart1 0x3F8 4 --uartmode1 "file" "/tmp/gentooha_serial.log" \
        --natpf1 "ha-ui,tcp,,8123,,8123" \
        --natpf1 "ssh,tcp,,2222,,22" 2>/dev/null || true

    "$vboxmanage" closemedium disk "$ARTIFACT" 2>/dev/null || true
    "$vboxmanage" storageattach "$vm" --storagectl SATA --port 0 --device 0 \
        --type hdd --medium "$ARTIFACT" 2>/dev/null || \
    "$vboxmanage" storagectl "$vm" --name SATA --add sata --bootable on && \
    "$vboxmanage" storageattach "$vm" --storagectl SATA --port 0 --device 0 \
        --type hdd --medium "$ARTIFACT"

    "$vboxmanage" startvm "$vm" --type gui
    echo "    VM started. Monitor: tail -f /tmp/gentooha_serial.log"
    echo "    Home Assistant UI: http://localhost:8123 (after Supervisor pulls images)"
}

# ── Main dispatcher ───────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "x64" && "$ENV_TYPE" != "wsl" ]]; then
    run_virtualbox
    exit 0
fi

# WSL import+boot path
[[ "$START_STEP" -le 1 ]] && step_import
[[ "$START_STEP" -le 2 ]] && step_wsl_conf
[[ "$START_STEP" -le 3 ]] && step_iptables
[[ "$START_STEP" -le 4 ]] && step_services
step_validate
