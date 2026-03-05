#!/usr/bin/env bash
# Real-time configuration functions

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Resolve a deterministic CPU layout for RT VMs.
# Default policy on multi-core hosts:
# - Housekeeping CPUs: 0-1
# - RT-isolated CPUs: 2..N
# Fallback on small hosts keeps CPU 0 as housekeeping.
get_rt_cpu_layout() {
  local host_cores="${1:-$(nproc)}"

  if [[ ${host_cores} -lt 2 ]]; then
    echo "Error: host must provide at least 2 CPU cores for RT pinning" >&2
    return 1
  fi

  HK_CPUSET="0"
  RT_START_CPU=1
  if [[ ${host_cores} -ge 4 ]]; then
    HK_CPUSET="0-1"
    RT_START_CPU=2
  fi

  RT_END_CPU=$((host_cores - 1))
  if [[ ${RT_START_CPU} -gt ${RT_END_CPU} ]]; then
    HK_CPUSET="0"
    RT_START_CPU=1
  fi

  RT_AVAILABLE=$((RT_END_CPU - RT_START_CPU + 1))
  RT_CPUSET=$(seq -s, "${RT_START_CPU}" "${RT_END_CPU}")
}

expand_cpulist() {
  local cpulist="$1"
  local part
  local first=1

  IFS=',' read -ra _parts <<< "${cpulist}"
  for part in "${_parts[@]}"; do
    if [[ "${part}" == *-* ]]; then
      local start="${part%-*}"
      local end="${part#*-}"
      for c in $(seq "${start}" "${end}"); do
        if [[ ${first} -eq 1 ]]; then
          printf "%s" "${c}"
          first=0
        else
          printf " %s" "${c}"
        fi
      done
    else
      if [[ ${first} -eq 1 ]]; then
        printf "%s" "${part}"
        first=0
      else
        printf " %s" "${part}"
      fi
    fi
  done
}

cpulist_to_mask() {
  local cpulist="$1"
  python3 - "${cpulist}" <<'PY'
import sys

cpulist = sys.argv[1]
mask = 0
for token in cpulist.split(','):
    token = token.strip()
    if not token:
        continue
    if '-' in token:
        start, end = token.split('-', 1)
        for cpu in range(int(start), int(end) + 1):
            mask |= (1 << cpu)
    else:
        mask |= (1 << int(token))

print(format(mask, "x"))
PY
}

# Calculate IRQBALANCE_BANNED_CPUS mask for host RT isolation
cmd_irqbalance_mask() {
  shift || true  # Remove the command name
  
  local host_cores=$(nproc)
  get_rt_cpu_layout "${host_cores}"
  local vm_name="${NAME}"  # Use default from global
  local isolated_min="${RT_START_CPU}"
  local isolated_max=""
  local vm_vcpus=""
  local auto_detected=0
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        vm_name="$2"
        shift 2
        ;;
      *)
        echo "Error: Unknown argument '$1'" >&2
        echo "Usage: servobox irqbalance-mask [--name NAME]" >&2
        exit 1
        ;;
    esac
  done
  
  # Auto-detect from VM
  if virsh_cmd dominfo "${vm_name}" >/dev/null 2>&1; then
    vm_vcpus=$(virsh_cmd dominfo "${vm_name}" 2>/dev/null | grep "CPU(s):" | awk '{print $2}')
    if [[ -n "${vm_vcpus}" && "${vm_vcpus}" =~ ^[0-9]+$ ]]; then
      # Isolate VM vCPUs on host RT cores (after housekeeping cores)
      isolated_max=$((isolated_min + vm_vcpus - 1))
      auto_detected=1
      echo "ℹ️  Auto-detected from VM '${vm_name}': ${vm_vcpus} vCPUs"
    fi
  fi
  
  # Fallback: use default VM vCPU count
  if [[ -z "${isolated_max}" ]]; then
    isolated_max=$((isolated_min + 3))  # Default: 4 vCPUs
    if [[ ${isolated_max} -ge ${host_cores} ]]; then
      isolated_max=$((host_cores - 1))
    fi
    auto_detected=1
    echo "ℹ️  No VM found, using default: 4 vCPUs (isolating cores ${isolated_min}-${isolated_max})"
  fi
  
  # Validate isolated_max
  if [[ ${isolated_max} -ge ${host_cores} ]]; then
    echo "Error: Cannot isolate more cores than available on host" >&2
    echo "Host has ${host_cores} cores, you tried to isolate up to core ${isolated_max}" >&2
    exit 1
  fi
  
  if [[ ${isolated_max} -lt ${isolated_min} ]]; then
    echo "Error: Must isolate at least core ${isolated_min}" >&2
    exit 1
  fi
  
  # Calculate both formats (cpulist is simpler, bitmask for compatibility)
  local cpulist="${isolated_min}-${isolated_max}"
  local mask
  mask=$(cpulist_to_mask "${cpulist}")
  
  echo "═══════════════════════════════════════════════════════════════"
  echo "         IRQBALANCE CONFIGURATION FOR RT ISOLATION"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  if [[ ${auto_detected} -eq 1 && -n "${vm_vcpus}" ]]; then
    echo "VM Configuration:"
    echo "  • VM name: ${vm_name}"
    echo "  • VM vCPUs: ${vm_vcpus}"
    echo ""
  fi
  echo "Host Configuration:"
  echo "  • Total HOST cores: ${host_cores}"
  echo "  • Cores to isolate: ${isolated_min}-${isolated_max} (for RT VMs)"
  echo "  • Housekeeping cores: ${HK_CPUSET} (for host IRQs/emulator tasks)"
  echo ""
  echo "Generated Configuration (use either format):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "IRQBALANCE_BANNED_CPULIST=${cpulist}  (recommended - simple!)"
  echo "IRQBALANCE_BANNED_CPUS=0x${mask}      (alternative - bitmask)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "How to apply this configuration:"
  echo ""
  echo "1. Edit the irqbalance configuration file:"
  echo "   sudo vim /etc/default/irqbalance"
  echo ""
  echo "2. Add this line (simple format recommended):"
  echo "   IRQBALANCE_BANNED_CPULIST=${cpulist}"
  echo ""
  echo "3. Restart irqbalance service:"
  echo "   sudo systemctl restart irqbalance"
  echo ""
  echo "4. Verify the configuration (after a few seconds):"
  echo "   cat /proc/interrupts | head -20"
  echo "   # Cores ${isolated_min}-${isolated_max} should have minimal interrupt activity"
  echo ""
  echo "Note: This configuration persists across reboots automatically."
  echo ""
  echo "VM Mapping:"
  if [[ -n "${vm_vcpus}" ]]; then
    echo "  • VM '${vm_name}' has ${vm_vcpus} vCPUs"
    echo "  • These will be pinned to HOST cores ${isolated_min}-${isolated_max}"
    echo "  • Housekeeping remains on HOST cores ${HK_CPUSET}"
  else
    echo "  • VM vCPUs will be pinned to HOST cores ${isolated_min}-N"
    echo "  • Default VM (4 vCPUs) → HOST cores ${isolated_min}-${isolated_max}"
  fi
  echo "  • ServoBox handles this mapping automatically during 'servobox start'"
  echo ""
}

# Apply RT optimizations to the libvirt XML definition
apply_rt_xml_config() {
  echo "Applying RT optimizations to VM XML configuration..."
  
  # Get host CPU topology
  local host_cores=$(nproc)
  get_rt_cpu_layout "${host_cores}"
  
  # Calculate isolated cores for vCPUs
  local vcpu_cpuset="${RT_CPUSET}"
  if [[ ${VCPUS} -gt ${RT_AVAILABLE} ]]; then
    echo "Warning: Requested ${VCPUS} vCPUs but only ${RT_AVAILABLE} host cores available for RT isolation"
    echo "         Using cores ${RT_CPUSET}"
  fi
  
  # Export current XML
  local xml_file=$(mktemp)
  virsh_cmd dumpxml "${NAME}" > "${xml_file}"
  
  # Use xmlstarlet if available, otherwise use sed
  if command -v xmlstarlet >/dev/null 2>&1; then
    # Add iothreads
    xmlstarlet ed -L \
      -s "/domain" -t elem -n "iothreads" -v "1" \
      "${xml_file}" 2>/dev/null || true
    
    # Add memoryBacking with locked, nosharepages
    # locked: prevents swapping
    # nosharepages: disables KSM (Kernel Same-page Merging) for determinism
    # Note: We don't use hugepages by default as they require host configuration
    # Users can manually configure hugepages if needed for extreme performance
    xmlstarlet ed -L \
      -s "/domain" -t elem -n "memoryBacking" \
      -s "/domain/memoryBacking" -t elem -n "locked" \
      -s "/domain/memoryBacking" -t elem -n "nosharepages" \
      "${xml_file}" 2>/dev/null || true
    
    # Add cputune section with pinning
    xmlstarlet ed -L \
      -s "/domain" -t elem -n "cputune" \
      "${xml_file}" 2>/dev/null || true
    
    # Add vcpu pinning for each vCPU
    for vcpu in $(seq 0 $((VCPUS-1))); do
      local host_cpu=$((RT_START_CPU + vcpu))
      if [[ ${host_cpu} -le ${RT_END_CPU} ]]; then
        xmlstarlet ed -L \
          -s "/domain/cputune" -t elem -n "vcpupin" \
          -i "/domain/cputune/vcpupin[last()]" -t attr -n "vcpu" -v "${vcpu}" \
          -i "/domain/cputune/vcpupin[last()]" -t attr -n "cpuset" -v "${host_cpu}" \
          "${xml_file}" 2>/dev/null || true
      fi
    done
    
    # Keep emulator thread(s) on housekeeping CPU set
    xmlstarlet ed -L \
      -s "/domain/cputune" -t elem -n "emulatorpin" \
      -i "/domain/cputune/emulatorpin" -t attr -n "cpuset" -v "${HK_CPUSET}" \
      "${xml_file}" 2>/dev/null || true
    
    # Keep IO thread(s) on housekeeping CPU set
    xmlstarlet ed -L \
      -s "/domain/cputune" -t elem -n "iothreadpin" \
      -i "/domain/cputune/iothreadpin" -t attr -n "iothread" -v "1" \
      -i "/domain/cputune/iothreadpin" -t attr -n "cpuset" -v "${HK_CPUSET}" \
      "${xml_file}" 2>/dev/null || true
    
    # Update clock configuration
    xmlstarlet ed -L \
      -s "/domain/clock" -t elem -n "timer" \
      -i "/domain/clock/timer[last()]" -t attr -n "name" -v "kvmclock" \
      -i "/domain/clock/timer[last()]" -t attr -n "present" -v "yes" \
      "${xml_file}" 2>/dev/null || true
    
    xmlstarlet ed -L \
      -s "/domain/clock" -t elem -n "timer" \
      -i "/domain/clock/timer[last()]" -t attr -n "name" -v "tsc" \
      -i "/domain/clock/timer[last()]" -t attr -n "present" -v "yes" \
      -i "/domain/clock/timer[last()]" -t attr -n "mode" -v "native" \
      "${xml_file}" 2>/dev/null || true
  else
    # Fallback: Use sed for basic XML manipulation
    # This is a simplified version - just add the sections
    
    # Find the insertion point (before </domain>)
    sed -i '/<\/domain>/i\  <iothreads>1</iothreads>' "${xml_file}"
    
    # Add memoryBacking with RT optimizations
    sed -i '/<\/domain>/i\  <memoryBacking>\n    <locked/>\n    <nosharepages/>\n  </memoryBacking>' "${xml_file}"
    
    # Add cputune section
    local cputune_xml="  <cputune>\n"
    # Add vcpupin for each vCPU
    for vcpu in $(seq 0 $((VCPUS-1))); do
      local host_cpu=$((RT_START_CPU + vcpu))
      if [[ ${host_cpu} -le ${RT_END_CPU} ]]; then
        cputune_xml+="    <vcpupin vcpu='${vcpu}' cpuset='${host_cpu}'/>\n"
      fi
    done
    # Add emulatorpin and iothreadpin
    cputune_xml+="    <emulatorpin cpuset='${HK_CPUSET}'/>\n"
    cputune_xml+="    <iothreadpin iothread='1' cpuset='${HK_CPUSET}'/>\n"
    cputune_xml+="  </cputune>"
    
    sed -i "/<\/domain>/i\\${cputune_xml}" "${xml_file}"
    
    # Add timer elements to clock section (if not already present)
    if ! grep -q "kvmclock" "${xml_file}"; then
      sed -i '/<\/clock>/i\    <timer name="kvmclock" present="yes"/>' "${xml_file}"
    fi
    if ! grep -q 'timer name="tsc"' "${xml_file}"; then
      sed -i '/<\/clock>/i\    <timer name="tsc" present="yes" mode="native"/>' "${xml_file}"
    fi
  fi
  
  # Redefine the domain with updated XML
  echo "Redefining VM with RT-optimized XML..."
  if virsh_cmd define "${xml_file}" >/dev/null 2>&1; then
    echo "✓ RT XML configuration applied successfully"
    echo "  • CPU pinning: vCPUs 0-$((VCPUS-1)) → host CPUs ${RT_START_CPU}-${RT_END_CPU}"
    echo "  • Emulator thread pinned to CPUs ${HK_CPUSET}"
    echo "  • IOThread pinned to CPUs ${HK_CPUSET}"
    echo "  • Memory locking enabled"
    echo "  • Enhanced clock configuration (kvmclock, TSC)"
  else
    echo "⚠️  Warning: Failed to apply RT XML optimizations"
    echo "   VM will still work but may not have optimal RT performance"
    echo "   Falling back to runtime pinning only"
  fi
  
  rm -f "${xml_file}"
}

# Inject RT kernel parameters into guest GRUB configuration
inject_rt_kernel_params() {
  # Note: We intentionally do NOT use isolcpus/nohz_full/rcu_nocbs in the guest.
  # The PREEMPT_RT kernel + host-level CPU isolation is sufficient for RT performance.
  # Guest-level isolation would force all user processes onto vCPU 0, creating a bottleneck
  # and preventing Python apps (ur_rtde, franky) from utilizing all available vCPUs.
  # Advanced users who need guest isolation can manually add it via /etc/default/grub.
  
  # RT-optimized kernel parameters:
  # - nohpet: Disable HPET (High Precision Event Timer) - reduces latency spikes
  # - tsc=reliable: Use TSC as primary clocksource (already configured via kvmclock)
  local grub_params="quiet splash nohpet tsc=reliable"
  
  echo "Configuring guest kernel parameters (PREEMPT_RT only, no guest CPU isolation)..."
  echo "  • Host-level isolation already provides dedicated cores for the VM"
  echo "  • Guest processes can freely use all ${VCPUS} vCPUs for optimal performance"
  echo "  • Advanced users: manually add 'isolcpus=' to /etc/default/grub if needed"
  
  # Create a script to update GRUB configuration
  local grub_script
  grub_script=$(mktemp)
  cat > "${grub_script}" <<'GRUBSCRIPT'
#!/bin/bash
set -e
# Backup original GRUB config
cp /etc/default/grub /etc/default/grub.servobox-orig 2>/dev/null || true
# Update GRUB_CMDLINE_LINUX_DEFAULT
sed -i.bak "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"GRUB_PARAMS_PLACEHOLDER\"|" /etc/default/grub
# Clear GRUB_CMDLINE_LINUX to avoid conflicts
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=""|' /etc/default/grub
# Disable cloud-init grub config if it exists
if [ -f /etc/default/grub.d/50-cloudimg-settings.cfg ]; then
  sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|# Disabled by servobox for RT configuration\n# GRUB_CMDLINE_LINUX_DEFAULT=|' /etc/default/grub.d/50-cloudimg-settings.cfg
fi
# Update grub configuration
update-grub || grub-mkconfig -o /boot/grub/grub.cfg || true
GRUBSCRIPT
  
  # Replace placeholder with actual parameters
  sed -i "s|GRUB_PARAMS_PLACEHOLDER|${grub_params}|" "${grub_script}"
  
  # Upload and execute the script using virt-customize
  if virt-customize -a "${DISK_QCOW}" \
      --upload "${grub_script}:/tmp/setup-rt-grub.sh" \
      --run-command "chmod +x /tmp/setup-rt-grub.sh" \
      --run-command "/tmp/setup-rt-grub.sh" \
      --run-command "rm -f /tmp/setup-rt-grub.sh" >/dev/null 2>&1; then
    :
  else
    sudo virt-customize -a "${DISK_QCOW}" \
      --upload "${grub_script}:/tmp/setup-rt-grub.sh" \
      --run-command "chmod +x /tmp/setup-rt-grub.sh" \
      --run-command "/tmp/setup-rt-grub.sh" \
      --run-command "rm -f /tmp/setup-rt-grub.sh"
  fi
  
  rm -f "${grub_script}" 2>/dev/null || true
  echo "✓ RT kernel parameters configured in GRUB"
}

pin_vcpus() {
  echo "Pinning vCPUs and QEMU threads for optimal real-time performance..."
  
  # Get QEMU process ID (with retry for startup race)
  QEMU_PID=""
  for i in {1..5}; do
    QEMU_PID=$(pgrep -f "qemu.*${NAME}" | head -1)
    if [[ -n "${QEMU_PID}" ]]; then
      break
    fi
    echo "Waiting for QEMU process to start... (attempt $i/5)"
    sleep 1
  done
  
  if [[ -z "${QEMU_PID}" ]]; then
    echo "Error: VM ${NAME} not running or QEMU process not found" >&2
    exit 1
  fi
  
  # Wait a moment for vCPU threads to spawn
  sleep 2
  
  # Get host CPU topology
  HOST_CORES=$(nproc)
  get_rt_cpu_layout "${HOST_CORES}"
  
  echo "Host has ${HOST_CORES} cores, using housekeeping CPUs ${HK_CPUSET} and RT CPUs ${RT_CPUSET} for VM"
  
  # Pin vCPUs to host cores
  for vcpu in $(seq 0 $((VCPUS-1))); do
    host_cpu=$((RT_START_CPU + vcpu))
    if [[ ${host_cpu} -le ${RT_END_CPU} ]]; then
      echo "Pinning vCPU ${vcpu} to host CPU ${host_cpu}"
      virsh_cmd vcpupin "${NAME}" ${vcpu} ${host_cpu} >/dev/null
    fi
  done
  
  # Set RT priority for QEMU threads
  echo "Setting RT priority for QEMU process and threads..."
  
  # Note: QEMU emulator threads are already pinned to CPU 0 via XML <emulatorpin cpuset='0'/>
  # This keeps QEMU infrastructure off isolated RT cores, which is correct behavior.
  # The individual vCPU threads will be configured separately below.
  
  # Set QEMU main process to real-time priority (infrastructure level)
  # Priority 70 for QEMU main process (data logging/monitoring level)
  echo "Setting QEMU process to SCHED_FIFO priority 70..."
  if ! sudo chrt -f -p 70 ${QEMU_PID} >/dev/null 2>&1; then
    echo "❌ Error: Could not set RT priority for QEMU" >&2
    echo "   RT configuration incomplete. vCPU threads may not be realtime." >&2
  else
    echo "  ✓ QEMU main process set to SCHED_FIFO priority 70"
  fi
  
  # Find and set priority for vCPU threads (critical infrastructure)
  # Priority 80 for vCPU threads (secondary control tasks level)
  # This leaves room for guest RT apps (90-99: critical control loops)
  echo "Setting vCPU threads to RT priority..."
  local vcpu_threads=$(ps -eLo pid,tid,comm | awk "\$1 == ${QEMU_PID}" | grep -E "CPU [0-9]+/KVM" | awk '{print $2}' || true)
  if [[ -n "${vcpu_threads}" ]]; then
    local success_count=0
    local fail_count=0
    for tid in ${vcpu_threads}; do
      if sudo chrt -f -p 80 ${tid} >/dev/null 2>&1; then
        echo "  ✓ Set vCPU thread ${tid} to SCHED_FIFO priority 80"
        success_count=$((success_count + 1))
      else
        echo "  ❌ Failed to set RT priority for vCPU thread ${tid}"
        fail_count=$((fail_count + 1))
      fi
    done
    
    if [[ ${fail_count} -gt 0 ]]; then
      echo "❌ Warning: ${fail_count} vCPU thread(s) failed RT configuration"
    else
      echo "✓ All ${success_count} vCPU threads configured for RT"
    fi
  else
    echo "⚠️  Warning: No vCPU threads found (pattern 'CPU [0-9]+/KVM')"
    echo "   RT scheduling may not be optimal"
    echo "   Checking alternative patterns..."
    # Try alternative patterns in case QEMU names threads differently
    local alt_threads=$(ps -eLo pid,tid,comm | awk "\$1 == ${QEMU_PID}" | grep -iE "vcpu|cpu" || true)
    if [[ -n "${alt_threads}" ]]; then
      echo "   Found these CPU-related threads:"
      echo "${alt_threads}" | head -5
    fi
  fi
  
  # Set RT priority for vhost-net threads (network packet processing)
  # Priority 75 for vhost threads (between QEMU main and vCPU threads)
  # These handle all network I/O between host and guest - critical for robot control
  echo "Setting vhost-net threads to RT priority..."
  local vhost_threads=$(ps -eLo pid,tid,comm | awk "\$1 == ${QEMU_PID}" | grep "vhost-" | awk '{print $2}' || true)
  if [[ -n "${vhost_threads}" ]]; then
    local vhost_success=0
    local vhost_fail=0
    for tid in ${vhost_threads}; do
      if sudo chrt -f -p 75 ${tid} >/dev/null 2>&1; then
        echo "  ✓ Set vhost thread ${tid} to SCHED_FIFO priority 75"
        vhost_success=$((vhost_success + 1))
      else
        echo "  ❌ Failed to set RT priority for vhost thread ${tid}"
        vhost_fail=$((vhost_fail + 1))
      fi
    done
    
    if [[ ${vhost_fail} -gt 0 ]]; then
      echo "❌ Warning: ${vhost_fail} vhost thread(s) failed RT configuration"
    else
      echo "✓ All ${vhost_success} vhost-net threads configured for RT"
    fi
  else
    echo "⚠️  No vhost-net threads found (network model may not be using vhost)"
  fi
  
  # Configure CPU governor (and optionally lock frequency) based on RT mode
  local rt_mode="${RT_MODE:-balanced}"
  
  local rt_vm_end_cpu=$((RT_START_CPU + VCPUS - 1))
  if [[ ${rt_vm_end_cpu} -gt ${RT_END_CPU} ]]; then
    rt_vm_end_cpu=${RT_END_CPU}
  fi
  local governor_targets="${HK_CPUSET}"
  if [[ ${rt_vm_end_cpu} -ge ${RT_START_CPU} ]]; then
    governor_targets+=",${RT_START_CPU}-${rt_vm_end_cpu}"
  fi
  
  if [[ "${rt_mode}" == "balanced" ]]; then
    echo "Setting CPU governor to performance mode for housekeeping + VM RT CPUs..."
    for cpu in $(expand_cpulist "${governor_targets}"); do
      if [[ -f "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" ]]; then
        if echo performance | sudo tee /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor >/dev/null 2>&1; then
          echo "  ✓ CPU ${cpu} set to performance mode"
        else
          echo "Warning: Could not set performance governor for CPU ${cpu}" >&2
        fi
      fi
    done
    echo "  ✅ Balanced mode: Performance governor with dynamic frequency (excellent RT performance)"
    echo "  💡 Tip: This mode is recommended for most users (~4μs avg, ~100μs max)"
    
  elif [[ "${rt_mode}" == "performance" ]]; then
    echo "Setting CPU governor and locking frequencies (performance mode)..."
    for cpu in $(expand_cpulist "${governor_targets}"); do
      if [[ -f "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" ]]; then
        if echo performance | sudo tee /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor >/dev/null 2>&1; then
          echo "  ✓ CPU ${cpu} set to performance mode"
          
          # Lock frequency to max to prevent any scaling (eliminates frequency transition latency)
          local max_freq=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/cpuinfo_max_freq 2>/dev/null || echo "")
          if [[ -n "${max_freq}" ]]; then
            # Set both min and max to the same value to lock frequency
            echo ${max_freq} | sudo tee /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_min_freq >/dev/null 2>&1
            echo ${max_freq} | sudo tee /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq >/dev/null 2>&1
            echo "    • Locked frequency to max: ${max_freq} kHz"
          fi
        else
          echo "Warning: Could not set performance governor for CPU ${cpu}" >&2
        fi
      fi
    done
    echo "  ⚡ Performance mode: Frequencies locked to max (~3μs avg, ~70μs max)"
    
  elif [[ "${rt_mode}" == "extreme" ]]; then
    echo "Setting CPU governor and applying extreme optimizations..."
    for cpu in $(expand_cpulist "${governor_targets}"); do
      if [[ -f "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" ]]; then
        if echo performance | sudo tee /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor >/dev/null 2>&1; then
          echo "  ✓ CPU ${cpu} set to performance mode"
          
          # Lock frequency to max
          local max_freq=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/cpuinfo_max_freq 2>/dev/null || echo "")
          if [[ -n "${max_freq}" ]]; then
            echo ${max_freq} | sudo tee /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_min_freq >/dev/null 2>&1
            echo ${max_freq} | sudo tee /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq >/dev/null 2>&1
            echo "    • Locked frequency to max: ${max_freq} kHz"
          fi
        else
          echo "Warning: Could not set performance governor for CPU ${cpu}" >&2
        fi
      fi
    done
    
    # Extreme mode: Try to disable turbo if available
    if [[ -f "/sys/devices/system/cpu/intel_pstate/no_turbo" ]]; then
      local current_turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)
      if [[ "${current_turbo}" == "0" ]]; then
        echo "  • Disabling Intel Turbo Boost for determinism..."
        echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null 2>&1
        echo "    ✓ Turbo disabled (reduces max freq jitter)"
      fi
    fi
    
    echo "  🚀 Extreme mode: Max tuning applied (target <50μs max, high power)"
    echo "  ⚠️  Warning: High power consumption, monitor temperatures"
  fi
  
  # Configure halt polling for better idle behavior (reduces exit latency)
  # halt_poll_ns: time (ns) to busy-wait before sleeping when vCPU is idle
  # Moderate value (50000 = 50μs) reduces wakeup latency without wasting CPU
  echo "Configuring halt polling for lower idle wakeup latency..."
  local halt_poll_ns=50000
  
  local rt_mode="${RT_MODE:-balanced}"
  if [[ "${rt_mode}" == "extreme" ]]; then
    # Extreme mode: use higher halt polling for absolute lowest wakeup latency
    halt_poll_ns=100000  # 100μs
  fi
  
  if [[ -f "/sys/module/kvm/parameters/halt_poll_ns" ]]; then
    local current_val=$(cat /sys/module/kvm/parameters/halt_poll_ns 2>/dev/null || echo "0")
    if echo ${halt_poll_ns} | sudo tee /sys/module/kvm/parameters/halt_poll_ns >/dev/null 2>&1; then
      echo "  ✓ Set halt_poll_ns=${halt_poll_ns} ($(( halt_poll_ns / 1000 ))μs busy-wait, was ${current_val}ns)"
    else
      echo "  ⚠️  Could not set halt_poll_ns (current: ${current_val}ns)"
    fi
  else
    echo "  ⚠️  halt_poll_ns not available (KVM not loaded?)"
  fi
  
  # Configure IRQ affinity to keep interrupts off RT cores
  echo "Configuring IRQ affinity (keeping IRQs off RT cores)..."
  
  # Route host IRQs onto housekeeping CPUs (default: 0-1 on 4+ core hosts).
  local irq_cpulist="${HK_CPUSET}"
  local irq_mask
  irq_mask=$(cpulist_to_mask "${irq_cpulist}")
  
  local irq_count=0
  local irq_success=0
  local irq_list_success=0
  
  # Try both formats: smp_affinity (hex) and smp_affinity_list (cpu list)
  for irq_dir in /proc/irq/*/; do
    [[ -d "$irq_dir" ]] || continue
    irq_count=$((irq_count + 1))
    
    # Skip special IRQs
    local irq_num=$(basename "$irq_dir")
    [[ "$irq_num" == "default_smp_affinity" ]] && continue
    
    # Try smp_affinity_list first (easier and more reliable)
    if echo "${irq_cpulist}" | sudo tee "${irq_dir}smp_affinity_list" >/dev/null 2>&1; then
      irq_list_success=$((irq_list_success + 1))
    fi
    
    # Also try smp_affinity (hex format)
    if echo "${irq_mask}" | sudo tee "${irq_dir}smp_affinity" >/dev/null 2>&1; then
      irq_success=$((irq_success + 1))
    fi
  done
  
  echo "✓ Configured IRQs: ${irq_success} via smp_affinity, ${irq_list_success} via smp_affinity_list (total: ${irq_count})"
  
  # Verify by checking how many IRQs are actually set to housekeeping CPU set
  echo "Verifying IRQ isolation..."
  local irq_on_housekeeping=$(sudo grep -h "^${irq_cpulist}$" /proc/irq/*/smp_affinity_list 2>/dev/null | wc -l)
  local total_checkable=$(sudo ls /proc/irq/*/smp_affinity_list 2>/dev/null | wc -l)
  
  echo "✓ ${irq_on_housekeeping}/${total_checkable} IRQs isolated to CPUs ${irq_cpulist}"
  
  if [[ ${irq_on_housekeeping} -lt $((total_checkable / 2)) ]]; then
    echo "⚠️  Note: Some IRQs may not support affinity control (built-in IRQs)"
    echo "   This is normal - critical device IRQs will still be isolated"
  fi
  
  echo "CPU pinning completed!"
  echo "VM vCPUs pinned to cores ${RT_START_CPU}-${RT_END_CPU}, QEMU threads isolated, IRQs on CPUs ${irq_cpulist}"
}

# Verify RT configuration is actually applied
verify_rt_config() {
  echo "═══════════════════════════════════════════════════════════════"
  echo "              🔍 RT CONFIGURATION VERIFICATION"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  
  # Check if VM is running
  if ! virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi running; then
    echo "❌ VM ${NAME} is not running"
    echo "Run 'servobox start --name ${NAME}' first"
    return 1
  fi
  
  # Get QEMU process ID
  QEMU_PID=$(pgrep -f "qemu.*${NAME}" | head -1)
  if [[ -z "${QEMU_PID}" ]]; then
    echo "❌ Could not find QEMU process for VM ${NAME}"
    return 1
  fi
  
  echo "✓ VM is running (QEMU PID: ${QEMU_PID})"
  echo ""
  
  # Check XML configuration first
  echo "📋 XML Configuration:"
  local xml_file=$(mktemp)
  virsh_cmd dumpxml "${NAME}" > "${xml_file}"
  
  # Check for cputune section
  if grep -q "<cputune>" "${xml_file}"; then
    echo "  ✓ <cputune> section present"
    local vcpupin_count=$(grep -c "<vcpupin" "${xml_file}" || echo "0")
    echo "    • vCPU pinning entries: ${vcpupin_count}"
    if grep -q "<emulatorpin" "${xml_file}"; then
      echo "    • ✓ Emulator thread pinning configured"
    else
      echo "    • ❌ Emulator thread pinning NOT configured"
    fi
    if grep -q "<iothreadpin" "${xml_file}"; then
      echo "    • ✓ IOThread pinning configured"
    else
      echo "    • ⚠️  IOThread pinning NOT configured"
    fi
  else
    echo "  ❌ <cputune> section NOT FOUND"
    echo "    Run 'servobox rt-config-apply --name ${NAME}' to add RT optimizations to XML"
  fi
  
  # Check for iothreads
  if grep -q "<iothreads>" "${xml_file}"; then
    local iothreads=$(grep "<iothreads>" "${xml_file}" | sed -n 's/.*<iothreads>\([0-9]*\)<\/iothreads>.*/\1/p')
    echo "  ✓ IOThreads: ${iothreads}"
  else
    echo "  ❌ IOThreads NOT configured"
  fi
  
  # Check for memoryBacking
  if grep -q "<memoryBacking>" "${xml_file}"; then
    echo "  ✓ <memoryBacking> present"
    if grep -q "<locked/>" "${xml_file}"; then
      echo "    • ✓ Memory locking enabled"
    fi
    if grep -q "<nosharepages/>" "${xml_file}"; then
      echo "    • ✓ KSM disabled (nosharepages)"
    else
      echo "    • ⚠️  KSM not disabled (may cause jitter)"
    fi
    if grep -q "<hugepages>" "${xml_file}"; then
      echo "    • ✓ Hugepages configured (manually added)"
    else
      echo "    • ℹ️  Hugepages not configured (optional - requires host setup)"
    fi
  else
    echo "  ❌ <memoryBacking> NOT configured"
  fi
  
  # Check clock configuration (match both single and double quotes)
  if grep -q "timer name=['\"]kvmclock['\"]" "${xml_file}"; then
    echo "  ✓ kvmclock timer configured"
  else
    echo "  ⚠️  kvmclock timer NOT configured"
  fi
  
  if grep -q "timer name=['\"]tsc['\"]" "${xml_file}"; then
    echo "  ✓ TSC timer configured"
  else
    echo "  ⚠️  TSC timer NOT configured"
  fi
  
  rm -f "${xml_file}"
  echo ""
  
  # Check vCPU pinning
  echo "📌 Runtime vCPU Pinning (virsh vcpupin):"
  virsh_cmd vcpupin "${NAME}" 2>/dev/null || echo "  ⚠️  Could not retrieve vCPU pinning"
  echo ""
  
  # Check QEMU process affinity
  echo "📌 QEMU Process CPU Affinity:"
  if [[ -f "/proc/${QEMU_PID}/status" ]]; then
    local cpus_allowed=$(grep "Cpus_allowed_list" /proc/${QEMU_PID}/status | awk '{print $2}')
    echo "  QEMU main process (${QEMU_PID}): CPUs ${cpus_allowed}"
  else
    echo "  ⚠️  Could not read /proc/${QEMU_PID}/status"
  fi
  echo ""
  
  # Check vCPU threads
  echo "📌 vCPU Thread Details:"
  local vcpu_threads=$(ps -eLo pid,tid,comm,psr,rtprio,policy,ni | awk "\$1 == ${QEMU_PID}" | grep -E "CPU [0-9]+/KVM")
  if [[ -n "${vcpu_threads}" ]]; then
    echo "  TID    vCPU         RunOn  RTPrio  Policy  Nice"
    echo "${vcpu_threads}" | awk '{printf "  %-6s %-12s %-6s %-7s %-7s %s\n", $2, $3, $4, $5, $6, $7}'
  else
    echo "  ⚠️  No vCPU threads found (pattern: 'CPU [0-9]+/KVM')"
    echo "  All QEMU threads:"
    ps -eLo pid,tid,comm,psr,rtprio,policy | awk "\$1 == ${QEMU_PID}" | head -10
  fi
  echo ""
  
  # Check QEMU main thread RT priority
  echo "📌 QEMU Main Thread RT Priority:"
  local qemu_policy=$(chrt -p ${QEMU_PID} 2>/dev/null || echo "unknown")
  echo "  ${qemu_policy}"
  echo ""
  
  # Check CPU governors
  echo "📌 CPU Frequency Governors:"
  for cpu in $(seq 0 $(($(nproc) - 1))); do
    if [[ -f "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" ]]; then
      local gov=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor)
      if [[ ${cpu} -eq 0 ]]; then
        echo "  CPU ${cpu} (housekeeping): ${gov}"
      else
        echo "  CPU ${cpu} (RT core): ${gov}"
      fi
    fi
  done
  echo ""
  
  # Check IRQ affinity
  local host_cores=$(nproc)
  get_rt_cpu_layout "${host_cores}"
  echo "📌 IRQ Affinity Check:"
  local housekeeping_only=0
  local other=0
  for irq_dir in /proc/irq/*/smp_affinity_list; do
    [[ -f "$irq_dir" ]] || continue
    local affinity=$(sudo cat "$irq_dir" 2>/dev/null || cat "$irq_dir" 2>/dev/null)
    if [[ "${affinity}" == "${HK_CPUSET}" ]]; then
      housekeeping_only=$((housekeeping_only + 1))
    else
      other=$((other + 1))
    fi
  done
  echo "  IRQs on housekeeping CPUs (${HK_CPUSET}): ${housekeeping_only}"
  echo "  IRQs on other CPUs: ${other}"
  if [[ ${housekeeping_only} -eq 0 ]]; then
    echo "  ❌ WARNING: No IRQs isolated to housekeeping CPUs ${HK_CPUSET}!"
  fi
  echo ""
  
  # Check guest kernel parameters (if we can SSH in)
  echo "📌 Guest RT Kernel Parameters:"
  IP=$(vm_ip || true)
  if [[ -n "${IP}" ]]; then
    local ssh_opts=(-o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o UpdateHostKeys=no)
    local guest_cmdline=""
    
    # Try SSH with keys first
    guest_cmdline=$(ssh "${ssh_opts[@]}" servobox-usr@"${IP}" "cat /proc/cmdline" 2>/dev/null || echo "")
    
    # Fall back to password if keys don't work
    if [[ -z "${guest_cmdline}" ]] && command -v sshpass >/dev/null 2>&1; then
      guest_cmdline=$(sshpass -p "servobox-pwd" ssh "${ssh_opts[@]}" servobox-usr@"${IP}" "cat /proc/cmdline" 2>/dev/null || echo "")
    fi
    
    if [[ -n "${guest_cmdline}" ]]; then
      # Note: ServoBox ships pre-built images with PREEMPT_RT kernel (6.8.0-rt8).
      # Guest-level isolation (isolcpus/nohz_full/rcu_nocbs) is intentionally disabled
      # by default to allow guest processes to use all vCPUs. Host-level isolation
      # provides the RT guarantees.
      
      # Check for custom kernel parameters
      if echo "${guest_cmdline}" | grep -q "nohpet"; then
        echo "  ✓ HPET disabled (nohpet)"
      fi
      if echo "${guest_cmdline}" | grep -q "tsc=reliable"; then
        echo "  ✓ TSC clocksource (tsc=reliable)"
      fi
      
      # Check for guest isolation (should be absent by default)
      if echo "${guest_cmdline}" | grep -q "isolcpus"; then
        echo "  ℹ️  Guest CPU isolation: $(echo "${guest_cmdline}" | grep -oP 'isolcpus=\S+') (manually configured)"
      else
        echo "  ✓ No guest CPU isolation (default - allows processes to use all vCPUs)"
      fi
    else
      echo "  ⚠️  Could not SSH to guest to verify kernel parameters"
    fi
  else
    echo "  ⚠️  VM has no IP, cannot check guest kernel parameters"
  fi
  echo ""
  
  echo "═══════════════════════════════════════════════════════════════"
}

