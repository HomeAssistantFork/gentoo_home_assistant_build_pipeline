# GentooHA Pipeline Plan

## Overview

Single-input, single-artifact builds for all supported platforms.
Pass `PLATFORM` and `FLAVOR` and get exactly one artifact out.

## Platform → Artifact Matrix

| PLATFORM  | Architecture | SoC / Board         | Artifact   | Flavors         |
|-----------|-------------|---------------------|------------|-----------------|
| x64       | x86_64      | Generic PC / VM     | `.iso`     | live, installer |
| pi3       | armv7 (32b) | BCM2837 (RPi 3)     | `.img`     | live, installer |
| pi4       | arm64       | BCM2711 (RPi 4)     | `.img`     | live, installer |
| pizero2   | arm64       | BCM2710 (RPi Zero2W)| `.img`     | live, installer |
| bbb       | armv7 (32b) | AM335x (BBB)        | `.img`     | live, installer |
| pbv2      | arm64       | AM62x (PocketBeagle2)| `.img`    | live, installer |

## Artifact Naming Convention

```
gentooha-<platform>-<flavor>.<ext>
e.g. gentooha-x64-live.iso
     gentooha-pi4-installer.img
```

## Runner Strategy

Every build runs on **two runner targets** via GitHub Actions:

1. **Self-hosted runner** (`runs-on: [self-hosted, linux, x64]`)
   - Your local Windows PC registered as a GitHub Actions runner.
   - Has WSL2 + Debian already set up, access to `/mnt/gentoo`.
   - ARM builds use QEMU binfmt on the self-hosted runner.
   - `import_and_boot_gentooha.cmd` only runs on self-hosted (Windows).

2. **GitHub-hosted fallback** (`runs-on: ubuntu-latest`)
   - Triggers automatically if the self-hosted runner is offline.
   - Runs the full Linux-side build pipeline via `build.sh`.
   - Cannot run `import_and_boot_gentooha.cmd` (Windows-only).
   - ARM builds use QEMU binfmt (`qemu-user-static`).

## Environment Variables

| Variable       | Values                              | Default   |
|----------------|-------------------------------------|-----------|
| PLATFORM       | x64, pi3, pi4, pizero2, bbb, pbv2   | x64       |
| FLAVOR         | live, installer                     | live      |
| START_STAGE    | 1–11                                | 1         |
| CLEAN_STATE    | true/false                          | false     |
| ARTIFACT_DIR   | path                                | /var/lib/ha-gentoo-hybrid/artifacts |
| CROSS_COMPILE  | (auto-set by common.sh from PLATFORM)| —        |
| ARCH           | (auto-set by common.sh from PLATFORM)| —        |

## Cross-Compile Toolchains

| PLATFORM       | ARCH   | CROSS_COMPILE prefix          | Install (Debian/Ubuntu)                  |
|----------------|--------|-------------------------------|------------------------------------------|
| x64            | x86_64 | (native, none)                | —                                        |
| pi3            | arm    | arm-linux-gnueabihf-          | gcc-arm-linux-gnueabihf                  |
| pi4, pizero2   | arm64  | aarch64-linux-gnu-            | gcc-aarch64-linux-gnu                    |
| bbb            | arm    | arm-linux-gnueabihf-          | gcc-arm-linux-gnueabihf                  |
| pbv2           | arm64  | aarch64-linux-gnu-            | gcc-aarch64-linux-gnu                    |

ARM builds also require `qemu-user-static` and `binfmt-support` on the build host.

## Stage Pipeline

```
stage1  → Gentoo stage3 tarball / base system
stage2  → Portage tree sync
stage3  → Base system packages (openrc → systemd migration)
stage4  → System profile + USE flags
stage5  → Python, Docker, os-agent prerequisites
stage6  → Dual kernel build (compat + modern) with HA/AppArmor kernel options
          + ARM cross-compile when PLATFORM != x64
stage7  → os-agent install
stage8  → hassio-supervisor + Home Assistant Supervised install
stage9  → AppArmor userspace (emerge sys-apps/apparmor + systemctl enable)
stage10 → Internal cleanup (remove source/cache dirs)
stage11 → Artifact generation
          PLATFORM=x64           → .iso (grub-mkrescue live + syslinux installer)
          PLATFORM=pi*/bbb/pbv2  → .img (dd + losetup + ext4/fat32 partition layout)
```

## Artifact Generation Detail

### x64 ISO (stage11, FLAVOR=live)
- squashfs rootfs → LiveOS/rootfs.squashfs
- dracut with dmsquash-live module
- grub2 EFI + BIOS boot
- ISO label: GENTOOHA

### x64 ISO (stage11, FLAVOR=installer)
- Same squashfs rootfs
- Additional installer script in /root/install.sh run from live environment
- Grub menu adds "Install to disk" entry

### ARM IMG (stage11, FLAVOR=live)
- Partition layout: 256MB FAT32 boot + rest ext4 root
- Boot: kernel + dtb + initramfs in /boot partition
- U-Boot or device-specific bootloader config per platform
- Compressed: `.img.xz`

### ARM IMG (stage11, FLAVOR=installer)
- Same partition layout
- /root/install.sh auto-runs on first boot from a flag file
- Writes itself to target disk when booted on target hardware

## GitHub Actions Workflows

### `.github/workflows/build.yml`
- Trigger: `workflow_dispatch` with `platform` and `flavor` inputs
- Runs on self-hosted first; ubuntu-latest if offline
- Steps:
  1. Checkout repo
  2. Clone HA org repos (scripts/repos/clone_home_assistant_org.sh)
  3. Install host build deps (QEMU if ARM)
  4. Run `bash build.sh --non-interactive` with PLATFORM/FLAVOR env
  5. Upload artifact
  6. (self-hosted only) Run import_and_boot_gentooha.cmd for x64

### `.github/workflows/build-all.yml`
- Trigger: `push` to main or manual dispatch
- Matrix strategy: all 6 platforms × 2 flavors = 12 jobs
- Each job calls `build.yml` reusable workflow

## Local Build Scripts

### `build.sh` (bash / WSL / Linux)
Interactive mode (default):
- Prompt: Which platform? (x64/pi3/pi4/pizero2/bbb/pbv2)
- Prompt: Which flavor? (live/installer)
- Prompt: Start from stage? (1–11, default 1)
- Prompt: Clean prior state? (y/N)
Exports env vars and calls `scripts/gentoo/run_all.sh`.

Non-interactive mode (CI):
- `bash build.sh --non-interactive` reads PLATFORM/FLAVOR from environment.

### `build.cmd` (Windows / CMD)
- `SET /P` prompts for platform and flavor
- Invokes `build.sh` via `wsl -d GentooHA` (primary) or `wsl -d Debian` (fallback)
- After build, calls `import_and_boot_gentooha.cmd` for x64 builds

## Self-Hosted Runner Setup

1. On your local machine, go to your GitHub repo → Settings → Actions → Runners → New self-hosted runner.
2. Follow the instructions to download and register the runner agent on Windows.
3. Run the agent as a Windows service so it starts automatically.
4. The runner needs WSL2 + Debian available as `wsl -d Debian`.
5. Label the runner: `self-hosted, linux, x64`.

The runner agent will be at `C:\actions-runner\` by default and can be started with:
```powershell
cd C:\actions-runner
.\run.cmd
```

## pbv2 GPU Note

PocketBeagle v2 uses the TI AM62x SoC with PowerVR SGX GPU.
GPU driver support requires:
- TI-provided kernel module (`pvrsrvkm`) — not yet in mainline.
- Firmware blob from TI SDK.
- This is stubbed as TODO in stage6.sh until TI source is available.

## File Checklist

- [x] `scripts/gentoo/common.sh` — PLATFORM/FLAVOR/ARCH/CROSS_COMPILE
- [x] `scripts/gentoo/stage6.sh` — ARM cross-compile + platform defconfig
- [x] `scripts/gentoo/stage9.sh` — AppArmor userspace
- [x] `scripts/gentoo/stage10.sh` — internal source/cache cleanup
- [x] `scripts/gentoo/stage11.sh` — ISO/IMG artifact output
- [x] `scripts/gentoo/run_all.sh` — START_STAGE + env pass-through
- [x] `build.sh` — interactive local launcher
- [x] `build.cmd` — Windows local launcher
- [x] `.github/workflows/build.yml` — single platform CI workflow
- [x] `.github/workflows/build-all.yml` — full matrix CI workflow
- [x] `import_and_boot_gentooha.cmd` — x64 WSL2 boot/validation (Windows)
