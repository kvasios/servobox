# Frequently Asked Questions

## General

### What is ServoBox?

ServoBox is a tool for creating and managing Ubuntu 22.04 VMs with PREEMPT_RT kernel optimized for robotics development. It automates CPU isolation, IRQ affinity, and provides pre-built packages for common robotics software.

### Why not just use Ubuntu Pro RT kernel?

**Great question!** Ubuntu Pro makes RT kernels available with `apt install linux-realtime`, but ServoBox's VM-based approach solves critical limitations:

**🚫 NVIDIA GPU Conflicts**

Ubuntu Pro RT kernels **break NVIDIA drivers**. The proprietary NVIDIA drivers don't support PREEMPT_RT kernels, causing:

- Driver installation failures
- System instability and crashes  
- Loss of GPU acceleration for ML/vision workloads

**ServoBox solution:** Keep your host on standard kernel with full NVIDIA support, run RT workloads in isolated VMs.

**⚡ Host Throughput Preservation**

Ubuntu Pro RT kernels optimize the **entire system** for low latency, sacrificing:

- High-throughput workloads (data processing, ML training)
- Background services performance
- General desktop responsiveness

RT kernels prioritize worst-case latency over average-case throughput. This makes the entire system slower for non-RT tasks.

**ServoBox solution:** Isolate RT workloads to dedicated CPU cores while keeping your host optimized for throughput on remaining cores.

**🔧 Additional Benefits**

- **Zero host kernel modifications** - No kernel changes, no system-wide RT impact, no risk
- **Multiple RT environments** - Run different RT kernel versions and configurations simultaneously
- **Easy experimentation** - Delete VM vs. complicated kernel rollback
- **Pre-configured packages** - One-command installation of robotics software stacks
- **Development isolation** - Test RT code without affecting host stability
- **Reproducible environments** - Share VM configs across teams with exact same behavior

**When Ubuntu Pro RT might be better:**

- Bare metal robots with no ML/vision workloads
- Systems without NVIDIA GPUs
- You need <20μs latencies AT ALL TIMES - ZERO EXCEPTIONS
- Single-purpose dedicated RT systems

For most robotics development workstations running perception + control, ServoBox's isolation approach is superior.

!!! info "Deep Dive"
    For a complete technical breakdown of ServoBox's real-time optimizations, see the [Real-Time Tuning Reference](rt-tuning.md).

### What has been tested?

Here's the current testing status:

**✅ Tested and Verified:**

- **Host System:** Ubuntu 22.04 with Intel i5-13700 (16 cores, 20 threads), 64GB RAM
- **Robot Hardware:** Franka Emika Robot (1st generation) - runtime tested
- **Packages (runtime tested):**
  - libfranka-gen1
  - polymetis (Franka gen1)
  - franka-ros (Franka gen1)

**⚠️ Built but NOT Runtime Tested:**

- **AMD CPUs** - Should work (KVM/QEMU is CPU-agnostic) but not verified
- **Franka FR3 packages** - Builds successfully but needs runtime validation with actual FR3 hardware
- **Other robot platforms** - Recipes available but need testing

**🤝 Contributors Welcome!**

I'd especially welcome testing and feedback on:

- AMD Ryzen systems (different CPU architectures)
- Franka FR3 robot runtime (current generation)
- Other robot platforms (UR, ABB, KUKA, etc.)
- Different host configurations (Ubuntu 20.04, 24.04, varying core counts)

If you test ServoBox with different hardware/platforms, please open a GitHub issue or discussion to share your results!

### Why use VMs instead of bare metal?

**VMs offer:**
- Isolated development environments
- Easy testing without risking hardware
- Reproducible configurations
- Quick setup/teardown
- Multiple environments on one machine

**Good for:** Development, testing, simulation
**Not ideal for:** Production deployics robots requiring HARD AT ALL TIMES <20μs latency

### Can I use ServoBox for production robots?

Yes, for many applications! ServoBox VMs achieve low latency under stress, suitable for 1kHz control loops (industrial robots, manipulators).

### What should run in the VM vs host?

**VM (Real-Time):**
- Control loops (1kHz+)
- Robot hardware interfaces
- Motion control algorithms
- Force/torque control

**Host (High-Level):**
- Computer vision and perception
- Path planning and decision making
- User interfaces and visualization
- Development tools and debugging

This separation ensures RT performance while allowing complex processing on the host.

### Will this affect other software on my host?

The host will have fewer CPU cores available for general tasks (isolated cores are dedicated to VMs). For typical desktop/development work, this is fine. Adjust isolation range for your use case.

## Usage

### How many VMs can I run simultaneously?

**Not tested and not advised for RT workloads.** Prefer a single VM and use CPU/process pinning inside that VM to run multiple real-time processes on isolated CPUs.

## Packages

### Can I request new packages?

Yes! Open an issue on GitHub with package details.

### Can I create my own packages?

Absolutely! See [Creating Custom Recipes](../user-guide/package-management.md#creating-custom-recipes).

## Networking

### What's the default VM IP?

`192.168.122.100/24` (configurable with `--ip` flag)

### Can the VM access the internet?

Yes, by default via NAT.

## Troubleshooting

For detailed troubleshooting information, see the [Troubleshooting Guide](troubleshooting.md).

## Advanced

### Can I use custom base images?

Yes:

```console
servobox init --image /path/to/custom.qcow2
```

### Can I modify the RT kernel?

Yes, ServoBox includes scripts to build custom RT kernels. See the [ServoBox repository](https://github.com/kvasios/servobox) for build scripts and documentation.

## Licensing

### Can I use ServoBox commercially?

Certainly! ServoBox is distributed under the MIT License, permitting commercial use with minimal restrictions.

### Do I need a license for robots I build?

No. ServoBox is used for development. Your robot code can have any license.

## Getting Help

- [GitHub Discussions](https://github.com/kvasios/servobox/discussions)
- [GitHub Issues](https://github.com/kvasios/servobox/issues)
- Email: konstantinos.vasios@gmail.com


