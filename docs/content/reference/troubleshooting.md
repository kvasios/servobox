# Troubleshooting

Minimal guide for common ServoBox issues.

## Quick diagnostics

```console
# VM status and IP
servobox status
servobox ip

# RT verification
servobox rt-verify

# Host RT isolation
cat /sys/devices/system/cpu/isolated

# Libvirt health
sudo systemctl status libvirtd
virsh list --all

# Disk space for VM images
df -h /var/lib/libvirt/images
```

## Quick fixes

- Install deps: `sudo apt install -y qemu-kvm libvirt-daemon-system virtinst cloud-image-utils wget xz-utils`
- Add user to groups: `sudo usermod -aG libvirt,kvm $USER && newgrp libvirt`
- Restart libvirt network: `sudo virsh net-destroy default && sudo virsh net-start default`
- Wait for first boot, then retry `servobox ip` and SSH
- Verify RT config: `servobox rt-verify` (VM must be running)

## Common issues

### High latency

Common causes:
1. Host CPU isolation not configured
2. GRUB not updated/rebooted
3. CPU governor not set to performance
4. Other VMs running
5. SMI/firmware interrupts

```console
servobox rt-verify
cat /sys/devices/system/cpu/isolated
cat /proc/cmdline | grep -E 'isolcpus|nohz_full|rcu_nocbs'
```

### VM won't start

Common fixes:
```console
# Check libvirt
sudo systemctl status libvirtd

# Check VM status
virsh list --all

# View detailed error
virsh start my-vm

# If permissions issue
sudo chown -R libvirt-qemu:kvm /var/lib/libvirt/images/servobox/
```

### Can't SSH into VM

Wait 1-2 minutes for cloud-init on first boot. Then:

```console
# Check VM has IP
servobox ip

# Test connectivity
ping $(servobox ip)

# View console
virsh console my-vm

# Check SSH service
sleep 60 && servobox ip
virsh list --all | grep running
virsh console servobox-vm  # check: systemctl status ssh
```

### Package installation fails

```console
# Try with verbose output
servobox pkg-install package-name --verbose

# Check VM has internet
servobox ssh
ping google.com

# Install dependencies first
servobox pkg-install build-essential
```

### VM uses too much disk space

```console
# Check usage
sudo du -sh /var/lib/libvirt/images/servobox/*

# Compact image (VM must be stopped)
servobox stop
cd /var/lib/libvirt/images/servobox/my-vm
sudo qemu-img convert -O qcow2 my-vm.qcow2 compact.qcow2
sudo mv compact.qcow2 my-vm.qcow2
```

### No network / no IP

```console
sudo virsh net-dhcp-leases default
sudo virsh net-destroy default && sudo virsh net-start default
```

## Getting help

Include version, host OS, exact error, steps to reproduce, and diagnostics output when filing an issue: [GitHub Issues](https://github.com/kvasios/servobox/issues)

See also: `Installation` (../getting-started/installation.md), `FAQ` (../reference/faq.md).

