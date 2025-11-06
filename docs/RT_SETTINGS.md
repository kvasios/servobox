# Real-Time (RT) Configuration Settings

This document lists all RT-specific settings applied by ServoBox during `servobox init` and `servobox start` to isolate the VM and achieve real-time performance.

## Settings Applied During `servobox init`

### Guest Kernel Configuration
Applied to the guest VM:

1. **PREEMPT_RT Kernel** - Real-time kernel with deterministic scheduling
   - Provides low-latency, deterministic task scheduling
   - All kernel code paths are preemptible (no unbounded latencies)
   - Combined with host-level isolation, this provides excellent RT performance
   - **Note**: Guest-level CPU isolation (`isolcpus`, `nohz_full`, `rcu_nocbs`) is **intentionally disabled**
     - Host-level isolation already provides dedicated CPU cores for the VM
     - Guest processes can freely use all vCPUs without manual pinning
     - Prevents bottlenecking all user processes on vCPU 0
     - Critical for Python applications (ur_rtde, franky) that benefit from multi-core usage
     - Advanced users can manually add `isolcpus=` to `/etc/default/grub` if needed

### Guest User/Group Configuration
Applied inside the guest VM:

2. **`realtime` group** - Created and configured for RT privilege access
   - Users in this group can set real-time priorities without root
   - `servobox-usr` is automatically added to this group

3. **`/etc/security/limits.conf`** - Sets RT priority and memory limits
   - `@realtime soft/hard rtprio 99` - Maximum real-time priority (1-99)
   - `@realtime soft/hard priority 99` - Process priority
   - `@realtime soft/hard memlock 102400` - Memory locking limit (KB) for preventing swapping

4. **`pam_limits.so`** - Enables limits enforcement in PAM
   - Loaded in `/etc/pam.d/common-session` and `common-session-noninteractive`
   - Ensures limits.conf settings are actually applied to user sessions

### Libvirt XML Configuration
Applied to the VM domain definition:

5. **CPU Pinning (`<cputune>`)** - Pins vCPUs to specific host cores
   - vCPU 0 → host CPU 1, vCPU 1 → host CPU 2, etc.
   - Ensures deterministic CPU assignment and prevents migration

6. **Emulator Thread Pinning** - Pins QEMU emulator thread to host CPU 0
   - Keeps QEMU infrastructure off isolated RT cores
   - Emulator handles device emulation, not guest CPU execution

7. **IOThread Pinning** - Pins IOThread to host CPU 0
   - Dedicated thread for disk I/O operations
   - Keeps I/O operations off RT cores

8. **Memory Locking (`<memoryBacking><locked/>`)** - Locks VM memory in RAM
    - Prevents memory from being swapped to disk
    - Eliminates swap-related latency spikes
    - Critical for deterministic RT performance

9. **IOThreads (`<iothreads>1</iothreads>`)** - Enables dedicated I/O thread
    - Separates I/O operations from vCPU threads
    - Reduces I/O interference with RT workloads

10. **Clock Configuration (`<timer>` elements)** - Configures timekeeping
    - `kvmclock` - KVM paravirtualized clock source
    - `tsc` (Time Stamp Counter) with `mode="native"` - High-resolution timer
    - Reduces timekeeping overhead and improves accuracy

### CPU Configuration
Applied during VM creation:

11. **`--cpu host-passthrough,cache.mode=passthrough`** - CPU passthrough mode
    - Passes host CPU features directly to guest
    - Enables advanced CPU features for better performance
    - `cache.mode=passthrough` ensures cache coherency

12. **Disk Cache (`cache=none`)** - Disables host disk cache
    - Eliminates cache-related latency unpredictability
    - Direct I/O for deterministic behavior

### Network Configuration
Applied during VM creation:

13. **virtio-net Network Model** - Paravirtualized network driver
    - Used for all network interfaces (NAT, bridge, macvtap)
    - Replaces emulated e1000e driver (5-10x lower latency)
    - Reduces network overhead from ~20-50μs to ~2-5μs per packet
    - Critical for high-frequency robot control (UR RTDE @ 500Hz, libfranka @ 1kHz)

14. **Multi-Queue virtio-net** - Parallel packet processing
    - Number of queues matches vCPU count (e.g., 4 vCPUs → 4 queues)
    - Distributes network load across multiple CPU cores
    - Improves throughput and reduces latency under load

15. **vhost-net Acceleration** - Kernel-space packet processing
    - Network packets processed in kernel space (not userspace QEMU)
    - Spawns dedicated vhost worker threads (typically 4-8 threads per NIC)
    - Significantly reduces CPU overhead and latency
    - All vhost threads pinned to host CPU 0 (off RT cores)

## Settings Applied During `servobox start`

### Runtime CPU Pinning
Applied after VM starts:

16. **vCPU Pinning (via `virsh vcpupin`)** - Runtime CPU affinity
    - Reinforces XML pinning at runtime
    - Ensures vCPUs run only on designated host cores
    - Host cores 1 to vCPUS are reserved for VM

17. **QEMU Process Priority** - Sets QEMU main process to SCHED_FIFO priority 70
    - Real-time scheduling policy (FIFO = First In, First Out)
    - Priority 70 (medium RT priority, leaves room for higher-priority tasks)
    - Prevents QEMU from being preempted by normal processes

18. **vCPU Thread Priority** - Sets vCPU threads to SCHED_FIFO priority 80
    - Higher priority than QEMU main process (80 vs 70)
    - Critical threads that execute guest CPU instructions
    - Leaves room for guest RT applications (typically 90-99)

19. **vhost-net Thread Priority** - Sets vhost-net threads to SCHED_FIFO priority 75
    - Network packet processing threads (kernel-space)
    - Priority 75 (between QEMU main and vCPU threads)
    - Handles all network I/O between host and guest
    - Critical for robot control applications (UR RTDE, libfranka FCI)
    - Prevents network packet processing delays that cause connection drops

### Host CPU Configuration
Applied on the host system:

20. **CPU Frequency Governor** - Sets to `performance` mode
    - Disables CPU frequency scaling (no throttling)
    - Prevents dynamic clock changes that cause latency spikes
    - Applied to CPU 0 (IRQ handling) and RT cores (1 to vCPUS)

### IRQ Affinity
Applied on the host system:

21. **IRQ Affinity to CPU 0** - Routes all interrupts to host CPU 0
    - Keeps interrupts off isolated RT cores (1 to vCPUS)
    - Prevents interrupt handlers from causing latency spikes on RT cores
    - Uses `/proc/irq/*/smp_affinity_list` and `smp_affinity` (hex mask)

## Summary

**During `init`**: Guest kernel parameters, user/group configuration, and libvirt XML settings are applied to prepare the VM for RT operation.

**During `start`**: Runtime CPU pinning, thread priorities, CPU frequency governors, and IRQ affinity are configured to ensure optimal RT performance while the VM is running.

Together, these settings provide:
- **CPU isolation** - RT workloads run on dedicated cores
- **Interrupt isolation** - IRQs routed away from RT cores
- **Memory locking** - No swap-related latency
- **Real-time scheduling** - RT priorities for QEMU, vCPU, and vhost threads
- **Network optimization** - Low-latency virtio-net with vhost acceleration
- **Deterministic performance** - Predictable, low-latency execution for robot control

