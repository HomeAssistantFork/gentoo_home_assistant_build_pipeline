# Implementation Guide

## 1) WSL prerequisite on Windows
Run the prerequisite command script from an elevated Command Prompt:

scripts\\windows\\prereq_wsl_debian.cmd

Behavior:
- Deletes an existing Debian WSL distro directly (no backup).
- Installs Debian through WSL catalog.
- Runs apt update, full-upgrade, and base tools install.

## 2) Clone Home Assistant organization repositories
Run in Linux shell after prerequisites:

bash scripts/repos/clone_home_assistant_org.sh

Optional environment variables:
- OUT_DIR
- MANIFEST_DIR
- INCLUDE_ARCHIVED=true|false
- SHALLOW=true|false
- RESUME=true|false

## 3) Build Gentoo staged pipeline
Make scripts executable and run stages in order:

chmod +x scripts/gentoo/*.sh scripts/compat/*.sh scripts/validation/*.sh scripts/repos/*.sh
sudo bash scripts/gentoo/run_all.sh

You can also run each stage individually:
- stage1.sh through stage10.sh

Important inputs:
- STAGE3_TARBALL must point to a valid Gentoo stage3 tarball before stage2.

## 4) Compatibility preflight
Run before and after Supervisor deployment:

sudo bash scripts/compat/preflight_ha_supervisor.sh

## 5) Stack validation
Run post-deployment:

sudo bash scripts/validation/validate_ha_stack.sh

Set SUPERVISOR_TOKEN to validate Node-RED add-on install through Supervisor API.

## 6) Validation artifact bundle (pass/fail report)
Run this after each kernel boot track (compat and modern):

export KERNEL_TRACK=compat
sudo bash scripts/validation/run_validation_bundle.sh

export KERNEL_TRACK=modern
sudo bash scripts/validation/run_validation_bundle.sh

Artifacts are written under:
- artifacts/validation/

## 7) Pure VM ISO generation
Stage10 creates a live ISO artifact for VM testing:

sudo bash scripts/gentoo/stage10.sh

Default output:
- /var/lib/ha-gentoo-hybrid/artifacts/gentooha-live.iso

See docs/pure_vm_iso_workflow.md for Hyper-V/VirtualBox/Xen usage guidance.
