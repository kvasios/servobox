# Concept Overview

ServoBox is for robotics workstations that need low-latency control without giving up the rest of the machine.

## Core Idea

Keep the host on a normal Ubuntu kernel for development, GPU workloads, perception, and planning. Run the latency-sensitive control workload inside:

- a local Ubuntu PREEMPT_RT VM created by ServoBox, or
- a remote RT machine reached over SSH in `0.3.0`

This keeps the real-time part isolated while the host stays practical for day-to-day work.

## What ServoBox Automates

- VM creation from a prepared Ubuntu RT image
- CPU pinning and IRQ steering for the VM
- RT verification and latency testing
- package installation for common robotics stacks
- project-local defaults via `.servobox/config`
- a consistent CLI across local VMs and supported remote targets

## When It Fits Best

ServoBox is a strong fit when:

- you want RT control alongside GPU-heavy or desktop workloads on the host
- you want a repeatable robotics setup instead of hand-rolling PREEMPT_RT environments
- you want VM and package defaults checked into each client project
- you want package install helpers and built-in RT verification

## When To Read More

- For setup: [Installation](installation.md)
- For your first workflow: [First Run](run.md)
- For the Ubuntu Pro RT comparison: [FAQ](../reference/faq.md#why-not-just-use-ubuntu-pro-rt-kernel)
- For detailed tuning internals: [RT Tuning](../reference/rt-tuning.md)
