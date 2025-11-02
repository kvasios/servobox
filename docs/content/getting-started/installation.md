# Installation

This guide walks you through installing ServoBox and configuring your host system for real-time performance.

## Prerequisites

### System Requirements

- **OS**: Ubuntu 20.04 or newer (host) (tested with 22.04)
- **CPU**: 6+, ideally 8+ cores (4 cores for VM)  
- **Memory**: 8GB+, ideally 16GB RAM
- **Disk**: 40GB+ free space (default VM size, can be configured for less)
- **Virtualization**: KVM/QEMU support (Intel VT-x or AMD-V)


## Step 1: Install ServoBox

### Option A: Via APT Repository (Recommended)

Add the ServoBox APT repository and install:

```console
# Add the ServoBox APT repository using wget (pre-installed on Ubuntu)
wget -qO- https://www.servobox.dev/apt-repo/servobox-apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/servobox-apt-keyring.gpg

# Add the repository to your sources list
echo "deb [signed-by=/usr/share/keyrings/servobox-apt-keyring.gpg] https://www.servobox.dev/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/servobox.list

# Update package lists and install
sudo apt update
sudo apt install servobox
```

### Option B: From Release

Download the latest release:

```console
# Check https://github.com/kvasios/servobox/releases for the latest version
wget https://github.com/kvasios/servobox/releases/download/v0.1.2/servobox_0.1.2_amd64.deb
```

Install the package:

```console
sudo apt install -f ./servobox_0.1.2_amd64.deb
```

### Option C: From Source

Clone the repository:

```console
git clone https://github.com/kvasios/servobox.git
cd servobox
```

Build the package:

```console
dpkg-buildpackage -us -uc -B
```

Install:

```console
sudo dpkg -i ../servobox_*.deb
```

## Step 2: Configure Host for RT Performance

!!! warning "Required Step"
    This step is **required** for real-time performance. Without CPU isolation, you will experience latency spikes.

### Check Your CPU Count First

**IMPORTANT:** Before configuring CPU isolation, check how many CPU cores your system has:

```console
nproc
# Example output: 8 (means you have 8 CPU cores: 0-7), which means you are good.
```

### Edit GRUB Configuration

⚠️ Again proceed here if your CPU cores are 6+,ideally 8+ as stated above.

Edit your GRUB configuration:

```console
sudo vim /etc/default/grub
```

Modify or add the `GRUB_CMDLINE_LINUX_DEFAULT` line. **Example for an 8-core system:**

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash isolcpus=managed_irq,domain,1-4 nohz_full=1-4 rcu_nocbs=1-4 irqaffinity=0"
```

### Understanding the Parameters

- `isolcpus=managed_irq,domain,1-4` - Isolate CPUs 1-4 from scheduler
- `nohz_full=1-4` - Disable timer ticks on isolated CPUs
- `rcu_nocbs=1-4` - Move RCU callbacks off isolated CPUs
- `irqaffinity=0` - Pin IRQs to CPU 0

Apply the configuration and reboot:

```console
sudo update-grub
sudo reboot
```

### Verify Isolation

After reboot, check that CPUs are isolated:

```console
cat /sys/devices/system/cpu/isolated
# Should output: 1-4 (or your configured range)
```

## Step 3: Verify Installation

Check that ServoBox is installed:

```console
servobox --help
```

You should see the ServoBox help message with available commands.


## Next Steps

- [Run Guide](run.md) - Create and manage your first RT VM
 

## Troubleshooting

### Permission denied accessing `/var/lib/libvirt`

First, check if you're already in the required groups:

```console
groups $USER
# Look for 'libvirt' and 'kvm' in the output
```

If you don't see `libvirt` and `kvm` in the list, add your user to the libvirt group:

```console
sudo usermod -aG libvirt $USER
newgrp libvirt
```

### Virtualization not working

1. Check BIOS/UEFI settings - ensure VT-x/AMD-V is enabled
2. Verify kernel modules are loaded: `lsmod | grep kvm`
3. Reinstall QEMU/KVM packages

See the [Troubleshooting Guide](../reference/troubleshooting.md) for more help.

