# Gentoo + Home Assistant Hybrid Automation

## Project Context

This GentooHA conversion from Debian has been driven primarily with Copilot AI Autopilot for VS Code, with most work focused on system configuration, orchestration, and compatibility bring-up rather than application code changes.

`GentooHA` naming note: in this project, `HA` does not mean Home Assistant. This effort is an in-progress forking path around the Home Assistant ecosystem, and the same project name should not be reused so the projects remain clearly differentiated.

Future efforts are planned to mirror Home Assistant behavior through a more bare-metal oriented implementation approach.

Another primary objective is to run this stack on Raspberry Pi Green hardware.

Contributing compatible improvements back to the original Home Assistant project remains a primary goal.

This repository contains automation to:
- Recreate the WSL bootstrap distro (Debian on WSL2).
- Clone Home Assistant organization repositories.
- Build a staged Gentoo host with systemd.
- Prepare Home Assistant Supervisor compatibility checks.
- Validate the final Home Assistant stack.
- Produce a pure-VM live ISO artifact after staged build completion.

## Current Progress (May 2026)

### Verified Working

- Gentoo VM boots from rebuilt debug VDI artifacts.
- SSH and HA NAT forwarding are configured on VirtualBox (host ports `2222` and `8123`).
- Kernel-side Supervisor prerequisites for cgroup/BPF were added and validated in built configs:
	- `CONFIG_BPF_SYSCALL=y`
	- `CONFIG_CGROUP_BPF=y`
- Supervisor launch path under Gentoo is now working in the rebuilt image:
	- `docker.service` reaches `active`
	- `hassio-supervisor.service` reaches `active`
	- `hassio_supervisor` container reaches `Up`
- Prior runtime blocker `bpf_prog_query(BPF_CGROUP_DEVICE) failed: function not implemented` is no longer observed on the current rebuilt artifact.
- Prior AppArmor label failure path was mitigated for this Gentoo flow by running Supervisor with:
	- `--security-opt apparmor=unconfined`

### Not Fully Stable Yet

- SSH responsiveness is intermittent in some boots: port `2222` may be open while SSH banner exchange times out.
- HA web endpoint (`http://127.0.0.1:8123`) can remain slow or timeout from host-side checks even when Supervisor is up.
- Some stage executions still encounter transient DNS resolution failures while fetching Gentoo packages (`distfiles.gentoo.org`, `packages.gentoo.org`).

### In Progress / Remaining Work

- Harden boot-time service reliability so SSH and UI become consistently responsive after every boot.
- Confirm end-to-end Home Assistant onboarding through the UI (not only service/container health).
- Run and archive full validation bundle results for both kernel tracks (`compat` and `modern`).
- Keep validating that Supervisor startup remains clean across rebuilds and not just a single artifact.

### Next Targeted Validation: Add-ons (Node-RED)

One explicit pending validation is to prove add-on discovery and install flow under Gentoo Supervisor, including Node-RED from the add-on repository.

Planned acceptance checks:

- Home Assistant UI shows add-on store/repositories.
- Node-RED add-on appears in catalog.
- Node-RED installs successfully.
- Node-RED container starts and remains healthy.
- Restart/reboot persistence is verified.

Suggested verification methods:

- UI path (preferred): install Node-RED from add-on store and verify add-on logs/status.
- API/CLI path: use Supervisor API checks in `scripts/validation/validate_ha_stack.sh` and `scripts/validation/run_validation_bundle.sh` with `SUPERVISOR_TOKEN` exported.

## Natural next step:

Run prerequisite and initial automation execution in order:
prereq_wsl_debian.cmd
clone_home_assistant_org.sh
run_all.sh
preflight_ha_supervisor.sh
validate_ha_stack.sh
If you want, I can now do the second pass and harden stage6 specifically for a true Debian-kernel compatibility track plus a modern Gentoo kernel track with explicit config artifacts and boot menu naming.

## Repository Layout

- `scripts/windows/prereq_wsl_debian.cmd`
- `scripts/repos/clone_home_assistant_org.sh`
- `scripts/gentoo/run_all.sh`
- `scripts/gentoo/stage1.sh` ... `scripts/gentoo/stage13.sh` (13 build stages)
- `scripts/compat/preflight_ha_supervisor.sh`
- `scripts/validation/validate_ha_stack.sh`
- `scripts/validation/run_validation_bundle.sh`
- `docs/pure_vm_iso_workflow.md`
- `docs/arm64_delta_notes.md`
- `plan.md`
- `plan_manual.md`
- `IMPLEMENTATION.md`

## Run Order

Use the steps below in order.

### 1) Windows prerequisite (destructive for Debian WSL)
Run from an elevated Command Prompt on Windows:

```cmd
scripts\windows\prereq_wsl_debian.cmd
```

What it does:
- Removes existing Debian WSL distro directly (no backup/export).
- Installs Debian via WSL.
- Runs `apt update`, `apt full-upgrade`, and base package install.

### 2) Clone all Home Assistant organization repositories
Run from Linux shell (WSL):

```bash
bash scripts/repos/clone_home_assistant_org.sh
```

Optional environment variables:
- `OUT_DIR` (default: `./sources/home-assistant`)
- `MANIFEST_DIR` (default: `./manifests`)
- `INCLUDE_ARCHIVED=true|false`
- `SHALLOW=true|false`
- `RESUME=true|false`

### 3) Run staged Gentoo build pipeline
Run from Linux shell:

```bash
chmod +x scripts/gentoo/*.sh scripts/compat/*.sh scripts/validation/*.sh scripts/repos/*.sh
sudo bash scripts/gentoo/run_all.sh
```

Important:
- Ensure `STAGE3_TARBALL` is configured/available before stage2.
- Stages are designed to be rerunnable.

To run individual stages:

```bash
sudo bash scripts/gentoo/stage1.sh
sudo bash scripts/gentoo/stage2.sh
sudo bash scripts/gentoo/stage3.sh
sudo bash scripts/gentoo/stage4.sh
sudo bash scripts/gentoo/stage5.sh
sudo bash scripts/gentoo/stage6.sh
sudo bash scripts/gentoo/stage7.sh
sudo bash scripts/gentoo/stage8.sh
sudo bash scripts/gentoo/stage9.sh
sudo bash scripts/gentoo/stage10.sh
sudo bash scripts/gentoo/stage11.sh
sudo bash scripts/gentoo/stage12.sh
sudo bash scripts/gentoo/stage13.sh
```

Or run a range using environment variables:

```bash
# Run only stages 6-12 (kernel build through binary packages, skip finalization)
sudo bash -c 'START_STAGE=6 END_STAGE=12 bash scripts/gentoo/run_all.sh'
```

### 4) Run Home Assistant compatibility preflight
Run before and after Supervisor deployment:

```bash
sudo bash scripts/compat/preflight_ha_supervisor.sh
```

### 5) Run stack validation
Run after deployment:

```bash
sudo bash scripts/validation/validate_ha_stack.sh
```

For Node-RED add-on API checks, set:

```bash
export SUPERVISOR_TOKEN="<your_token>"
```

For report artifacts and pass/fail bundle output:

```bash
export KERNEL_TRACK=compat
sudo bash scripts/validation/run_validation_bundle.sh
```

Repeat after booting the modern kernel track:

```bash
export KERNEL_TRACK=modern
sudo bash scripts/validation/run_validation_bundle.sh
```

### 6) Pure VM artifact workflow

See:

- `docs/pure_vm_iso_workflow.md`

Artifact output path default:

- `/var/lib/ha-gentoo-hybrid/artifacts/gentooha-live.iso`

## Build Stages Reference

The build pipeline consists of 13 stages, each with a specific role in constructing the Gentoo + Home Assistant image.

### Stage 1: Host Preparation
**Purpose**: Prepare the Debian WSL host for building  
**Key Actions**:
- Install host prerequisites (debootstrap, gdisk, parted, wget, curl, git, rsync, xz-utils, tar)
- Create and prepare `TARGET_ROOT` directory for the chroot environment
- Clean up any existing partial chroots to ensure clean state

**Inputs**: None (runs on host)  
**Outputs**: Empty prepared chroot directory at `TARGET_ROOT`

### Stage 2: Stage3 Extraction
**Purpose**: Download and extract Gentoo stage3 tarball into the chroot  
**Key Actions**:
- Fetch or use existing Gentoo stage3 tarball (x86_64, ARM64, etc.)
- Extract stage3 into `TARGET_ROOT` to bootstrap the Gentoo system
- Preserve any existing configuration files

**Inputs**: `STAGE3_TARBALL` path (auto-fetched if not present)  
**Outputs**: Complete Gentoo base system in `TARGET_ROOT`

### Stage 3: Portage & System Profile
**Purpose**: Configure Portage and apply base system profile  
**Key Actions**:
- Bind-mount `/proc`, `/sys`, `/dev` into chroot
- Sync Portage tree from Gentoo mirrors
- Apply default/linux system profile
- Copy and register local `gentooha` overlay (contains `sys-kernel/gentooha-kernel-config-alpha`)
- Install systemd-networkd, systemd-resolved as boot services
- Update entire `@world` package set

**Inputs**: Gentoo stage3 from stage2  
**Outputs**: Configured Gentoo system with Portage and systemd infrastructure ready

### Stage 4: bootloader & System Tools
**Purpose**: Install boot-critical tools and bootloader  
**Key Actions**:
- Install GRUB2 bootloader and necessary boot tools
- Configure initramfs generation (dracut)
- Set up boot partition layout for x64/ARM targets

**Inputs**: Base system from stage3  
**Outputs**: Bootable system with GRUB and initramfs support

### Stage 5: Device Tree & Board Support
**Purpose**: Install hardware-specific device tree and board support files  
**Key Actions**:
- Install `sys-firmware/linux-firmware` for network and device drivers
- Extract and install device tree blobs (DTBs) for ARM boards if applicable
- Configure board-specific boot parameters

**Inputs**: Base system from stage4  
**Outputs**: System with hardware firmware and device support

### Stage 6: Kernel Build (Dual Track)
**Purpose**: Build dual kernel tracks (compat and modern) with Home Assistant Supervisor prerequisites  
**Key Actions**:
- Install `sys-kernel/gentooha-kernel-config-alpha` package from local overlay
- Read and apply required kernel flags from package manifest (150+ flags for BPF, cgroups, netfilter, AppArmor, etc.)
- Build `compat` kernel (conservative settings for compatibility)
- Build `modern` kernel (latest Gentoo kernel with latest features)
- Generate boot menu entries for both tracks

**Inputs**: Base system from stage5; kernel sources; local overlay with alpha config package  
**Outputs**: Two bootable kernels with Supervisor prerequisites (`CONFIG_BPF_SYSCALL`, `CONFIG_CGROUP_BPF`, etc.)

### Stage 7: Services & Daemons
**Purpose**: Install and configure system services  
**Key Actions**:
- Install OpenSSH, syslog services
- Configure systemd unit files for automatic service startup
- Set up logging infrastructure

**Inputs**: System from stage6  
**Outputs**: System with network and logging services ready

### Stage 8: Home Assistant Supervisor & Docker
**Purpose**: Install Home Assistant Supervisor, Docker, and os-agent  
**Key Actions**:
- Download and extract `homeassistant-supervised.deb` package contents
- Download and extract `os-agent.deb` package contents
- Install Docker daemon with optimized configuration:
  - Disable legacy iptables (`iptables=false, ip6tables=false`) for compatibility
  - Configure log drivers and storage
- Install systemd unit files for `docker.service` and `hassio-supervisor.service`
- Apply AppArmor workaround: launch Supervisor with `apparmor=unconfined` to avoid profile lookup failures
- Configure Supervisor data directory (`/var/lib/homeassistant`)

**Inputs**: System from stage7  
**Outputs**: Ready-to-boot system with Docker and Supervisor installed

### Stage 9: System Cleanup & Optimization
**Purpose**: Reduce image size and prepare for artifact generation  
**Key Actions**:
- Remove build artifacts and temporary files
- Clean Portage cache
- Strip debug symbols from binaries (optional)
- Remove unnecessary documentation

**Inputs**: System from stage8  
**Outputs**: Optimized, compact rootfs ready for packaging

### Stage 10: Post-Install Configuration
**Purpose**: Final system tuning and validation  
**Key Actions**:
- Verify critical services are installed and functional
- Set up any final runtime configurations
- Generate system manifests or validation checksums

**Inputs**: System from stage9  
**Outputs**: Fully configured, validated rootfs

### Stage 11: Image Artifact Generation
**Purpose**: Create bootable VM/appliance images from the rootfs  
**Key Actions**:
- Package rootfs into VDI (VirtualBox) format for x64
- Create alternative formats (ISO, IMG) if specified
- Configure boot parameters and kernel command-line options
- Embed both kernel tracks (compat/modern) for boot selection
- For debug flavor: disable modesetting, enable verbose logging

**Inputs**: Completed rootfs from stage10  
**Outputs**: Bootable VM artifacts (`*.vdi`, `*.iso`, `*.img`)

### Stage 12: Binary Package Generation
**Purpose**: Create a cache of compiled binary packages for faster rebuilds  
**Key Actions**:
- Mount chroot filesystem
- Configure Portage with `FEATURES="buildpkg"` enabled
- Run `emerge --buildpkg=y @world` to precompile all packages as binary `.tbz2` archives
- Exclude virtual and metadata-only packages
- Store binaries in `/var/cache/binpkgs/` for reuse by `--getbinpkg` in future builds

**Inputs**: Completed system from stage11  
**Outputs**: Binary package cache (`.tbz2` files) in `binpkgs/` directory

### Stage 13: Artifact Manifest & Finalization
**Purpose**: Generate checksums and metadata for all artifacts  
**Key Actions**:
- Locate all generated artifacts from stage11 (VDI, ISO, IMG)
- Generate manifest file listing:
  - Platform and flavor metadata
  - Artifact filenames
  - SHA256 checksums for integrity verification
- Store manifest as `gentooha-${PLATFORM}-${FLAVOR}.manifest.txt`

**Inputs**: Artifacts from stage11  
**Outputs**: Manifest file with artifact checksums and metadata

## What To Commit

To add everything in this repo to source control:

```bash
git add .
git status
```

Then commit:

```bash
git commit -m "Add Gentoo + Home Assistant hybrid automation scripts and docs"
```

## Notes

- The Windows prerequisite step intentionally deletes current Debian WSL distro.
- This implementation targets x64 first.
- arm64 (Raspberry Pi Green) is a planned follow-up adaptation.
