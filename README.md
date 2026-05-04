# Gentoo + Home Assistant Hybrid Automation

This repository contains automation to:
- Recreate the WSL bootstrap distro (Debian on WSL2).
- Clone Home Assistant organization repositories.
- Build a staged Gentoo host with systemd.
- Prepare Home Assistant Supervisor compatibility checks.
- Validate the final Home Assistant stack.
- Produce a pure-VM live ISO artifact after staged build completion.

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
- `scripts/gentoo/stage1.sh` ... `scripts/gentoo/stage11.sh`
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
