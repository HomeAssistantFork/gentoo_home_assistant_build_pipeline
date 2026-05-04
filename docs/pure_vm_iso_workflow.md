# Pure VM and ISO Workflow

This workflow runs GentooHA as a pure VM target. It does not depend on WSL kernel selection.

## Hypervisor choice

Recommended order:

1. Hyper-V (Windows host, easiest networking on Windows)
2. VirtualBox (cross-platform, easy local testing)
3. Xen/KVM stack (Linux host, advanced use)

WSL2 itself cannot swap to your custom guest kernel per distro runtime the same way a full VM can, so custom-kernel validation should be done in a VM.

## End-to-end build pipeline

Run on your build host:

```bash
sudo bash scripts/gentoo/run_all.sh
```

`run_all.sh` now includes:

- stage1 .. stage8 (base + Supervisor)
- stage9 (AppArmor userspace)
- stage10 (internal cleanup)
- stage11 (artifact generation)

## ISO artifact output

Stage11 writes build artifacts to:

- `/var/lib/ha-gentoo-hybrid/artifacts/gentooha-live.iso`

You can override with:

```bash
export ARTIFACT_DIR=/path/to/artifacts
export ISO_NAME=gentooha-live.iso
sudo bash scripts/gentoo/stage10.sh
sudo bash scripts/gentoo/stage11.sh
```

## Booting as a VM

1. Create a new VM in Hyper-V/VirtualBox/Xen.
2. Attach the generated ISO as boot media.
3. Boot the VM and verify systemd + Docker + Supervisor stack.
4. Run validation bundle script:

```bash
export KERNEL_TRACK=compat
sudo bash scripts/validation/run_validation_bundle.sh
```

Repeat for modern kernel boot entry:

```bash
export KERNEL_TRACK=modern
sudo bash scripts/validation/run_validation_bundle.sh
```

## Node-RED validation

Node-RED is not preinstalled by stage scripts. Validation installs and exercises it via Supervisor API only when token is provided.

```bash
export SUPERVISOR_TOKEN=<token>
export REQUIRE_NODERED_TEST=true
sudo bash scripts/validation/run_validation_bundle.sh
```

This validates install/start/restart/update/info lifecycle without baking Node-RED into the base image.
