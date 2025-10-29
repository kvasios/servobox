# Installation

This guide walks you through installing ServoBox and configuring your host system for real-time performance.

## Prerequisites

### System Requirements

- **Operating System**: Ubuntu 20.04 or newer (host)
- **CPU**: 4+ cores (minimum 2 for VM + 1 for host)
- **Memory**: 8GB+ RAM
- **Disk Space**: 40GB+ free (the servobox default - can be set to be less)
- **Virtualization**: CPU with Intel VT-x or AMD-V support


## Step 1: Install ServoBox

### Option A: Via APT Repository (Recommended)

Add the ServoBox APT repository and install:

```console
# Add the ServoBox APT repository
curl -sSL https://www.servobox.dev/apt-repo/servobox-apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/servobox-apt-keyring.gpg

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
wget https://github.com/kvasios/servobox/releases/download/v0.1.0/servobox_0.1.0_amd64.deb
```

Install the package:

```console
sudo apt install -f ./servobox_0.1.0_amd64.deb
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

Edit your GRUB configuration:

```console
sudo nano /etc/default/grub
```

Modify or add the `GRUB_CMDLINE_LINUX_DEFAULT` line (adjust CPU range based on your system):

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash isolcpus=managed_irq,domain,1-4 nohz_full=1-4 rcu_nocbs=1-4 irqaffinity=0"
```

### Understanding the Parameters

- `isolcpus=managed_irq,domain,1-4` - Isolate CPUs 1-4 from scheduler
- `nohz_full=1-4` - Disable timer ticks on isolated CPUs
- `rcu_nocbs=1-4` - Move RCU callbacks off isolated CPUs
- `irqaffinity=0` - Pin IRQs to CPU 0

!!! tip "Choosing CPU Range"
    On a 6-core system, `isolcpus=1-4` reserves CPUs 1-4 for RT, leaving CPU 0 and 5 for the host.
    Always leave at least 1-2 CPUs for host operations.

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

### "Missing dependency" error

Install missing packages:

```console
sudo apt install -y qemu-kvm libvirt-daemon-system virtinst \
    cloud-image-utils wget xz-utils
```

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

