# Real-Time (RT) Configuration Settings

This document lists all RT-specific settings applied by ServoBox during `servobox init` and `servobox start` to isolate the VM and achieve real-time performance.

## Settings Applied During `servobox init`

### Guest Kernel Parameters (via GRUB)
Applied to the guest VM's kernel command line:

1. **`isolcpus`** - Isolates specified CPUs from the Linux scheduler
   - Prevents kernel threads and other processes from running on isolated CPUs
   - Leaves CPU 0 for housekeeping tasks, isolates CPUs 1 to (vCPUs-1)
   - Example: `isolcpus=1,2,3` for 4 vCPU VM

2. **`nohz_full`** - Disables timer ticks on isolated CPUs
   - Eliminates periodic interrupts that cause scheduling delays
   - Reduces jitter and improves worst-case latency
   - Applied to same CPUs as `isolcpus`

3. **`rcu_nocbs`** - Moves RCU callbacks off isolated CPUs
   - Prevents Read-Copy-Update (RCU) callbacks from running on isolated CPUs
   - RCU is a synchronization mechanism that can cause latency spikes
   - Applied to same CPUs as `isolcpus`

### Guest User/Group Configuration
Applied inside the guest VM:

4. **`realtime` group** - Created and configured for RT privilege access
   - Users in this group can set real-time priorities without root
   - `servobox-usr` is automatically added to this group

5. **`/etc/security/limits.conf`** - Sets RT priority and memory limits
   - `@realtime soft/hard rtprio 99` - Maximum real-time priority (1-99)
   - `@realtime soft/hard priority 99` - Process priority
   - `@realtime soft/hard memlock 102400` - Memory locking limit (KB) for preventing swapping

6. **`pam_limits.so`** - Enables limits enforcement in PAM
   - Loaded in `/etc/pam.d/common-session` and `common-session-noninteractive`
   - Ensures limits.conf settings are actually applied to user sessions

### Libvirt XML Configuration
Applied to the VM domain definition:

7. **CPU Pinning (`<cputune>`)** - Pins vCPUs to specific host cores
   - vCPU 0 → host CPU 1, vCPU 1 → host CPU 2, etc.
   - Ensures deterministic CPU assignment and prevents migration

8. **Emulator Thread Pinning** - Pins QEMU emulator thread to host CPU 0
   - Keeps QEMU infrastructure off isolated RT cores
   - Emulator handles device emulation, not guest CPU execution

9. **IOThread Pinning** - Pins IOThread to host CPU 0
   - Dedicated thread for disk I/O operations
   - Keeps I/O operations off RT cores

10. **Memory Locking (`<memoryBacking><locked/>`)** - Locks VM memory in RAM
    - Prevents memory from being swapped to disk
    - Eliminates swap-related latency spikes
    - Critical for deterministic RT performance

11. **IOThreads (`<iothreads>1</iothreads>`)** - Enables dedicated I/O thread
    - Separates I/O operations from vCPU threads
    - Reduces I/O interference with RT workloads

12. **Clock Configuration (`<timer>` elements)** - Configures timekeeping
    - `kvmclock` - KVM paravirtualized clock source
    - `tsc` (Time Stamp Counter) with `mode="native"` - High-resolution timer
    - Reduces timekeeping overhead and improves accuracy

### CPU Configuration
Applied during VM creation:

13. **`--cpu host-passthrough,cache.mode=passthrough`** - CPU passthrough mode
    - Passes host CPU features directly to guest
    - Enables advanced CPU features for better performance
    - `cache.mode=passthrough` ensures cache coherency

14. **Disk Cache (`cache=none`)** - Disables host disk cache
    - Eliminates cache-related latency unpredictability
    - Direct I/O for deterministic behavior

## Settings Applied During `servobox start`

### Runtime CPU Pinning
Applied after VM starts:

15. **vCPU Pinning (via `virsh vcpupin`)** - Runtime CPU affinity
    - Reinforces XML pinning at runtime
    - Ensures vCPUs run only on designated host cores
    - Host cores 1 to vCPUS are reserved for VM

16. **QEMU Process Priority** - Sets QEMU main process to SCHED_FIFO priority 70
    - Real-time scheduling policy (FIFO = First In, First Out)
    - Priority 70 (medium RT priority, leaves room for higher-priority tasks)
    - Prevents QEMU from being preempted by normal processes

17. **vCPU Thread Priority** - Sets vCPU threads to SCHED_FIFO priority 80
    - Higher priority than QEMU main process (80 vs 70)
    - Critical threads that execute guest CPU instructions
    - Leaves room for guest RT applications (typically 90-99)

### Host CPU Configuration
Applied on the host system:

18. **CPU Frequency Governor** - Sets to `performance` mode
    - Disables CPU frequency scaling (no throttling)
    - Prevents dynamic clock changes that cause latency spikes
    - Applied to CPU 0 (IRQ handling) and RT cores (1 to vCPUS)

### IRQ Affinity
Applied on the host system:

19. **IRQ Affinity to CPU 0** - Routes all interrupts to host CPU 0
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
- **Real-time scheduling** - RT priorities for QEMU and vCPU threads
- **Deterministic performance** - Predictable, low-latency execution

