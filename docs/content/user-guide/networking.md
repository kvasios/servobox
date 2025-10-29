# Network Configuration

ServoBox networking options for robot communication and VM management.

## Overview

ServoBox provides simplified networking setup for robot applications. For advanced networking configurations, ServoBox VMs can be managed like any standard KVM/QEMU VM using standard virtualization tools.

## Default NAT Networking

Simple, works out of the box for basic VM access.

### How It Works

```
┌─────────────────────────────────────┐
│  Host System                        │
│  ┌────────────────────────────────┐ │
│  │  VM: 192.168.122.100           │ │
│  └─────────────┬──────────────────┘ │
│                │                    │
│         ┌──────┴──────┐             │
│         │  virbr0     │             │
│         │  (NAT)      │             │
│         └──────┬──────┘             │
│                │                    │
│         ┌──────┴──────┐             │
│         │  Host NIC   │             │
│         └──────┬──────┘             │
└────────────────┼────────────────────┘
                 │
            Internet
```

### Usage

```console
# Default NAT setup
servobox init

# With custom IP
servobox init --ip 192.168.122.50/24

# SSH access
servobox ssh
```

## Direct NIC Setup for Robots

Add direct host NICs for low-latency robot communication.

### Single Robot Setup

```
┌────────────────────────────────────────┐
│  Host System                           │
│  ┌──────────────────────────────────┐  │
│  │  VM                              │  │
│  │    enp1s0: 192.168.122.100 (NAT) │  │
│  │    enp2s0: 172.16.0.10 (direct)  │  │
│  └──────┬────────────┬──────────────┘  │
│         │            │                 │
│    ┌────┴─────┐    ┌─┴──┐              │
│    │  virbr0  │    │eth0│              │
│    │  (NAT)   │    │    │              │
│    └──────────┘    └─┬──┘              │
│                      │                 │
│                  ┌───┴──┐              │
│                  │Robot │              │
│                  └──────┘              │
└────────────────────────────────────────┘
```

**Setup:**
```console
servobox init --host-nic eth0
servobox start
servobox ssh
```

### Dual Robot Setup

```
┌────────────────────────────────────────┐
│  Host System                           │
│  ┌──────────────────────────────────┐  │
│  │  VM                              │  │
│  │    enp1s0: 192.168.122.100 (NAT) │  │
│  │    enp2s0: 172.16.0.10 (direct)  │  │
│  │    enp3s0: 172.17.0.10 (direct)  │  │
│  └──────┬────────────┬──────┬───────┘  │
│         │            │      │          │
│    ┌────┴─────┐    ┌─┴──┐ ┌─┴──┐       │
│    │  virbr0  │    │eth0│ │eth1│       │
│    │  (NAT)   │    │    │ │    │       │
│    └──────────┘    └─┬──┘ └─┬──┘       │
│                      │      │          │
│                  ┌───┴──┐ ┌─┴────┐     │
│                  │Robot1│ │Robot2│     │
│                  └──────┘ └──────┘     │
└────────────────────────────────────────┘
```

**Setup:**
```console
servobox init --host-nic eth0 --host-nic eth1
servobox start
servobox ssh
```

## Interactive Network Setup

Use the network setup wizard for guided configuration:

```console
servobox init --choose-nic
```

Or configure networks after VM creation:

```console
servobox network-setup
```

The wizard will show available NICs and guide you through selection:

```
=== ServoBox Network Setup ===
Select host NICs to attach to the VM (max 2 for dual robot setups).

  [1] eth0  driver=e1000e ip=172.16.0.10/24
  [2] eth1  driver=e1000e ip=172.17.0.10/24
  [3] wlan0  driver=iwlwifi ip=192.168.1.100/24

Select first NIC (or press ENTER to skip): 1
✓ Selected: eth0
```

## Automatic Configuration

ServoBox automatically:
- ✅ Mirrors host IP to VM (same IP on both sides)
- ✅ Maps NICs to predictable names:
  - First direct NIC → `enp2s0` in VM
  - Second direct NIC → `enp3s0` in VM
- ✅ Injects persistent netplan configuration

## SSH Key Management

Copy SSH keys from host to VM for seamless access:

```console
# Copy host SSH keys to VM
servobox ssh-copy-keys

# Or manually
ssh-copy-id servobox-usr@$(servobox ip)
```

## Advanced Networking

For complex networking requirements (bridges, VLANs, custom topologies), ServoBox VMs can be managed using standard KVM/QEMU tools and libvirt, just like any other virtual machine.

## See Also

- [Commands Reference](commands.md) - Network-related options and VM management
 

