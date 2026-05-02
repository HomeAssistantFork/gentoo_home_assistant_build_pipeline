# arm64 Delta Notes

This document tracks differences required to move the x86_64 GentooHA flow to arm64 (Raspberry Pi Green and generic arm64 VMs).

## Current status

- x86_64 is the primary validated target.
- arm64 is design-documented but not yet fully validated end-to-end.

## Kernel and boot deltas

- Use arm64 Gentoo profile and stage3 tarball in stage2/stage3.
- Ensure kernel config includes:
  - cgroup v2
  - overlayfs
  - netfilter + nft/iptables compatibility modules
  - namespaces and seccomp
  - AppArmor and audit (if policy enforcement is desired)
- Bootloader changes:
  - UEFI arm64 uses `grub-efi-arm64`.
  - SBC flows may need U-Boot or vendor firmware flow instead of GRUB.

## Container/runtime deltas

- Verify Docker package availability and keywording for arm64 in Gentoo profile.
- Confirm os-agent asset selection for arm64 (`aarch64` release artifact).
- Confirm Home Assistant Supervisor image architecture in `/etc/hassio.json`.

## Validation deltas

- Run `scripts/compat/preflight_ha_supervisor.sh` on arm64 and archive output.
- Run `scripts/validation/run_validation_bundle.sh` with `KERNEL_TRACK` labels for each kernel variant.
- Node-RED lifecycle test requires `SUPERVISOR_TOKEN` and should be validated on arm64 as well.

## Open items

- Add automated os-agent URL selection for arm64 in stage8.
- Add arm64 ISO profile for stage10 live build.
- Validate reboot + revalidation flow on arm64 VM and on target SBC.
