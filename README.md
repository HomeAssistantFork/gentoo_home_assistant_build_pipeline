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

## Portage Emerge Package Path (Validated)

The Home Assistant stack in this repository is now package-driven through the local `gentooha` overlay.

Primary packages:

- `sys-kernel/gentooha-kernel-config-alpha`
	- Ships `/usr/share/gentooha-kernel-config-alpha/required-flags.conf`
	- Stage 6 consumes this manifest to enforce 150+ required kernel flags.
- `sys-apps/gentooha-compat`
	- Installs host compatibility assets (`/etc/ha-compat/os-release`, host info helpers, Docker defaults).
- `sys-apps/gentooha-supervisor-9999`
	- Live ebuild for Supervisor install path (fork-first repo resolution).
- `sys-apps/gentooha-os-agent-9999`
	- Live ebuild that builds and installs os-agent.
- `gentooha/gentooha-alpha`
	- Meta-package that pulls the full stack and dependencies (systemd, docker, apparmor, openssh, grub, etc.).

Package flow by stage:

- Stage 3: register local overlay and Portage repo config.
- Stage 4: `emerge gentooha/gentooha-alpha` installs the stack.
- Stage 6: kernel build applies flags from `gentooha-kernel-config-alpha` package manifest.
- Stage 8+: service/runtime wiring uses already-emerged components.

## What Still Requires Manual/Scripted Steps (Not Pure Emerge)

These are still handled by scripts or runtime orchestration rather than a single ebuild:

- Partitioning, filesystem creation, chroot mount orchestration, and final disk/image assembly.
- Bootloader install targets and image-specific boot wiring (for VDI/ISO/IMG formats).
- Platform/flavor-specific artifact packaging and checksum manifest generation.
- CI artifact upload and GitHub Release publishing logic.
- Runtime validation tasks (service health checks, API checks, add-on validation) in `scripts/validation/*`.

Everything above is expected and normal for appliance/image pipelines; Portage manages software installation and dependency resolution, while the build scripts manage environment construction and artifact lifecycle.

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
- Copy and register local `gentooha` overlay (contains `sys-kernel/gentooha-kernel-alpha` and `sys-kernel/gentooha-kernel-config-alpha`)
- Install systemd-networkd, systemd-resolved as boot services
- Update entire `@world` package set

**Inputs**: Gentoo stage3 from stage2  
**Outputs**: Configured Gentoo system with Portage and systemd infrastructure ready

### Stage 4: Gentooha Meta-Package Emerge
**Purpose**: Install the Home Assistant stack from Portage overlay packages  
**Key Actions**:
- Configure package keywords/USE where needed for live/overlay packages
- Run `emerge --ask=n gentooha/gentooha-alpha`
- Pull stack dependencies via Portage (systemd, docker, apparmor, openssh, grub, etc.)

**Inputs**: Base system from stage3  
**Outputs**: Package-installed stack from Portage overlay and Gentoo repos

### Stage 5: Compatibility Layer Finalization
**Purpose**: Ensure host compatibility helpers are installed and enabled  
**Key Actions**:
- Ensure `sys-apps/gentooha-compat` is present
- Enable `ha-os-release-sync.service`
- Keep compatibility identity files in sync for Supervisor expectations

**Inputs**: Base system from stage4  
**Outputs**: Compatibility layer active and service-enabled

### Stage 6: Kernel Package Build (Dual Track)
**Purpose**: Build dual kernel tracks (compat and modern) as a Portage-installed kernel package  
**Key Actions**:
- Emerge `sys-kernel/gentooha-kernel-alpha` from the local overlay
- Read and apply required kernel flags from `sys-kernel/gentooha-kernel-config-alpha`
- Build `compat` kernel (conservative settings for compatibility)
- Build `modern` kernel (latest Gentoo kernel with latest features)
- Install kernel images, modules, configs, and DTBs through Portage so stage12 can emit a standalone kernel binpkg

**Inputs**: Base system from stage5; kernel sources; local overlay with kernel package and config package  
**Outputs**: Two bootable kernels with Supervisor prerequisites and a Portage-managed kernel package install

### Stage 7: Services & Daemons
**Purpose**: Install and configure system services  
**Key Actions**:
- Install OpenSSH, syslog services
- Configure systemd unit files for automatic service startup
- Set up logging infrastructure

**Inputs**: System from stage6  
**Outputs**: System with network and logging services ready

### Stage 8: Home Assistant Supervisor & Docker
**Purpose**: Apply HA runtime configuration on top of emerged packages  
**Key Actions**:
- Ensure supervisor and os-agent ebuild outputs are present
- Apply machine/platform substitutions where required by runtime config
- Verify service units and expected filesystem paths for Supervisor runtime
- Keep Docker and Supervisor runtime behavior aligned with Gentoo host expectations

**Inputs**: System from stage7  
**Outputs**: Ready-to-boot HA runtime aligned to emerged package layout

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
- Release workflows request x64 `vdi iso img` outputs by default
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
- Publish a release-friendly binhost archive as `gentooha-binhost-<platform>-<flavor>.tar.zst`

**Inputs**: Completed system from stage11  
**Outputs**: Binary package cache (`.tbz2` files) in `binpkgs/` directory plus a `gentooha-binhost-*.tar.zst` release asset

Notes:
- GitHub Actions artifacts are downloaded as `.zip` containers by GitHub even when the real payload inside is `.iso`, `.img`, or Portage binpkg content.
- Stage 6 now installs `sys-kernel/gentooha-kernel-alpha` through Portage, so stage12 can emit the compiled kernel as a standalone binpkg alongside the rest of `@world`.

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
