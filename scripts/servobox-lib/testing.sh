#!/usr/bin/env bash
# Testing and validation functions

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

run_latency_test() {
  echo "Running 1kHz real-time latency test on VM ${NAME}..."
  
  IP=$(vm_ip || true)
  if [[ -z "${IP}" ]]; then
    echo "Error: VM ${NAME} not accessible" >&2
    exit 1
  fi
  
  echo "VM IP: ${IP}"
  echo "Testing 1kHz timing requirements (1000μs cycle time) for ${TEST_DURATION} seconds..."
  
  # Ensure SSH is ready (gives cloud-init time to finalize sudoers as well)
  wait_for_sshd "${IP}" 60 || true

  # Common SSH options: avoid touching known_hosts in quick dev cycles
  # Separate options for scp (no -t flag) and ssh (with -t flag for real-time output)
  SCP_OPTS=(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o UpdateHostKeys=no)
  SSH_OPTS=(-t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o UpdateHostKeys=no)

  # Create a temporary script to handle cloud-init wait and cyclictest installation
  local temp_script="/tmp/servobox-test-$$.sh"
  local loops=$((TEST_DURATION * 1000))
  
  # Create the test script content
  cat > "${temp_script}" << 'EOF'
#!/bin/bash
set -e

echo "Real-time latency test (cyclictest) - 1kHz Application Focus"
echo "Testing 1kHz timing requirements (1000μs cycle time)..."
echo "Running for ${TEST_DURATION} seconds on isolated CPUs..."

# Wait for cloud-init to complete (up to 60 seconds)
echo "Waiting for cloud-init to complete..."
timeout 60 bash -c 'while [[ ! -f /var/lib/cloud/instance/boot-finished ]]; do echo "Waiting for cloud-init..."; sleep 2; done; echo "Cloud-init completed"' || echo "Cloud-init timeout, proceeding anyway"

# Check if cyclictest is available and install if needed
echo "Checking for cyclictest availability..."
if ! command -v cyclictest >/dev/null 2>&1; then
  echo "Installing rt-tests package..."
  apt-get update && apt-get -y install rt-tests
fi

# Run cyclictest with maximum RT optimizations:
# -m: lock memory (prevent page faults)
# --policy=fifo: explicit SCHED_FIFO  
# Note: Don't use -a flag because isolated CPUs need special handling
# The RT priority will ensure we get CPU time on isolated cores
taskset -c 1 cyclictest -t1 -p 80 -m -i 1000 -l ${loops} --policy=fifo --duration=${TEST_DURATION}
EOF

  # Replace the placeholder variables in the script
  sed -i "s/\${TEST_DURATION}/${TEST_DURATION}/g" "${temp_script}"
  sed -i "s/\${loops}/${loops}/g" "${temp_script}"
  
  # Make the script executable
  chmod +x "${temp_script}"
  
  # Upload the script to the VM using scp and run it
  echo "Uploading test script to VM..."
  if ! scp "${SCP_OPTS[@]}" "${temp_script}" servobox-usr@"${IP}":/tmp/servobox-test.sh; then
    echo "Failed to upload test script, trying with password..."
    if command -v sshpass >/dev/null 2>&1; then
      if ! sshpass -p "servobox-pwd" scp "${SCP_OPTS[@]}" "${temp_script}" servobox-usr@"${IP}":/tmp/servobox-test.sh; then
        echo "Failed to upload test script even with password" >&2
        rm -f "${temp_script}" 2>/dev/null || true
        exit 1
      fi
    else
      echo "Failed to upload test script and sshpass not available" >&2
      rm -f "${temp_script}" 2>/dev/null || true
      exit 1
    fi
  fi
  
  local test_cmd="chmod +x /tmp/servobox-test.sh && /tmp/servobox-test.sh; rm -f /tmp/servobox-test.sh"
  
  # Check if stress-ng is available and enabled for concurrent stress testing
  STRESS_PID=""
  if [[ "${ENABLE_STRESS}" -eq 1 ]]; then
    if command -v stress-ng >/dev/null 2>&1; then
      # Introspect system resources
      local total_cpus=$(nproc)
      local total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')
      
      # Calculate 80% utilization
      local stress_cpus=$(echo "scale=0; ${total_cpus} * 0.8 / 1" | bc)
      local stress_mem_mb=$(echo "scale=0; ${total_mem_mb} * 0.8 / 1" | bc)
      
      # Ensure at least 1 CPU and reasonable memory
      if [[ ${stress_cpus} -lt 1 ]]; then stress_cpus=1; fi
      if [[ ${stress_mem_mb} -lt 256 ]]; then stress_mem_mb=256; fi
      
      echo "Starting host stress test (concurrent with guest test)..."
      echo "Host resources: ${total_cpus} CPUs, ${total_mem_mb} MB RAM"
      echo "Stressing: ${stress_cpus} CPUs (~80%), ${stress_mem_mb} MB RAM (~80%)"
      
      # Start stress test in background with CPU + memory stress
      stress-ng --cpu ${stress_cpus} --vm 2 --vm-bytes ${stress_mem_mb}M --timeout ${TEST_DURATION} >/dev/null 2>&1 &
      STRESS_PID=$!
      echo "Host stress test started (PID: ${STRESS_PID})"
    else
      echo "Warning: --stress-ng requested but stress-ng not available on host" >&2
      echo "Install with: sudo apt install stress-ng" >&2
    fi
  else
    echo "Running test without host stress (use --stress-ng to enable)"
  fi

  # Run the guest cyclictest and capture output
  echo "Running cyclictest on guest VM..."
  local cyclictest_output=""
  local ssh_exit_code=0
  
  # Run cyclictest (this will block until completion)
  echo "Executing test (this will take ${TEST_DURATION} seconds)..."
  
  # Create a temporary file to capture output while streaming
  local output_file="/tmp/servobox-test-output-$$.log"
  
  # Function to run SSH with real-time output and capture
  run_ssh_with_capture() {
    local ssh_args=("$@")
    local capture_file="${ssh_args[-1]}"
    unset ssh_args[-1]  # Remove the last argument (capture file)
    
    # Use tee to both display and capture output
    ssh "${ssh_args[@]}" 2>&1 | tee "$capture_file"
    return ${PIPESTATUS[0]}
  }
  
  # Function to run SSH with password and real-time output
  run_ssh_with_password() {
    local password="$1"
    shift
    local ssh_args=("$@")
    local capture_file="${ssh_args[-1]}"
    unset ssh_args[-1]  # Remove the last argument (capture file)
    
    # Use sshpass with tee to both display and capture output
    sshpass -p "$password" ssh "${ssh_args[@]}" 2>&1 | tee "$capture_file"
    return ${PIPESTATUS[0]}
  }
  
  # Try without password first
  if run_ssh_with_capture "${SSH_OPTS[@]}" servobox-usr@"${IP}" "sudo -n bash -c '${test_cmd}'" "$output_file"; then
    ssh_exit_code=0
    echo "Test completed successfully"
  else
    ssh_exit_code=$?
    echo "First attempt failed (exit code: ${ssh_exit_code}), trying with password..."
    # Fall back to password-based sudo using the standard password
    PW="servobox-pwd"
    if command -v sshpass >/dev/null 2>&1; then
      # Allocate a TTY and provide password to sudo via -S (stdin)
      # Use -tt for double TTY allocation for password handling
      if run_ssh_with_password "${PW}" -tt -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o UpdateHostKeys=no servobox-usr@"${IP}" "printf '%s\n' '${PW}' | sudo -S -k bash -c '${test_cmd}'" "$output_file"; then
        ssh_exit_code=0
        echo "Test completed successfully (with password)"
      else
        ssh_exit_code=$?
        echo "Password attempt also failed (exit code: ${ssh_exit_code})"
      fi
    else
      echo "sudo on guest requires a password. Install 'sshpass' or retry after cloud-init applies NOPASSWD." >&2
      # Clean up stress process if it was started
      if [[ -n "${STRESS_PID}" ]]; then
        if ! kill ${STRESS_PID} 2>/dev/null; then
          echo "Warning: Failed to kill stress process ${STRESS_PID}" >&2
        fi
      fi
      rm -f "$output_file" 2>/dev/null || true
      exit 1
    fi
  fi
  
  # Read the captured output for parsing
  cyclictest_output=$(cat "$output_file" 2>/dev/null || echo "")
  rm -f "$output_file" 2>/dev/null || true
  
  # Raw output is now shown in real-time above, no need to duplicate it
  
  # Clean up stress test if it's still running
  if [[ -n "${STRESS_PID}" ]]; then
    if kill -0 ${STRESS_PID} 2>/dev/null; then
      echo "Stopping host stress test..."
      if ! kill ${STRESS_PID} 2>/dev/null; then
        echo "Warning: Failed to kill stress process ${STRESS_PID}" >&2
      fi
      if ! wait ${STRESS_PID} 2>/dev/null; then
        echo "Warning: Failed to wait for stress process ${STRESS_PID}" >&2
      fi
    fi
  fi
  
  # Debug: show what we captured
  if [[ -z "${cyclictest_output}" ]]; then
    echo "Warning: No output captured from cyclictest (exit code: ${ssh_exit_code})" >&2
    echo "This might indicate a problem with the test execution." >&2
    exit 1
  fi
  
  # Clean up temporary script
  rm -f "${temp_script}" 2>/dev/null || true
}

cmd_test() {
  parse_args "$@"
  ensure_vm_running
  run_latency_test
}

cmd_debug() {
  parse_args "$@"
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "VM ${NAME} not found"
    exit 1
  fi
  echo "=== VM Debug Info ==="
  echo "VM State: $(virsh_cmd domstate "${NAME}" 2>/dev/null || echo 'unknown')"
  IP=$(vm_ip || true)
  echo "VM IP: ${IP:-none}"
  
  echo "Password: servobox-pwd (standard default)"
  
  echo -e "\n=== Cloud-init logs ==="
  if command -v virt-cat >/dev/null 2>&1; then
    echo "--- /var/log/cloud-init.log (last 20 lines) ---"
    virt-cat -d "${NAME}" /var/log/cloud-init.log 2>/dev/null | tail -20 || echo "Could not read cloud-init.log"
    echo -e "\n--- /home/servobox-usr/.ssh/authorized_keys ---"
    virt-cat -d "${NAME}" /home/servobox-usr/.ssh/authorized_keys 2>/dev/null || echo "Could not read authorized_keys"
    echo -e "\n--- /etc/ssh/sshd_config.d/99-servobox.conf ---"
    virt-cat -d "${NAME}" /etc/ssh/sshd_config.d/99-servobox.conf 2>/dev/null || echo "Could not read sshd config"
  else
    echo "virt-cat not available (install libguestfs-tools)"
  fi
}

cmd_smi_check() {
  echo "═══════════════════════════════════════════════════════════════"
  echo "              🔍 SMI (System Management Interrupt) CHECK"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  
  # Check if hwlat tracer is available (kernel RT debugging)
  if [[ -d /sys/kernel/debug/tracing ]]; then
    echo "📊 Checking for SMI-induced latency using hwlat tracer..."
    echo ""
    
    # Enable hardware latency detector
    echo "Setting up hardware latency detector (10 second sample)..."
    sudo sh -c "echo hwlat > /sys/kernel/debug/tracing/current_tracer" 2>/dev/null || {
      echo "❌ hwlat tracer not available (need CONFIG_HWLAT_TRACER in kernel)"
      echo ""
      echo "Alternative: Check SMI count manually:"
      echo "  sudo cat /sys/firmware/acpi/interrupts/gpe* 2>/dev/null | grep enabled"
      return 1
    }
    
    # Run for 10 seconds
    sudo sh -c "echo 1 > /sys/kernel/debug/tracing/tracing_on"
    sleep 10
    sudo sh -c "echo 0 > /sys/kernel/debug/tracing/tracing_on"
    
    # Check results
    echo "Hardware latency results:"
    sudo grep -E "max:|count:" /sys/kernel/debug/tracing/trace | head -20
    
    # Reset
    sudo sh -c "echo nop > /sys/kernel/debug/tracing/current_tracer"
    echo ""
  fi
  
  # Check BIOS settings that affect SMIs
  echo "🔧 BIOS/Firmware Settings Recommendations:"
  echo ""
  echo "To reduce SMIs, configure these BIOS settings:"
  echo "  1. Disable C-States (CPU power saving)"
  echo "  2. Disable P-States or set to max performance"
  echo "  3. Disable Turbo Boost (use fixed frequency)"
  echo "  4. Disable USB Legacy Support"
  echo "  5. Disable ACPI thermal management"
  echo "  6. Set Power Profile to 'Performance' or 'Maximum Performance'"
  echo ""
  
  # Check current C-states
  echo "📋 Current Host Power State Configuration:"
  echo ""
  
  # Check if intel_idle is loaded
  if lsmod | grep -q intel_idle; then
    echo "  • intel_idle driver: LOADED (allows C-states)"
    echo "    To disable: Add 'intel_idle.max_cstate=0' to kernel cmdline"
  else
    echo "  • intel_idle driver: not loaded"
  fi
  
  # Check C-states
  echo ""
  echo "  • Available C-states on CPU 0:"
  if [[ -d /sys/devices/system/cpu/cpu0/cpuidle ]]; then
    local cstates=$(ls -d /sys/devices/system/cpu/cpu0/cpuidle/state* 2>/dev/null | wc -l)
    echo "    ${cstates} C-states available"
    for state in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do
      [[ -f "$state" ]] && echo "    - $(cat $state 2>/dev/null)"
    done
  else
    echo "    No C-state information available"
  fi
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "💡 To minimize SMI impact:"
  echo "  1. Boot with: intel_idle.max_cstate=0 processor.max_cstate=1"
  echo "  2. Boot with: idle=poll (prevents CPU from entering idle states)"
  echo "  3. Configure BIOS for maximum performance (disable power management)"
  echo "  4. Use 'tuned-adm profile latency-performance'"
  echo ""
}


