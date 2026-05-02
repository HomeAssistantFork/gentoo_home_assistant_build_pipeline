Plan: Gentoo Home Assistant Hybrid Build
Create an automation pipeline that first recreates the WSL bootstrap distro from Windows, then builds a systemd-based Gentoo host that can run Home Assistant Supervisor with add-on support, and provides two kernel choices: compatibility-focused and modern. Use staged scripts for reproducibility and future arm64 adaptation.

Steps

Phase 0: Top prerequisite bootstrap replacement.

Create a Windows cmd entrypoint that performs guarded WSL replacement:

Verify admin context and WSL availability.

Validate WSL is installed and running with admin rights.
Confirm the target distro name to remove (current Debian).
Execute direct distro removal (no export, no backup).
Install latest available Debian WSL2 distro channel.
Install fresh WSL2 Debian target using the latest available WSL Debian channel.
Run first-boot bootstrap:
apt update
apt full-upgrade
install build tooling and git/github CLI prerequisites
Mark completion state so reruns skip already-finished bootstrap tasks.
Run first-boot package refresh and baseline tool install.

Note on naming: Debian does not use Ubuntu-style year tags such as 26.04; script must detect/install the latest available Debian listing from WSL.

Dependency: blocks all later stages.

Phase 1: Repository acquisition.

Build org-wide clone automation for all repositories under github.com/home-assistant.

Prioritize initial bootstrap set for immediate work: supervisor, operating-system, core.

Clone remaining repositories with pagination, retries, and status manifest.

Add switches for archived repos, shallow/full history, and resume mode.

Dependency: can run in parallel with early Gentoo base prep after Phase 0.

Phase 2: Staged Gentoo build framework.

Define staged script model with strict idempotency and rerun safety.

stage1: host prep and disk/layout/chroot scaffolding.

stage2: stage3 unpack, mount orchestration, and chroot bootstrap.

stage3: systemd profile selection, world update, locale/timezone/network base.

stage4: container stack prerequisites and Home Assistant host dependency packages.

stage5: compatibility identity layer setup for Supervisor expectations.

stage6: kernel track build and install for both compatibility and modern variants.

stage7: boot configuration, service ordering, and preflight validation hooks.

stage8: Supervisor plus Home Assistant deployment and add-on validation.

Dependency: stage order is serial; verification gates between each stage.

Phase 3: Supervisor compatibility contract on Gentoo.

Provide expected OS identity outputs through managed templates and runtime sync.

Provide expected host metadata response path used by Supervisor checks.

Prepare required mount points and filesystem paths expected by Supervisor workflows.

Ensure Docker/container runtime startup ordering and health before Supervisor launch.

Implement a preflight checker that blocks deployment when any compatibility check fails.

Phase 4: Dual-kernel strategy.

Kernel A (compatibility): conservative config tuned to Supervisor and container feature expectations.

Kernel B (modern): latest stable kernel series with the same required feature matrix.

Maintain separate config artifacts, build outputs, and boot entries.

For WSL use host-level kernel selection; for bare metal use boot menu selection.

Dependency: both kernels must pass identical compatibility preflight.

Phase 5: Validation and template hardening.

Validate Supervisor health and Home Assistant core startup.

Validate add-on lifecycle with Node-RED as mandatory test.

Reboot test under each kernel and rerun compatibility suite.

Generate pass/fail report and artifact bundle for reuse.

Capture arm64 delta notes for future Raspberry Pi Green adaptation.

Relevant files

Windows cmd orchestration for WSL replacement and first-boot bootstrap.
Repository cloning automation and manifest output definitions.
Staged Gentoo scripts stage1 through stage8 with shared helpers.
Compatibility preflight and host identity provisioning scripts.
Dual-kernel configuration and build metadata artifacts.
Validation runner and report templates.
Verification

Direct unregister removes the existing Debian distro when confirmed by user prompt.
Fresh Debian WSL install is verified and baseline tools are present.
All staged scripts are rerunnable without corrupting state.
Both kernels boot and pass required container and namespace feature checks.
Supervisor preflight reports full compatibility pass.
Home Assistant starts cleanly and remains healthy through soak period.
Node-RED add-on installs, starts, updates, and survives reboot on both kernels.
Decisions

Included:
systemd-based Gentoo host.
top prerequisite Windows cmd for WSL distro replacement.
all home-assistant org repositories with prioritized bootstrap subset.
dual-kernel selectable runtime path.
Excluded in first implementation pass:
production arm64 deployment (document design and deltas only).
mandatory Supervisor source patching unless compatibility layer fails.
Further Considerations

Bootstrap distro recommendation:
Option A: latest Debian available in WSL listing (recommended).
Option B: Ubuntu 26.04 if you want parity with earlier workflow.
Kernel compatibility baseline:
Option A: conservative LTS-style config set for Supervisor checks (recommended).
Option B: mirror HAOS kernel config as close as possible, then layer Gentoo-specific deltas.
Repository cloning depth:
Option A: shallow for non-priority repos plus full for key repos (recommended).
Option B: full history for all repos.
