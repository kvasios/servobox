# ServoBox 🦾📦

<div align="center">
  <img src="docs/content/assets/images/servobox.png" alt="ServoBox Logo" width="350">
</div>

<!-- Build status - Release & Downloads -->
<p align="center">
  <a href="https://github.com/kvasios/servobox/actions/workflows/release.yml">
    <img src="https://github.com/kvasios/servobox/actions/workflows/release.yml/badge.svg" alt="Release pipeline">
  </a>
  <a href="https://github.com/kvasios/servobox/releases">
    <img src="https://img.shields.io/github/v/release/kvasios/servobox?display_name=tag&sort=semver" alt="Latest release">
  </a>
  <a href="https://www.servobox.dev/">
    <img src="https://img.shields.io/badge/docs-servobox.dev-blue?style=flat&logo=github" alt="Documentation">
  </a>
</p>

**Launch real-time VMs for robotics & control applications.**

ServoBox gives you Ubuntu 22.04 VMs with PREEMPT_RT kernel, automatic CPU pinning, and IRQ isolation. **Includes one-command installation for major Robot control packages** (libfranka, franka-ros, franka-ros2, polymetis, deoxys-control, SERL, franky, CRISP controllers) and ROS/ROS2 stacks. No manual configuration needed.

## Installation

**Install via APT**

```bash
# Install ServoBox keyring
sudo wget -O /usr/share/keyrings/servobox-archive-keyring.gpg https://www.servobox.dev/apt-repo/servobox-archive-keyring.gpg

# Add the repository to your sources list
echo "deb [signed-by=/usr/share/keyrings/servobox-archive-keyring.gpg] https://www.servobox.dev/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/servobox.list

# Update package lists and install
sudo apt update
sudo apt install servobox

# Upgrade to latest published release later
sudo apt update
sudo apt install --only-upgrade servobox

# Check which version APT sees and from where
apt-cache policy servobox
```

**Create your VM**

```bash
# It will download the ubuntu img with rt kernel & prep the VM
servobox init
```

**Servobox VM Network Setup for Device Communication**

```
# Configure direct device connections (optional)
servobox network-setup  # Interactive wizard shows available NICs with IPs
```

**Configure host for RT performance** (required for rt - do this once)

```bash
# IMPORTANT: First check your CPU count
nproc  # Must have 6,ideally 8+ cores for safe RT isolation

# Edit /etc/default/grub and set (example for 8-core system):
sudo vim /etc/default/grub # or any editor
# add GRUB_CMDLINE_LINUX_DEFAULT="quiet splash isolcpus=managed_irq,domain,2-5 nohz_full=2-5 rcu_nocbs=2-5 irqaffinity=0-1"

sudo update-grub
sudo reboot
```

## Quick Start

Once installed, you can simply start the VM and test it:

```bash
# Start the VM (balanced mode - default)
servobox start

# Or use performance mode for <100μs max latency
# servobox start --performance

# Validate RT performance (results should be green!)
servobox test --duration 10 --stress-ng
```

**Performance Modes:**
- **Balanced** (default): avg ~3-6μs, max ~100-120μs, normal power — **recommended for all users**
- **Performance** (`--performance`): avg ~3-6μs, max ~100μs (fewer spikes), +20W — for 99.99% timing
- **Extreme** (`--extreme`): avg ~3-6μs, max ~100μs (rare spikes), high power — experimental only

*Note: ~100μs represents the VM latency ceiling. Performance/Extreme modes reduce spike frequency, not max latency.*

You servobox RT VM is now ready for use! Check next section for installing one of the polular RT control packages with the `servobox pkg-install` option.

## Package Installation

Install pre-configured software stacks.

Check the available packages with

```bash
servobox pkg-install --list
```

You can e.g then simply install one of them with:

```bash
# polymetis server by facebook research for the Franka Robot (gen1)
# https://facebookresearch.github.io/fairo/polymetis/index.html
servobox pkg-install polymetis
```
And start spinning the server with one command

```bash
servobox run polymetis
```

Now you should be ready to start development in your host workstation by just simply running:

```bash
# Make sure you follow the installation instructions at host:
# https://facebookresearch.github.io/fairo/polymetis/installation.html
robot = RobotInterface(
        ip_address="192.168.122.100",
        enforce_version=False
    )
```

Enjoy dev :)

## What You Get

- Ubuntu 22.04 with PREEMPT_RT kernel (6.8.0-rt8)
- Automatic CPU pinning and IRQ isolation
- Pre-configured for deterministic control loops
- Package manager for robotics software (ROS2, ros2_control, franka, etc)

## Why not just Ubuntu Pro RT Kernel?

ServoBox's VM-based approach is ideal for robotics workstations that need both RT control and high-throughput processing:

- **GPU Compatibility** - Ubuntu Pro RT kernels conflict with NVIDIA drivers; ServoBox keeps your host GPU-enabled for ML/vision
- **Throughput Preservation** - RT kernels optimize for latency system-wide; ServoBox isolates RT to dedicated cores while maintaining host throughput
- **Isolated Environments** - Run multiple RT configurations without kernel changes

Ubuntu Pro RT is excellent for dedicated RT systems. ServoBox excels when you need RT control alongside perception, planning, and development tools on a single Workstation PC. [See detailed comparison →](https://www.servobox.dev/reference/faq/#why-not-just-use-ubuntu-pro-rt-kernel)

## Commands

```bash
servobox init [--vcpus N] [--mem MiB] [--disk GB]  # Create VM (defaults are good)
servobox start                                      # Start VM (auto-pins CPUs)
servobox test --duration 30 --stress-ng            # Validate RT performance
servobox ssh                                        # Connect to VM
servobox status                                     # Show VM info
servobox ip                                         # Get VM IP address
servobox stop                                       # Shutdown VM
servobox destroy                                    # Remove VM
servobox network-setup                              # Configure direct device NICs
servobox pkg-install <package>                     # Install packages (ROS2, etc)
servobox run <package>                             # Execute package run.sh script in VM 
```

## Use Cases

- Real-time robot control (1kHz+ control loops)
- Software/Hardware-in-the-loop testing
- Isolated testing of time-critical code

## Compatibility

**Tested:** Ubuntu 22.04 & 24.04 Host PC, Intel i5-13700, Franka Robot (gen1)  
**Expected to work:** AMD CPUs
**Not yet validated:** Franka FR3 (builds OK, needs runtime testing) or other robotic platforms with high-frequency RT control API capabilities.

ServoBox is an indie project. Testing with AMD systems, Franka FR3 hardware or any other type of system? Please share results on GitHub!

## Contributing

ServoBox welcomes contributions! We're particularly interested in:
- Testing on AMD CPUs and different host configurations
- Runtime validation with Franka FR3
- New package recipes for other robot platforms

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

ServoBox uses sudo only for necessary RT configuration and VM management. All operations are transparent and auditable. See [SECURITY.md](SECURITY.md) for a complete security audit and best practices.

## Citation

If you use ServoBox in your research or development work, please cite it as:

```bibtex
@software{servobox2025,
  title={ServoBox: Real-time VM Platform for Robotics},
  author={Vasios, Konstantinos},
  year={2025},
  url={https://github.com/kvasios/servobox},
  note={Software for creating Ubuntu VMs with PREEMPT_RT kernel, automatic CPU isolation, and package management system for robotics & control software}
}
```

Or in plain text:
> Vasios, K. (2025). ServoBox: Real-time VM Platform for Robotics. GitHub. https://github.com/kvasios/servobox

## License

MIT License - Use freely in any project, commercial or open source.

**Need help deploying ServoBox in production?**  
Consulting and custom integration services available: **konstantinos.vasios@gmail.com**
