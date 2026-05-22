# Ubuntu Real-time KVM Reference

Source: https://documentation.ubuntu.com/real-time/latest/how-to/create-rt-ubuntu-vm-using-kvm/

Use this reference when the task needs details beyond the normal ServoBox commands, especially host CPU isolation, manual libvirt tuning, or adapting ServoBox behavior to upstream Ubuntu Real-time KVM guidance.

## Key Principles

- Real-time VMs need predictable scheduling, low interrupt latency, and dedicated resources.
- KVM hardware virtualization is preferred for RT VM workloads; avoid QEMU full emulation for latency-sensitive systems.
- BIOS or firmware System Management Interrupts can add millisecond-level latency. Prefer hardware where SMIs can be disabled or controlled.
- Assign VM vCPUs to host CPUs that share the same NUMA node and cache hierarchy when possible.
- Do not isolate CPU 0. Leave at least one non-isolated CPU per socket for host housekeeping, interrupts, RCU callbacks, kernel threads, and emulator work.

## Host Preparation

Inspect CPU topology before choosing isolated CPUs:

```bash
nproc
lscpu
lstopo
cat /sys/devices/system/cpu/online
```

For a 16-CPU host where CPUs `0-7` stay reserved for the host and CPUs `8-15` are isolated for RT VM work, Ubuntu's example uses:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT clocksource=tsc tsc=reliable nmi_watchdog=0 nosoftlockup kthread_cpus=0-7 isolcpus=domain,managed_irq,8-15 rcu_nocb_poll rcu_nocbs=8-15 nohz=on nohz_full=8-15 irqaffinity=0-7 idle=poll"
```

Apply and verify after reboot:

```bash
sudo update-grub
sudo reboot
cat /proc/cmdline
cat /sys/devices/system/cpu/isolated
```

Install the host packages needed for manual KVM/libvirt workflows:

```bash
sudo apt update
sudo apt install util-linux wget whois qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils qemu-utils virtinst libosinfo-bin osinfo-db-tools genisoimage
sudo usermod --append --groups libvirt "$(whoami)"
newgrp libvirt
systemctl status libvirtd --no-pager
virsh net-start default || true
```

## Cloud Image VM Flow

The upstream example creates an Ubuntu 24.04 LTS cloud-image VM and installs Real-time Ubuntu during first boot with cloud-init.

```bash
sudo mkdir -p /var/lib/libvirt/images/ubuntu-rt-vm
cd /var/lib/libvirt/images/ubuntu-rt-vm
sudo wget -q --show-progress -O ubuntu-cloud.img https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
sudo qemu-img create -f qcow2 -F qcow2 -o backing_file=ubuntu-cloud.img ubuntu-rt-vm.qcow2 20G
```

Minimal `user-data` shape:

```yaml
#cloud-config
users:
  - name: ubuntu
    plain_text_passwd: 'ubuntu'
    lock_passwd: false
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
ssh_pwauth: true

packages:
  - stress-ng
  - rt-tests

write_files:
  - path: /etc/default/grub.d/99-rt-vm.cfg
    permissions: '0644'
    content: |
      GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} kthread_cpus=0 irqaffinity=0 isolcpus=domain,managed_irq,1-7 rcu_nocb_poll rcu_nocbs=1-7 nohz=on nohz_full=1-7"

runcmd:
  - add-apt-repository -y universe
  - apt update
  - apt install -y ubuntu-realtime
  - update-grub
  - reboot
```

Create `meta-data`:

```yaml
instance-id: ubuntu-rt-vm
local-hostname: ubuntu-rt-vm
```

Generate the seed ISO and define the VM:

```bash
sudo genisoimage -input-charset "utf-8" -volid cidata -joliet -rock -output seed.iso user-data meta-data
sudo virt-install --connect qemu:///system --virt-type kvm --name ubuntu-rt-vm --vcpus 8 --ram 8192 --os-variant ubuntu24.04 --disk path=ubuntu-rt-vm.qcow2,format=qcow2 --disk path=seed.iso,device=cdrom --import --network network=default --noautoconsole --nographics --print-xml | sudo tee /etc/libvirt/qemu/ubuntu-rt-vm.xml
sudo virsh define /etc/libvirt/qemu/ubuntu-rt-vm.xml
```

## Libvirt RT Tuning

Use `virsh edit ubuntu-rt-vm` or edit the generated XML and redefine it. Keep vCPU count, topology, and host pinning aligned.

CPU pinning and scheduler example for host isolated CPUs `8-15`:

```xml
<cputune>
    <vcpupin vcpu='0' cpuset='8'/>
    <vcpupin vcpu='1' cpuset='9'/>
    <vcpupin vcpu='2' cpuset='10'/>
    <vcpupin vcpu='3' cpuset='11'/>
    <vcpupin vcpu='4' cpuset='12'/>
    <vcpupin vcpu='5' cpuset='13'/>
    <vcpupin vcpu='6' cpuset='14'/>
    <vcpupin vcpu='7' cpuset='15'/>
    <emulatorpin cpuset='0-7'/>
    <vcpusched vcpus='0' scheduler='fifo' priority='1'/>
    <vcpusched vcpus='1-7' scheduler='fifo' priority='10'/>
</cputune>
```

CPU passthrough and topology:

```xml
<cpu mode='host-passthrough' check='none' migratable='off'>
    <topology sockets='1' dies='1' cores='8' threads='1'/>
    <feature policy='require' name='tsc-deadline'/>
</cpu>
```

Memory and virtualization overhead controls:

```xml
<memoryBacking>
    <nosharepages/>
    <locked/>
</memoryBacking>

<features>
    <pmu state='off'/>
</features>

<devices>
    <memballoon model='none'/>
</devices>
```

## Verification

Start and inspect the VM:

```bash
sudo virsh start ubuntu-rt-vm
virsh list
sudo virsh console ubuntu-rt-vm
```

The first boot may reboot after installing the RT kernel. After login, verify:

```bash
uname -a
cat /proc/cmdline
cat /sys/devices/system/cpu/isolated
```

For latency measurement, prefer ServoBox's normal validation commands when working inside this repo:

```bash
servobox rt-verify
servobox test --duration 30 --stress-ng
```
