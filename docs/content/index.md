# ServoBox 🦾📦

<div align="center">
  <img src="assets/images/servobox.png" alt="ServoBox Logo" width="300">
</div>

**Launch real-time VMs for robotics in a few steps.**

ServoBox gives you Ubuntu 22.04 VMs with PREEMPT_RT kernel, automatic CPU pinning, and IRQ isolation. No manual configuration needed.

<div style="text-align: center; margin: 2rem 0;">
  <div style="position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden; max-width: 100%; margin: 0 auto;">
    <iframe 
      style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;" 
      src="https://www.youtube.com/embed/EWkQHdm_uto?si=qQz0mVsXja7nM4f8" 
      title="YouTube video player" 
      frameborder="0" 
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" 
      referrerpolicy="strict-origin-when-cross-origin" 
      allowfullscreen>
    </iframe>
  </div>
</div>

---

## 🚀 Quick Start

**Prerequisites:** Ubuntu 22.04+ or 24.04, 6, ideally 8+ cores, 8GB, ideally 16GB+ RAM, hardware virtualization enabled (Intel VT-x or AMD-V)

### 1. Install ServoBox

```console
# Add ServoBox repository using wget (pre-installed on Ubuntu)
wget -qO- https://www.servobox.dev/apt-repo/servobox-apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/servobox-apt-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/servobox-apt-keyring.gpg] https://www.servobox.dev/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/servobox.list

# Install
sudo apt update
sudo apt install servobox
```

### 2. Configure Host (Required for RT)

```console
# ⚠️ **WARNING:** Check your CPU count first with:
nproc  

#You need 6+, ideally 8+ cores
```

```console
# Edit GRUB for CPU isolation
sudo vim /etc/default/grub # or with any other editor

# Add the following settings to the GRUB_CMDLINE_LINUX_DEFAULT variable
# GRUB_CMDLINE_LINUX_DEFAULT="quiet splash isolcpus=managed_irq,domain,1-4 nohz_full=1-4 rcu_nocbs=1-4 irqaffinity=0"
```
Finalize with:

```console
sudo update-grub
sudo reboot
```

### 3. Create Your First RT VM

```console
servobox init
```

### 4. Start and Test

```console
# Configure networking for communication with network devices if needed (interactive wizard)
servobox network-setup
```

```console
# Start VM (balanced mode - default)
servobox start

# Or use performance mode for <100μs max latency (locks CPU frequencies)
# servobox start --performance
```
```console
# Test RT performance
servobox test --duration 30 --stress-ng
```
**That's it!** You now have a real-time, low-latency VM ready for control.

!!! tip "Performance Modes"
    - **Balanced** (default): avg ~4μs, max ~100-120μs, normal power - **recommended**
    - **Performance** (`--performance`): avg ~3μs, max ~100μs (fewer spikes), +20W
    - **Extreme** (`--extreme`): avg ~3μs, max ~100μs (rare spikes), high power
    
    The ~100μs ceiling is the VM latency limit. Performance/Extreme modes reduce spike frequency for tighter timing guarantees. See [RT Tuning Reference](reference/rt-tuning.md#performance-modes) for details.

### 5. Install & run your favorite stack!

```console
# Install robotics software
servobox pkg-install deoxys-control
servobox run deoxys-control
```

---

## What ServoBox Does

ServoBox automates the complex setup of real-time Linux environments for robotics:

- **🚀 One-Command Setup** - `servobox init` creates fully configured RT VMs
- **⚡ PREEMPT_RT Kernel** - Ubuntu 22.04 with kernel 6.8.0-rt8 baked in  
- **🎯 Automatic CPU Pinning** - Intelligent CPU isolation and IRQ affinity
- **📦 Package Manager** - Pre-built recipes for common robotics control stacks
- **✅ Performance Testing** - Built-in cyclictest with stress testing
- **🔧 Zero Configuration** - Works out of the box with sensible defaults

For a complete breakdown of ServoBox's RT optimizations, see the [Real-Time Tuning Reference](reference/rt-tuning.md).

## Why ServoBox?

**Problem:** Setting up real-time Linux for robotics is complex and error-prone.

**Solution:** ServoBox isolates RT workloads to dedicated CPU cores in VMs while keeping your host optimized for ML/vision with full GPU support.

**Key Principle:** VM handles real-time control, host handles high-level processing.

---

## Architecture Overview

ServoBox follows a **host-VM separation** architecture optimized for real-time robotics:

```
┌─────────────────────────────────────────────────┐
│              Host System (Ubuntu)               │
│  ┌───────────────────────────────────────────┐  │
│  │  High-Level Processing                    │  │
│  │  - Perception & Vision                    │  │
│  │  - Planning & Decision Making             │  │
│  │  - User Interfaces                        │  │
│  │  - Development Tools                      │  │
│  └───────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────┐  │
│  │  Isolated CPUs (1-4)                      │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │   ServoBox VM (Ubuntu 22.04 RT)     │  │  │
│  │  │   - PREEMPT_RT Kernel 6.8.0-rt8     │  │  │
│  │  │   - Real-Time Control Loops         │  │  │
│  │  │   - Low-Latency Robot Control       │  │  │
│  │  │   - Package recipes (ROS2, etc)     │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
│  CPU 0: Host + IRQs    CPUs 1-4: RT Isolated    │
└─────────────────────────────────────────────────┘
```

## Use Cases

- **Real-time Robot Control** - 1kHz+ control loops with deterministic latency
- **Hardware-in-the-Loop Simulation** - Test algorithms before hardware deployment  
- **Motion Control Development** - Isolated environment for time-critical code
- **RT Algorithm Testing** - Validate performance before production
- **Robotics Education** - Learn RT concepts without bare-metal setup

---

## Documentation

<div class="grid cards" markdown>

-   :material-play:{ .lg .middle } **Run**

    ---

    Create and manage real-time VMs

    [:octicons-arrow-right-24: Run Guide](getting-started/run.md)

-   :material-download:{ .lg .middle } **Installation**

    ---

    Detailed installation and configuration

    [:octicons-arrow-right-24: Installation](getting-started/installation.md)

-   :material-book-open-variant:{ .lg .middle } **User Guide**

    ---

    Learn about all commands and features

    [:octicons-arrow-right-24: User Guide](user-guide/commands.md)

 -   :material-lifebuoy:{ .lg .middle } **Troubleshooting**
 
     ---
 
     Diagnose and resolve common issues
 
     [:octicons-arrow-right-24: Troubleshooting](reference/troubleshooting.md)

-   :material-speedometer:{ .lg .middle } **RT Tuning**

    ---

    Complete reference of all real-time optimizations

    [:octicons-arrow-right-24: RT Tuning](reference/rt-tuning.md)

</div>

---

## Community & Support

- **Issues**: [GitHub Issues](https://github.com/kvasios/servobox/issues)
- **Discussions**: [GitHub Discussions](https://github.com/kvasios/servobox/discussions)  
- **Email**: [konstantinos.vasios@gmail.com](mailto:konstantinos.vasios@gmail.com)

## License

ServoBox is licensed under **MIT**. See the LICENSE file for details.

---

**Ready to dive deeper?** Check out the [Run Guide](getting-started/run.md) for detailed examples and advanced configuration →

