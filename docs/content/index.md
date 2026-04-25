# ServoBox

ServoBox gives you Ubuntu 22.04 PREEMPT_RT environments for robotics without forcing your whole workstation onto an RT kernel. Use it to spin up local RT VMs with automatic CPU pinning and IRQ isolation, or target existing RT machines over SSH in `0.3.0`.

## Fastest Path

If you are new to ServoBox, follow this path:

1. [Install ServoBox](getting-started/installation.md#install-servobox)
2. [Configure your host for RT isolation](getting-started/installation.md#host-rt-setup-required-for-deterministic-latency)
3. [Create your first VM](getting-started/run.md#create-your-first-vm)
4. [Verify latency and RT configuration](getting-started/run.md#start-and-verify)
5. [Install a stack or package](getting-started/run.md#install-your-first-stack)

## Quick Start

### Prerequisites

- Ubuntu 22.04 or 24.04 on the host
- 6 CPU cores minimum, 8+ recommended
- 8 GB RAM minimum, 16+ GB recommended
- Hardware virtualization enabled

### 1. One-Line Install

```console
curl -fsSL https://www.servobox.dev/install.sh | sudo bash
```

### 2. Configure the host once

Host-side CPU isolation is required if you want deterministic VM latency. Follow the exact steps in [Installation](getting-started/installation.md#host-rt-setup-required-for-deterministic-latency).

### 3. Create, start, and verify

```console
servobox init
servobox start
servobox rt-verify
servobox test --duration 30 --stress-ng
```

### 4. Install and run a stack

```console
servobox pkg-install --list
servobox pkg-install deoxys-control
servobox run deoxys-control
```

## What ServoBox Helps With

- Running real-time control loops inside isolated Ubuntu RT environments
- Keeping the host available for perception, planning, development, and GPU workloads
- Installing common robotics stacks with `servobox pkg-install`
- Verifying RT behavior with `servobox rt-verify` and `servobox test`
- Working against remote RT targets such as Jetson or NUC systems via SSH

## Where To Go Next

<div class="grid cards" markdown>

- **Installation**

  Host prerequisites, APT install, upgrades, and host RT setup.

  [Open installation guide](getting-started/installation.md)

- **First Run**

  Create a VM, start it, verify RT behavior, and install your first stack.

  [Open first run guide](getting-started/run.md)

- **Commands**

  Full CLI reference for VM lifecycle, testing, networking, packages, and remote mode.

  [Open commands reference](user-guide/commands.md)

- **Packages**

  Package install workflow, install modes, remote targets, and custom recipes.

  [Open package management](user-guide/package-management.md)

- **Troubleshooting**

  Common failures, checks, and recovery steps.

  [Open troubleshooting](reference/troubleshooting.md)

- **RT Tuning**

  Detailed explanation of the RT optimizations and performance modes.

  [Open RT tuning reference](reference/rt-tuning.md)

</div>

## Why This Approach

ServoBox is built for robotics workstations where you want low-latency control without sacrificing the rest of the machine. The RT workload lives in the VM or remote target, while the host stays usable for development, vision, planning, and debugging.

