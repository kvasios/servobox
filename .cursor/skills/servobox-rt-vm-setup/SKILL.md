---
name: servobox-rt-vm-setup
description: Guides ServoBox RT VM setup, Ubuntu Real-time KVM host tuning, libvirt CPU pinning, cyclictest latency measurement, stress-ng RT performance validation, package installation, and remote RT target workflows. Use when the user mentions ServoBox setup, RT VM setup, PREEMPT_RT, Ubuntu real-time, KVM, libvirt, cyclictest, latency histograms, stress-ng, rt-verify, host NICs, package recipes, or remote targets.
---

# ServoBox RT VM Setup

## Workflow

1. Establish the target:
   - Local VM: use `servobox init`, `servobox start`, `servobox rt-verify`, and `servobox test`.
   - Remote RT machine: check `SERVOBOX_TARGET_IP`, `SERVOBOX_TARGET_USER`, and `SERVOBOX_TARGET_PORT`.

2. Check project defaults:
   - If a client project has `.servobox/config`, read it before suggesting commands.
   - If no config exists and defaults are needed, suggest `servobox config init`.

3. Local VM setup path:
   - Create/import the VM with `servobox init`.
   - Use `--vcpus`, `--mem`, `--disk`, `--host-nic`, or `--choose-nic` only when the user has provided the hardware or networking requirement.
   - Start with `servobox start`; use `--performance` or `--extreme` only when the user explicitly wants more aggressive latency tuning and accepts power/thermal tradeoffs.
   - Validate with `servobox rt-verify` and `servobox test --duration 30 --stress-ng`.

4. Ubuntu Real-time KVM tuning path:
   - Read [ubuntu-kvm-rt-reference.md](ubuntu-kvm-rt-reference.md) before changing host isolation, VM CPU pinning, libvirt XML, or cloud-init RT kernel setup.
   - Prefer KVM hardware virtualization for RT VMs; avoid QEMU full emulation for latency-sensitive workloads.
   - Pick isolated host CPUs from the same NUMA/cache topology when possible; use `lstopo`, `nproc`, `lscpu`, and `/sys/devices/system/cpu/online` to confirm.
   - Do not isolate CPU 0; leave at least one non-isolated CPU per socket for host housekeeping, interrupts, RCU callbacks, and emulator threads.
   - Keep host isolated CPU ranges, VM `isolcpus` ranges, and libvirt `<vcpupin>` assignments consistent.
   - For libvirt tuning, check `<cputune>`, `<cpu mode='host-passthrough'>`, `<memoryBacking>`, `<pmu state='off'>`, and `<memballoon model='none'>`.

5. Latency and RT performance path:
   - Read [ubuntu-rt-latency-reference.md](ubuntu-rt-latency-reference.md) before explaining raw `cyclictest` output, histogram generation, or stress-load methodology.
   - Prefer ServoBox validation first: `servobox rt-verify` and `servobox test --duration 30 --stress-ng`.
   - For manual checks, use `cyclictest` from `rt-tests`; the `Max` value per CPU is the key deadline-risk signal.
   - Use fixed `--loops` or `--duration` values when comparing runs; record whether results are in microseconds or nanoseconds.
   - Run latency tests under production-like load when possible, commonly with `stress-ng`, so results reflect realistic contention.

6. Package and recipe path:
   - List available packages with `servobox pkg-install --list`.
   - Install recipes with `servobox pkg-install <package-or-config>`.
   - Run workloads with `servobox run <recipe-name>` or `servobox run "<command>"`.

7. Troubleshooting path:
   - For VM accessibility, check `servobox status`, `servobox ip`, and `servobox ssh`.
   - For RT issues, check `servobox rt-verify`, CPU pinning, IRQ affinity, CPU governor, kernel command line, isolated CPU lists, and cyclictest output.
   - For networked robots, inspect `servobox network-setup` and direct NIC/macvtap configuration.

## Guardrails

- Do not run destructive commands such as `servobox destroy`, `virsh destroy`, or storage deletion unless the user explicitly asks.
- Do not assume a remote target is safe to reconfigure; ask before changing kernel, IRQ, governor, or package state on remote hardware.
- Keep recommendations command-oriented and concise.
- Follow the project CLI tone rule: no emojis, no hype, no decorative status glyphs.
