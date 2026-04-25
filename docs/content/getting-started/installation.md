# Installation

This guide covers host requirements, installation methods, and the one host-side RT configuration step that ServoBox depends on for deterministic latency.

## Requirements

- **Host OS:** Ubuntu 22.04 or greater
- **CPU:** 6 cores minimum, 8+ recommended
- **Memory:** 8 GB minimum, 16+ GB recommended
- **Disk:** 20 GB free space for the default VM
- **Virtualization:** KVM/QEMU with Intel VT-x or AMD-V enabled

## Install ServoBox

### One-Line Install

```console
curl -fsSL https://www.servobox.dev/install.sh | sudo bash
```

If you prefer to inspect the installer first:

```console
curl -fsSL https://www.servobox.dev/install.sh -o install.sh
less install.sh
sudo bash install.sh
```

### Manual APT Repository Install

```console
sudo wget -O /usr/share/keyrings/servobox-archive-keyring.gpg https://www.servobox.dev/apt-repo/servobox-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/servobox-archive-keyring.gpg] https://www.servobox.dev/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/servobox.list
sudo apt update
sudo apt install servobox
```

To upgrade later:

```console
sudo apt update
sudo apt install --only-upgrade servobox
apt-cache policy servobox
```

### GitHub release package

APT is the easiest path, but you can also install the current release package directly:

```console
wget https://github.com/kvasios/servobox/releases/download/v0.3.0/servobox_0.3.0_amd64.deb
sudo apt install -f ./servobox_0.3.0_amd64.deb
```

### Build from source

```console
git clone https://github.com/kvasios/servobox.git
cd servobox
dpkg-buildpackage -us -uc -B
sudo dpkg -i ../servobox_*.deb
```

## Host RT Setup Required For Deterministic Latency

!!! warning "Required for low-latency workloads"
    ServoBox automates the VM-side setup, but the host still needs isolated CPU cores. Without host isolation you should expect latency spikes.

### 1. Check CPU count

```console
nproc
```

If you have fewer than 6 CPU cores, ServoBox may still run, but you will have very limited room for safe isolation.

### 2. Edit the GRUB kernel command line

Open `/etc/default/grub` and update `GRUB_CMDLINE_LINUX_DEFAULT`.

```console
sudo vim /etc/default/grub
```

Example for an 8-core host:

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash isolcpus=managed_irq,domain,1-4 nohz_full=1-4 rcu_nocbs=1-4 irqaffinity=0-1"
```

Meaning of the important parameters:

- `isolcpus=managed_irq,domain,1-4`: reserves CPUs `1-4` away from normal scheduling
- `nohz_full=1-4`: removes periodic scheduler ticks from those CPUs
- `rcu_nocbs=1-4`: moves RCU work off those CPUs
- `irqaffinity=0-1`: keeps interrupts on the non-isolated host cores

Adjust the CPU ranges to match your machine. Keep at least one or two non-isolated cores for the host.

### 3. Apply and reboot

```console
sudo update-grub
sudo reboot
```

### 4. Verify the host isolation state

After reboot:

```console
cat /sys/devices/system/cpu/isolated
```

The output should match the CPU range you isolated, such as `1-4`.

## Sanity Check

Confirm that ServoBox is installed and available:

```console
servobox --help
```

## Next Step

Continue with the [First Run guide](run.md) to create your first VM, verify the RT setup, and install a stack.

## Troubleshooting

### Permission denied accessing libvirt resources

Check your groups:

```console
groups "$USER"
```

If needed:

```console
sudo usermod -aG libvirt "$USER"
newgrp libvirt
```

### Virtualization not available

1. Make sure VT-x or AMD-V is enabled in BIOS/UEFI.
2. Check that KVM modules are loaded with `lsmod | grep kvm`.
3. Reinstall the KVM/libvirt packages if the system is incomplete.

For broader diagnostics, see [Troubleshooting](../reference/troubleshooting.md).

