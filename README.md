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

**Launch real-time VMs for robotics in seconds.**

ServoBox gives you Ubuntu 22.04 VMs with PREEMPT_RT kernel, automatic CPU pinning, and IRQ isolation. **Includes one-command installation for major Robot control packages** (libfranka, franka-ros, franka-ros2, polymetis, deoxys-control, SERL, franky, CRISP controllers) and ROS/ROS2 stacks. No manual configuration needed.

## Installation

**Install via APT (Recommended)**

```bash
# Add the ServoBox APT repository
curl -sSL https://www.servobox.dev/apt-repo/servobox-apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/servobox-apt-keyring.gpg

# Add the repository to your sources list
echo "deb [signed-by=/usr/share/keyrings/servobox-apt-keyring.gpg] https://www.servobox.dev/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/servobox.list

# Update package lists and install
sudo apt update
sudo apt install servobox
```

**Or download from releases**

```bash
# Download latest release (check https://github.com/kvasios/servobox/releases for latest version)
wget https://github.com/kvasios/servobox/releases/download/v0.1.1/servobox_0.1.1_amd64.deb
sudo apt install -f ./servobox_0.1.1_amd64.deb
```

**Create your VM**

```bash
servobox init

# Configure direct device connections
servobox network-setup  # Interactive wizard shows available NICs with IPs

# Or specify directly during init if you know device names:
# servobox init --host-nic eth0 --host-nic eth1
```

**Configure host for RT performance** (required for rt - do this once)

```bash
# Configure CPU isolation in GRUB (adjust CPU range for your system)
# Edit /etc/default/grub and set:
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash isolcpus=managed_irq,domain,1-4 nohz_full=1-4 rcu_nocbs=1-4 irqaffinity=0"

sudo update-grub
sudo reboot
```

## Quick Start

Once installed, you can simply start the VM and test it:

```bash
# Start the VM
servobox start

# Validate RT performance (results should be green!)
servobox test --duration 30 --stress-ng
```
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

### Package Execution

Many packages include an optional `run.sh` script that defines how to execute the package in the VM. Use the `servobox run` command to execute these scripts:

```bash
# Run a package that has run.sh
servobox run polymetis

# Run with specific VM name
servobox run polymetis --name my-vm

```

### Custom Recipes

Test your own recipes directly from Host PC with:

```bash
# Create your recipe directory
mkdir -p ~/my-recipes/my-package
cd ~/my-recipes/my-package

# Create recipe files (see packages/recipes/example-custom/ for template)
vim recipe.conf install.sh

# Optional: Add run.sh for package execution
vim run.sh

# Test your custom recipe
servobox pkg-install --recipe-dir ~/my-recipes my-package

# Run your package (if run.sh exists)
servobox run my-package
```

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

## Building from Source

```bash
git clone https://github.com/kvasios/servobox.git
cd servobox
dpkg-buildpackage -us -uc -B
sudo dpkg -i ../servobox_*.deb
```

## Compatibility

**Tested:** Ubuntu 22.04, Intel i5-13700, Franka Robot (gen1)  
**Expected to work:** AMD CPUs, Ubuntu 20.04 or newer
**Not yet validated:** Franka FR3 (builds OK, needs runtime testing)

ServoBox is an indie project. Testing with AMD systems or Franka FR3 hardware? Please share results on GitHub!

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
