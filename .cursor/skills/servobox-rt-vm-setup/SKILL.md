---
name: servobox-rt-vm-setup
description: Guides ServoBox RT VM setup, host PREEMPT_RT tuning, latency validation, package installation, and remote RT target workflows. Use when the user mentions ServoBox setup, RT VM setup, PREEMPT_RT, cyclictest latency, rt-verify, host NICs, package recipes, or remote targets.
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

4. Package and recipe path:
   - List available packages with `servobox pkg-install --list`.
   - Install recipes with `servobox pkg-install <package-or-config>`.
   - Run workloads with `servobox run <recipe-name>` or `servobox run "<command>"`.

5. Troubleshooting path:
   - For VM accessibility, check `servobox status`, `servobox ip`, and `servobox ssh`.
   - For RT issues, check `servobox rt-verify`, CPU pinning, IRQ affinity, CPU governor, and cyclictest output.
   - For networked robots, inspect `servobox network-setup` and direct NIC/macvtap configuration.

## Guardrails

- Do not run destructive commands such as `servobox destroy`, `virsh destroy`, or storage deletion unless the user explicitly asks.
- Do not assume a remote target is safe to reconfigure; ask before changing kernel, IRQ, governor, or package state on remote hardware.
- Keep recommendations command-oriented and concise.
- Follow the project CLI tone rule: no emojis, no hype, no decorative status glyphs.
