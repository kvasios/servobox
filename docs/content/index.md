# ServoBox 🦾📦

<div align="center">
  <img src="assets/images/servobox.png" alt="ServoBox Logo" width="300">
</div>

**Launch real-time VMs for robotics in seconds.**

ServoBox gives you Ubuntu 22.04 VMs with PREEMPT_RT kernel, automatic CPU pinning, and IRQ isolation. No manual configuration needed.

---

## 🚀 Quick Start

**Prerequisites:** Ubuntu 20.04+ (tested with 22.04 host), 6, ideally 8+ cores, 8GB, ideally 16GB+ RAM, hardware virtualization enabled (Intel VT-x or AMD-V)

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
# IMPORTANT: Check your CPU count first
nproc  # You need 6+ cores for safe RT isolation

# Edit GRUB for CPU isolation
sudo vim /etc/default/grub
```
⚠️ **WARNING:** Adjust CPU range based on YOUR system! The example shows 8-core config.

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash isolcpus=managed_irq,domain,1-4 nohz_full=1-4 rcu_nocbs=1-4 irqaffinity=0"
```

```console
sudo update-grub
sudo reboot
```

See [Installation Guide](getting-started/installation.md#step-2-configure-host-for-rt-performance) for CPU-specific examples.

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
# Start VM
servobox start
```
```console
# Test RT performance
servobox test --duration 30
```
**That's it!** You now have a real-time, low-latency VM ready for control.

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

