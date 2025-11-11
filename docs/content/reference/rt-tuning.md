# Real-Time Tuning Reference

ServoBox implements a comprehensive real-time optimization stack across both host and guest systems. This page documents every tuning measure applied to achieve deterministic, low-latency performance.

---

## Overview

ServoBox achieves real-time performance through a **layered approach**:

1. **Host-level isolation** - Dedicate CPU cores and control interrupt routing
2. **VM configuration** - Optimize KVM/QEMU for deterministic execution
3. **Guest optimization** - PREEMPT_RT kernel with minimal jitter sources
4. **Verification tools** - Built-in testing and diagnostics

All optimizations are applied automatically during `servobox init` and `servobox start`.

---

## Performance Modes

ServoBox offers three RT performance modes (selected with `servobox start`):

| Mode | Latency Target | Power Usage | Command |
|------|---------------|-------------|---------|
| **Balanced** (default) | avg: ~4μs, max: ~100-120μs | Normal | `servobox start` |
| **Performance** | avg: ~3μs, max: ~100μs (fewer spikes) | +20-30W | `servobox start --performance` |
| **Extreme** | avg: ~3μs, max: ~100μs (rare spikes) | +40-60W (high) | `servobox start --extreme` |

**Mode details:**

- **Balanced**: Performance CPU governor with dynamic frequency scaling. **Recommended for most robotics control loops** - excellent latency with normal power consumption. Achieves the VM's fundamental latency floor.

- **Performance**: Locks CPU frequencies to maximum, eliminating frequency transition jitter. **Does not reduce max latency significantly** but makes 100μs+ spikes less frequent. Use when your application needs tighter timing guarantees (99.99% vs 99.9%).

- **Extreme**: Adds Turbo Boost disable for maximum determinism. In testing, shows no measurable improvement over Performance mode. Use only for experimentation or if you need absolutely predictable behavior.

!!! info "VM Latency Ceiling"
    The ~100-120μs max latency represents the fundamental limit of running RT workloads in a VM. These spikes come from:
    
    - **Hypervisor overhead** (QEMU/KVM context switches, memory management)
    - **Hardware interrupts** (SMIs, IRQs bleeding through isolation)
    - **Memory subsystem** (cache misses, TLB flushes)
    
    Frequency locking (Performance/Extreme modes) can reduce the *frequency* of spikes but cannot eliminate them. For latencies <50μs, bare-metal RT Linux is required.

!!! tip "Switching Modes"
    You can change modes by stopping and restarting the VM with a different flag. The mode only affects host CPU tuning, not the VM image.

---

## Host System Configuration

### CPU Isolation via Kernel Parameters

**What it does:**  
Removes CPU cores from the Linux scheduler and routes all interrupts to CPU 0, creating a "quiet zone" for RT workloads.

**Configuration (user-applied):**  
Edit `/etc/default/grub` and add to `GRUB_CMDLINE_LINUX_DEFAULT`:

```text
isolcpus=managed_irq,domain,1-4 nohz_full=1-4 rcu_nocbs=1-4 irqaffinity=0
```

Then apply with:

```console
sudo update-grub
sudo reboot
```

**Parameters explained:**

- `isolcpus=managed_irq,domain,1-4` - Remove CPUs 1-4 from kernel scheduler
- `nohz_full=1-4` - Disable periodic timer ticks on isolated CPUs
- `rcu_nocbs=1-4` - Move RCU callback processing off isolated CPUs
- `irqaffinity=0` - Route all interrupts to CPU 0 by default

**Why it matters:**  
Prevents kernel scheduler and interrupt activity from preempting RT vCPU threads, eliminating a major source of latency spikes.

!!! tip "Helper Command"
    ServoBox provides `servobox irqbalance-mask` to generate the correct `IRQBALANCE_BANNED_CPULIST` configuration for persistent IRQ isolation across reboots.

---

### Experimental Tuning

ServoBox's balanced mode already achieves the VM latency ceiling (~100-120μs max). For users interested in experimenting with advanced BIOS and host tuning to potentially reduce spike frequency, see:

**[:material-flask: Experimental Host Tuning →](experimental-tuning.md)**

!!! info "Community Research"
    These settings are untested with ServoBox and may not provide significant benefits in VMs. If you experiment with them and have interesting results, please share on [GitHub Discussions](https://github.com/kvasios/servobox/discussions)!

---

### Runtime IRQ Affinity Configuration

**What it does:**  
ServoBox sets IRQ affinity for all interrupt sources to CPU 0 during `servobox start`.

**Implementation:**

```bash
# For each IRQ in /proc/irq/*/smp_affinity_list
echo "0" | sudo tee /proc/irq/*/smp_affinity_list
```

**Why it matters:**  
Ensures hardware interrupts (network, disk, USB) don't disturb isolated RT cores even if new devices are hotplugged.

---

### CPU Frequency Governor

**What it does:**  
Forces CPU frequency governor to `performance` mode on CPU 0 and all RT cores.

**Why it matters:**  
Prevents dynamic frequency scaling (Intel SpeedStep, AMD Cool'n'Quiet) that can introduce latency spikes of 100+μs during frequency transitions.

---

## VM/Hypervisor Configuration

### vCPU to Physical CPU Pinning

**What it does:**  
Statically pins each VM vCPU thread to a specific host CPU core.

**Configuration (automatic):**  
libvirt XML `<cputune>` section with per-vCPU pinning:

```xml
<cputune>
  <vcpupin vcpu='0' cpuset='1'/>
  <vcpupin vcpu='1' cpuset='2'/>
  <vcpupin vcpu='2' cpuset='3'/>
  <vcpupin vcpu='3' cpuset='4'/>
  <emulatorpin cpuset='0'/>
  <iothreadpin iothread='1' cpuset='0'/>
</cputune>
```

**Why it matters:**  
Eliminates scheduler migration overhead and ensures predictable cache behavior. Guest vCPU N always runs on host CPU N+1.

---

### Real-Time Thread Priorities

**What it does:**  
Assigns `SCHED_FIFO` priorities to QEMU threads using `chrt`.

**Priority hierarchy:**

| Component | Priority | Rationale |
|-----------|----------|-----------|
| vCPU threads | 80 | Critical path for guest execution |
| vhost-net threads | 75 | Network I/O for robot communication |
| QEMU main process | 70 | Infrastructure/monitoring overhead |

**Why it matters:**  
Ensures QEMU threads preempt host tasks but leave headroom (priority 90-99) for guest RT applications.

---

### Memory Locking and KSM Disable

**What it does:**  
Locks VM memory in physical RAM and disables Kernel Same-page Merging (KSM).

**Configuration (automatic):**  
libvirt XML:

```xml
<memoryBacking>
  <locked/>
  <nosharepages/>
</memoryBacking>
```

**Why it matters:**  

- `locked`: Prevents swapping (eliminates ms-scale page fault latency)
- `nosharepages`: Disables KSM scanning (prevents unpredictable CPU overhead from background merging)

!!! info "Optional: Static Hugepages"
    For extreme performance (target <50μs max latency), you can configure host hugepages:
    
    ```bash
    # Reserve 2MB hugepages (e.g., 4096 pages = 8GB for an 8GB VM)
    echo 4096 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
    
    # Make persistent (add to /etc/sysctl.conf):
    vm.nr_hugepages=4096
    ```
    
    Then manually add to VM XML:
    ```xml
    <memoryBacking>
      <hugepages>
        <page size="2048" unit="KiB"/>
      </hugepages>
      <locked/>
      <nosharepages/>
    </memoryBacking>
    ```
    
    **Trade-off:** Hugepages reduce TLB misses but require dedicated host memory reservation.

---

### CPU Model and Cache Passthrough

**What it does:**  
Uses `host-passthrough` CPU model with cache passthrough.

**Configuration:**

```bash
virt-install --cpu host-passthrough,cache.mode=passthrough ...
```

**Why it matters:**  
Exposes host CPU features (SSE, AVX) to guest and minimizes emulation overhead. Cache passthrough reduces memory access latency.

---

### Clock Source Configuration

**What it does:**  
Enables `kvmclock` and native TSC timer in guest.

**Configuration (automatic):**  
libvirt XML:

```xml
<clock offset='utc'>
  <timer name='kvmclock' present='yes'/>
  <timer name='tsc' present='yes' mode='native'/>
</clock>
```

**Why it matters:**  
Provides stable, low-latency timekeeping for RT control loops. Native TSC avoids virtualization overhead.

---

### Virtio Network Multiqueue with Halt Polling

**What it does:**  
Enables one virtio-net queue per vCPU and configures KVM halt polling for lower idle wakeup latency.

**Configuration:**

```bash
--network model=virtio,driver.queues=4
# Plus runtime tuning:
echo 50000 > /sys/module/kvm/parameters/halt_poll_ns
```

**Why it matters:**  

- Multiqueue: Distributes network interrupt processing across vCPUs
- Halt polling (50μs): vCPU busy-waits before sleeping, reducing wakeup latency from ~10-20μs to <5μs for network packets

---

### Disk I/O Configuration

**What it does:**  
Uses `cache=none` and `discard=unmap` for VM disks.

**Why it matters:**  
Bypasses host page cache (eliminates cache flush latency) and improves SSD lifespan with TRIM support.

---

## Guest System Configuration

### PREEMPT_RT Kernel with Optimized Parameters

**What it does:**  
ServoBox ships Ubuntu 22.04 images with `linux-image-rt-amd64` (kernel 6.8.0-rt8) and RT-optimized boot parameters.

**Kernel parameters (automatic):**

```text
nohpet tsc=reliable
```

- `nohpet`: Disables HPET timer (reduces interrupt latency)
- `tsc=reliable`: Uses TSC as primary clocksource (lower overhead than HPET)

**Why it matters:**  
RT patches convert most kernel spinlocks to mutexes, enabling preemption throughout the kernel. Disabling HPET eliminates a source of 10-50μs latency spikes.

**Default approach:**  
No guest-level `isolcpus` parameters by default - allows multi-threaded applications to use all vCPUs freely.

!!! info "Advanced Configuration"
    For applications requiring strict single-core isolation, users can manually add `isolcpus=1-3 nohz_full=1-3 rcu_nocbs=1-3` to `/etc/default/grub` in the guest.

---

### Transparent Hugepages Disabled

**What it does:**  
Disables THP (Transparent Hugepages) in guest for deterministic behavior.

**Configuration (automatic):**

```bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
```

**Why it matters:**  
THP background scanning and compaction can cause unpredictable latency spikes. We use static hugepages (configured via libvirt XML) instead for deterministic 2MB page allocation.

---

### Guest Service Trimming

**What it does:**  
Disables non-essential services that create scheduling noise.

**Disabled services:**

- `snapd` - Package management daemon
- `ModemManager` - Mobile broadband management
- `bluetooth` - Bluetooth stack
- `cups` - Print service
- `avahi-daemon` - mDNS/Zeroconf

**Why it matters:**  
Each disabled service eliminates periodic wake-ups and background CPU activity that can interfere with RT control loops.

---

### Real-Time Process Limits

**What it does:**  
Configures PAM limits for the `@realtime` group in `/etc/security/limits.conf`:

```text
@realtime soft rtprio 99
@realtime hard rtprio 99
@realtime soft memlock 102400
@realtime hard memlock 102400
```

**Why it matters:**  
Allows user processes to request RT priorities and lock memory without `CAP_SYS_NICE` or `CAP_IPC_LOCK` capabilities.

---

### Fast Boot Path

**What it does:**

1. Cloud-init runs on first boot only, then disables itself
2. systemd-networkd-wait-online configured with `--any --timeout=10`
3. Custom `servobox-configure-macvtap` service for direct NIC setup

**Why it matters:**  
Reduces boot time from 90+ seconds to <30 seconds. Eliminates variability from cloud-init network probing on subsequent boots.

---

## Networking Configuration

### NAT Network with DHCP Reservation

**What it does:**  
Creates libvirt DHCP reservation for consistent VM IP (default: `192.168.122.100`).

**Why it matters:**  
Stable addressing for SSH access and client connections without manual IP configuration.

---

### Direct NIC Attachment (macvtap)

**What it does:**  
Optionally attaches up to 2 host NICs directly to the VM via macvtap bridge mode.

**Configuration:**

```bash
servobox init --host-nic eth0 --host-nic eth1
servobox network-setup  # Interactive wizard
```

**Why it matters:**  
Bypasses host networking stack for lowest-latency robot communication. Essential for dual-arm robot setups.

---

### Guest Firewall and Routing

**What it does:**

1. Disables `ufw` firewall
2. Flushes iptables rules
3. Disables reverse path filtering (`rp_filter=0`)

**Why it matters:**  
Franka and other robots use UDP broadcast/multicast. Strict firewalls and rp_filter can silently drop packets, breaking robot communication.

---

## Verification and Testing

### RT Configuration Verification

**Command:**

```console
servobox rt-verify
```

**Checks:**

- XML configuration (CPU pinning, memory locking, timers)
- Runtime vCPU pinning and affinity
- QEMU thread RT priorities
- CPU frequency governors
- IRQ isolation statistics
- Guest kernel parameters

---

### Latency Testing

**Command:**

```console
servobox test --duration 30 --stress-ng
```

**What it does:**  
Runs `cyclictest` at 1kHz (1000μs interval) while optionally stressing the host with `stress-ng`.

**Expected results by mode:**

| Mode | Average | Max (typical) | Spike Frequency | Rating |
|------|---------|--------------|-----------------|--------|
| Balanced | ~4μs | ~100-120μs | ~1 per 10k cycles | EXCELLENT |
| Performance | ~3μs | ~100μs | ~1 per 50k cycles | EXCELLENT |
| Extreme | ~3μs | ~100μs | ~1 per 100k cycles | EXCELLENT |

Results depend on host hardware and isolation configuration. **Balanced mode is recommended for all users** - it achieves the VM latency ceiling with normal power consumption. Performance/Extreme modes reduce spike *frequency* for applications needing 99.99% timing guarantees, but do not significantly reduce maximum latency.

---

## Summary: Complete Optimization Stack

| Layer | Optimizations Applied |
|-------|----------------------|
| **Host Kernel** | CPU isolation (isolcpus, nohz_full, rcu_nocbs), IRQ affinity |
| **Host Runtime (Balanced)** | IRQ pinning to CPU 0, performance governor (dynamic freq), halt polling (50μs) |
| **Host Runtime (Performance)** | + Locked CPU frequencies to max (no scaling transitions) |
| **Host Runtime (Extreme)** | + Turbo Boost disabled for determinism |
| **Hypervisor** | vCPU pinning, SCHED_FIFO priorities, KSM off (nosharepages) |
| **VM Memory** | Locked, KSM disabled (nosharepages), THP disabled in guest |
| **VM Hardware** | host-passthrough CPU, virtio multiqueue, cache=none disks |
| **Guest Kernel** | PREEMPT_RT, nohpet, tsc=reliable, no guest isolcpus (default) |
| **Guest Services** | Trimmed services, RT limits, fast boot path |
| **Guest Network** | Disabled rp_filter, permissive firewall |
| **Verification** | `rt-verify` and `test` commands |

---

## Related Documentation

- [Installation Guide](../getting-started/installation.md) - Host GRUB configuration
- [FAQ](faq.md#why-not-just-use-ubuntu-pro-rt-kernel) - RT kernel vs VM approach
- [Troubleshooting](troubleshooting.md) - Performance issues and diagnostics

---

## Additional Resources

For extreme RT requirements (<20μs worst-case at all times), consider:

1. **BIOS tuning**: Disable C-states, P-states, Turbo Boost
2. **SMI analysis**: Use `hwlat` tracer to detect firmware interrupts
3. **Bare metal**: Consider Ubuntu Pro RT kernel on dedicated hardware

ServoBox's VM approach achieves excellent RT performance (suitable for 1kHz+ robotics control) while preserving host flexibility for development, perception, and high-level processing.
