#!/usr/bin/env bash
# Remote target support for ServoBox
# Enables servobox commands to work on remote RT machines (Jetson, NUC, etc.)

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
if ! declare -f recipe_source_recipes_dir >/dev/null 2>&1; then
  source "${SCRIPT_DIR}/recipe-source.sh"
fi

# Remote target configuration (from environment)
# SERVOBOX_TARGET_IP   - Required: IP address of remote RT machine
# SERVOBOX_TARGET_USER - Optional: SSH user (default: servobox-usr)
# SERVOBOX_TARGET_PORT - Optional: SSH port (default: 22)

# Check if we're operating in remote target mode
is_remote_target() {
  [[ -n "${SERVOBOX_TARGET_IP:-}" ]]
}

# Get remote target configuration
get_remote_ip() {
  echo "${SERVOBOX_TARGET_IP:-}"
}

get_remote_user() {
  # Default to current user (more sensible for remote targets than servobox-usr)
  echo "${SERVOBOX_TARGET_USER:-${USER}}"
}

get_remote_port() {
  echo "${SERVOBOX_TARGET_PORT:-22}"
}

# Standard SSH options for remote target connections
# Avoids host key issues for quick dev cycles
get_ssh_opts() {
  echo "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o UpdateHostKeys=no -o ConnectTimeout=10"
}

# Execute command on remote target
# Usage: remote_exec "command" [timeout_seconds]
remote_exec() {
  local cmd="$1"
  local timeout="${2:-30}"
  local user=$(get_remote_user)
  local ip=$(get_remote_ip)
  local port=$(get_remote_port)
  local ssh_opts=$(get_ssh_opts)
  
  if [[ -z "${ip}" ]]; then
    echo "Error: SERVOBOX_TARGET_IP not set" >&2
    return 1
  fi
  
  timeout "${timeout}" ssh ${ssh_opts} -p "${port}" "${user}@${ip}" "${cmd}"
}

# Execute command on remote target with TTY (for interactive commands)
# Usage: remote_exec_tty "command"
remote_exec_tty() {
  local cmd="$1"
  local user=$(get_remote_user)
  local ip=$(get_remote_ip)
  local port=$(get_remote_port)
  local ssh_opts=$(get_ssh_opts)
  
  if [[ -z "${ip}" ]]; then
    echo "Error: SERVOBOX_TARGET_IP not set" >&2
    return 1
  fi
  
  ssh -t ${ssh_opts} -p "${port}" "${user}@${ip}" "${cmd}"
}

# Execute command with sudo on remote target
# Usage: remote_sudo "command" [timeout_seconds]
remote_sudo() {
  local cmd="$1"
  local timeout="${2:-60}"
  local user=$(get_remote_user)
  local ip=$(get_remote_ip)
  local port=$(get_remote_port)
  
  if [[ -z "${ip}" ]]; then
    echo "Error: SERVOBOX_TARGET_IP not set" >&2
    return 1
  fi
  
  # Simple SSH options (no UserKnownHostsFile tricks that cause warnings)
  local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
  
  # For sudo commands, we need interactive TTY for password prompts
  # Don't use timeout wrapper - let SSH handle it naturally
  ssh -t ${ssh_opts} -p "${port}" "${user}@${ip}" "sudo ${cmd}"
}

# Copy file to remote target
# Usage: remote_copy_to "local_path" "remote_path"
remote_copy_to() {
  local local_path="$1"
  local remote_path="$2"
  local user=$(get_remote_user)
  local ip=$(get_remote_ip)
  local port=$(get_remote_port)
  local ssh_opts=$(get_ssh_opts)
  
  if [[ -z "${ip}" ]]; then
    echo "Error: SERVOBOX_TARGET_IP not set" >&2
    return 1
  fi
  
  scp ${ssh_opts} -P "${port}" -r "${local_path}" "${user}@${ip}:${remote_path}"
}

# Copy file from remote target
# Usage: remote_copy_from "remote_path" "local_path"
remote_copy_from() {
  local remote_path="$1"
  local local_path="$2"
  local user=$(get_remote_user)
  local ip=$(get_remote_ip)
  local port=$(get_remote_port)
  local ssh_opts=$(get_ssh_opts)
  
  if [[ -z "${ip}" ]]; then
    echo "Error: SERVOBOX_TARGET_IP not set" >&2
    return 1
  fi
  
  scp ${ssh_opts} -P "${port}" -r "${user}@${ip}:${remote_path}" "${local_path}"
}

# Check if remote target is reachable
# Usage: check_remote_connection
check_remote_connection() {
  local ip=$(get_remote_ip)
  local port=$(get_remote_port)
  local user=$(get_remote_user)
  
  if [[ -z "${ip}" ]]; then
    echo "Error: SERVOBOX_TARGET_IP not set" >&2
    return 1
  fi
  
  echo "Checking connection to remote target ${user}@${ip}:${port}..."
  
  # Check if host is reachable (ping)
  if ! timeout 5 bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null; then
    echo "Error: Cannot connect to ${ip}:${port}" >&2
    echo "  • Check that the remote machine is powered on" >&2
    echo "  • Verify the IP address is correct" >&2
    echo "  • Ensure SSH is running on the remote machine" >&2
    return 1
  fi
  
  # Try SSH connection
  if ! remote_exec "echo 'Connection OK'" 10 2>/dev/null; then
    echo "Error: SSH connection failed to ${user}@${ip}" >&2
    echo "  • Check SSH credentials (user: ${user})" >&2
    echo "  • Verify SSH key or password authentication is configured" >&2
    echo "  • Try: ssh ${user}@${ip}" >&2
    return 1
  fi
  
  echo "✓ Connected to remote target ${ip}"
  return 0
}

# Wait for remote target SSH to become available
# Usage: wait_for_remote_ssh [timeout_seconds]
wait_for_remote_ssh() {
  local timeout="${1:-60}"
  local ip=$(get_remote_ip)
  local port=$(get_remote_port)
  local elapsed=0
  
  echo "Waiting for SSH on ${ip}:${port}..."
  
  while [[ ${elapsed} -lt ${timeout} ]]; do
    if timeout 2 bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null; then
      if remote_exec "true" 5 2>/dev/null; then
        echo "✓ SSH available on ${ip}"
        return 0
      fi
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo "  Waiting... (${elapsed}/${timeout}s)"
  done
  
  echo "Error: SSH connection timeout after ${timeout}s" >&2
  return 1
}

# Print error for commands that don't apply to remote targets
remote_not_applicable() {
  local cmd="$1"
  local ip=$(get_remote_ip)
  
  echo "Error: '${cmd}' command is not applicable for remote targets" >&2
  echo "" >&2
  echo "Remote target mode is active (SERVOBOX_TARGET_IP=${ip})" >&2
  echo "This command is only for local VM management." >&2
  echo "" >&2
  echo "For remote targets, use these commands:" >&2
  echo "  servobox ssh        - Connect to remote target" >&2
  echo "  servobox status     - Show remote target status" >&2
  echo "  servobox test       - Run RT latency test" >&2
  echo "  servobox run        - Run recipe or command" >&2
  echo "  servobox pkg-install - Install packages" >&2
  echo "  servobox rt-verify  - Verify RT configuration" >&2
  echo "" >&2
  echo "To use VM commands, unset SERVOBOX_TARGET_IP:" >&2
  echo "  unset SERVOBOX_TARGET_IP" >&2
  exit 1
}

# ============================================================================
# Remote Target Commands
# ============================================================================

# SSH to remote target
cmd_remote_ssh() {
  local user=$(get_remote_user)
  local ip=$(get_remote_ip)
  local port=$(get_remote_port)
  local ssh_opts=$(get_ssh_opts)
  
  if ! check_remote_connection; then
    exit 1
  fi
  
  echo "Connecting to ${user}@${ip}..."
  ssh ${ssh_opts} -p "${port}" "${user}@${ip}"
}

# Show remote target IP
cmd_remote_ip() {
  local ip=$(get_remote_ip)
  echo "${ip}"
}

# Show remote target status
cmd_remote_status() {
  local ip=$(get_remote_ip)
  local user=$(get_remote_user)
  local port=$(get_remote_port)
  
  echo "═══════════════════════════════════════════════════════════════"
  echo "              🎯 REMOTE TARGET STATUS"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "Target: ${user}@${ip}:${port}"
  echo ""
  
  if ! check_remote_connection 2>/dev/null; then
    echo "Status: ❌ Unreachable"
    echo ""
    echo "Check that the remote machine is powered on and SSH is running."
    return 1
  fi
  
  echo "Status: ✓ Connected"
  echo ""
  
  # Get system info
  echo "=== System Information ==="
  remote_exec "hostname" 10 2>/dev/null && echo ""
  
  # Get kernel info
  echo "Kernel: $(remote_exec "uname -r" 10 2>/dev/null)"
  
  # Check for RT kernel
  local kernel_version=$(remote_exec "uname -r" 10 2>/dev/null)
  if echo "${kernel_version}" | grep -qi "rt\|preempt"; then
    echo "RT Kernel: ✓ Yes (${kernel_version})"
  else
    echo "RT Kernel: ⚠️  Not detected (kernel: ${kernel_version})"
  fi
  
  # Get architecture
  echo "Architecture: $(remote_exec "uname -m" 10 2>/dev/null)"
  
  # Get distro info
  local distro=$(remote_exec "cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'\"' -f2" 10 2>/dev/null)
  echo "OS: ${distro:-unknown}"
  
  # Get CPU info
  echo ""
  echo "=== Hardware ==="
  local cpu_model=$(remote_exec "grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs" 10 2>/dev/null)
  local cpu_count=$(remote_exec "nproc" 10 2>/dev/null)
  echo "CPU: ${cpu_model:-unknown} (${cpu_count:-?} cores)"
  
  local mem_total=$(remote_exec "free -h 2>/dev/null | awk '/^Mem:/{print \$2}'" 10 2>/dev/null)
  echo "Memory: ${mem_total:-unknown}"
  
  # Check for Jetson-specific info
  local jetson_model=$(remote_exec "cat /proc/device-tree/model 2>/dev/null | tr -d '\0'" 10 2>/dev/null)
  if [[ -n "${jetson_model}" ]]; then
    echo ""
    echo "=== Jetson Platform ==="
    echo "Model: ${jetson_model}"
  fi
  
  # Get uptime
  echo ""
  echo "=== Runtime ==="
  echo "Uptime: $(remote_exec "uptime -p 2>/dev/null || uptime" 10 2>/dev/null)"
  
  # Get load
  local load=$(remote_exec "cat /proc/loadavg 2>/dev/null | awk '{print \$1, \$2, \$3}'" 10 2>/dev/null)
  echo "Load: ${load:-unknown}"
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "Available commands:"
  echo "  servobox ssh          - Connect to remote target"
  echo "  servobox test         - Run RT latency test"
  echo "  servobox run <recipe> - Run recipe or command"
  echo "  servobox pkg-install  - Install packages"
  echo "  servobox rt-verify    - Verify RT configuration"
}

# Run RT latency test on remote target
cmd_remote_test() {
  local ip=$(get_remote_ip)
  local duration="${TEST_DURATION:-60}"
  
  echo "═══════════════════════════════════════════════════════════════"
  echo "              🚀 REMOTE RT LATENCY TEST"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "Target: ${ip}"
  echo "Duration: ${duration} seconds"
  echo ""
  
  if ! check_remote_connection; then
    exit 1
  fi
  
  local user=$(get_remote_user)
  local port=$(get_remote_port)
  local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

  # Check if cyclictest is available
  echo "Checking for cyclictest..."
  if ! remote_exec "command -v cyclictest" 10 2>/dev/null; then
    echo "Installing rt-tests package on remote target..."
    echo "(You may be prompted for sudo password)"
    echo ""
    if ! ssh -t ${ssh_opts} -p "${port}" "${user}@${ip}" "sudo apt-get update && sudo apt-get -y install rt-tests"; then
      echo "Error: Failed to install rt-tests on remote target" >&2
      exit 1
    fi
  fi

  # Determine isolated CPUs or use CPU 1
  local test_cpu="1"
  local isolcpus=$(remote_exec "cat /sys/devices/system/cpu/isolated 2>/dev/null" 10 2>/dev/null)
  if [[ -n "${isolcpus}" && "${isolcpus}" != "" ]]; then
    # Use first isolated CPU
    test_cpu=$(echo "${isolcpus}" | cut -d',' -f1 | cut -d'-' -f1)
    echo "Using isolated CPU: ${test_cpu}"
  else
    echo "Using CPU ${test_cpu} (no CPU isolation detected)"
  fi

  local loops=$((duration * 1000))

  echo ""
  echo "Running cyclictest (this will take ${duration} seconds)..."
  echo "(You may be prompted for sudo password)"
  echo ""

  # Run cyclictest on remote with real-time priority
  local output_file="/tmp/servobox-remote-test-$$.log"

  ssh -t ${ssh_opts} -p "${port}" "${user}@${ip}" \
    "sudo taskset -c ${test_cpu} cyclictest -t1 -p 80 -m -i 1000 -l ${loops} --policy=fifo --duration=${duration}" \
    | tee "${output_file}"

  # Parse results
  local cyclictest_output=$(cat "${output_file}" 2>/dev/null || echo "")
  rm -f "${output_file}" 2>/dev/null || true

  if [[ -n "${cyclictest_output}" ]]; then
    # Use the existing parse function from testing.sh
    parse_cyclictest_results "${cyclictest_output}"
  else
    echo "Warning: Could not capture cyclictest output" >&2
  fi

  echo "Remote latency test completed!"
}

# Verify RT configuration on remote target
cmd_remote_rt_verify() {
  local ip=$(get_remote_ip)
  
  echo "═══════════════════════════════════════════════════════════════"
  echo "              🔍 REMOTE RT CONFIGURATION CHECK"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "Target: ${ip}"
  echo ""
  
  if ! check_remote_connection; then
    exit 1
  fi
  
  local all_ok=1
  
  # Check kernel
  echo "=== Kernel Configuration ==="
  local kernel=$(remote_exec "uname -r" 10 2>/dev/null)
  echo -n "Kernel version: ${kernel} "
  if echo "${kernel}" | grep -qi "rt\|preempt"; then
    echo "✓ (RT kernel detected)"
  else
    echo "⚠️  (Not an RT kernel - may have higher latency)"
    all_ok=0
  fi
  
  # Check PREEMPT_RT
  local preempt=$(remote_exec "cat /sys/kernel/realtime 2>/dev/null || echo 0" 10 2>/dev/null)
  echo -n "PREEMPT_RT: "
  if [[ "${preempt}" == "1" ]]; then
    echo "✓ Enabled"
  else
    echo "⚠️  Not enabled (or not detected)"
    all_ok=0
  fi
  
  # Check CPU isolation
  echo ""
  echo "=== CPU Configuration ==="
  local isolcpus=$(remote_exec "cat /sys/devices/system/cpu/isolated 2>/dev/null" 10 2>/dev/null)
  echo -n "Isolated CPUs: "
  if [[ -n "${isolcpus}" && "${isolcpus}" != "" ]]; then
    echo "✓ ${isolcpus}"
  else
    echo "⚠️  None (consider isolating CPUs for better RT performance)"
    all_ok=0
  fi
  
  # Check nohz_full
  local nohz=$(remote_exec "cat /sys/devices/system/cpu/nohz_full 2>/dev/null" 10 2>/dev/null)
  echo -n "nohz_full CPUs: "
  if [[ -n "${nohz}" && "${nohz}" != "" ]]; then
    echo "✓ ${nohz}"
  else
    echo "⚠️  None"
  fi
  
  # Check CPU governor
  echo ""
  echo "=== Power Management ==="
  local governor=$(remote_exec "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null" 10 2>/dev/null)
  echo -n "CPU Governor: "
  if [[ "${governor}" == "performance" ]]; then
    echo "✓ ${governor}"
  elif [[ -n "${governor}" ]]; then
    echo "⚠️  ${governor} (recommend 'performance' for best RT latency)"
  else
    echo "⚠️  Not available"
  fi
  
  # Check for IRQ balance
  echo ""
  echo "=== IRQ Configuration ==="
  local irqbalance=$(remote_exec "systemctl is-active irqbalance 2>/dev/null || echo inactive" 10 2>/dev/null)
  echo -n "irqbalance: "
  if [[ "${irqbalance}" == "inactive" ]]; then
    echo "✓ Disabled (good for RT)"
  else
    echo "⚠️  ${irqbalance} (consider disabling for better RT performance)"
  fi
  
  # Summary
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  if [[ ${all_ok} -eq 1 ]]; then
    echo "✓ Remote target appears to be properly configured for RT workloads"
  else
    echo "⚠️  Some RT optimizations may be missing"
    echo ""
    echo "Recommendations:"
    echo "  1. Use an RT kernel (PREEMPT_RT patched)"
    echo "  2. Add kernel parameters: isolcpus=1-N nohz_full=1-N rcu_nocbs=1-N"
    echo "  3. Set CPU governor to 'performance'"
    echo "  4. Disable irqbalance: sudo systemctl disable --now irqbalance"
  fi
  echo "═══════════════════════════════════════════════════════════════"
}

# Execute recipe or command on remote target
cmd_remote_run() {
  local recipe_name="$1"
  local is_command=false
  
  if [[ -z "${recipe_name}" ]]; then
    echo "Error: Please provide a recipe name or command" >&2
    echo "Usage: servobox run <recipe-name>" >&2
    echo "       servobox run \"<command>\"" >&2
    exit 1
  fi
  
  # Check if it's a command (contains spaces)
  if [[ "${recipe_name}" =~ [[:space:]] ]]; then
    is_command=true
  fi
  
  if ! check_remote_connection; then
    exit 1
  fi
  
  local ip=$(get_remote_ip)
  
  if [[ "${is_command}" == "true" ]]; then
    # Execute arbitrary command
    echo "Running command on remote target ${ip}..."
    echo ""
    remote_exec_tty "bash -l -c '${recipe_name}'"
  else
    # Execute recipe
    local recipes_dir
    recipes_dir="$(recipe_source_recipes_dir)" || exit 1
    local recipe_dir="${recipes_dir}/${recipe_name}"
    local run_script="${recipe_dir}/run.sh"
    
    if [[ ! -d "${recipe_dir}" ]]; then
      echo "Error: Recipe '${recipe_name}' not found in ${recipes_dir}" >&2
      echo "Available recipes:" >&2
      list_available_recipes
      exit 1
    fi
    
    if [[ ! -f "${run_script}" ]]; then
      echo "Error: Recipe '${recipe_name}' does not have a run.sh script" >&2
      exit 1
    fi
    
    echo "Running recipe '${recipe_name}' on remote target ${ip}..."
    echo ""
    
    # Copy run script to remote and execute
    local script_content
    script_content=$(cat "${run_script}")
    
    remote_exec_tty "bash -l -c '
      echo \"=== Starting recipe ${recipe_name} ===\"
      echo \"Working directory: \$(pwd)\"
      echo \"User: \$(whoami)\"
      echo \"Date: \$(date)\"
      echo \"\"
      
      cat > /tmp/recipe_run.sh << \"EOF\"
${script_content}
EOF
      
      chmod +x /tmp/recipe_run.sh
      echo \"Executing recipe run script...\"
      echo \"\"
      
      if /tmp/recipe_run.sh; then
        echo \"\"
        echo \"=== Recipe ${recipe_name} completed successfully ===\"
      else
        echo \"\"
        echo \"=== Recipe ${recipe_name} failed with exit code \$? ===\"
      fi
      
      rm -f /tmp/recipe_run.sh
      echo \"\"
      echo \"Press Enter to exit...\"
      read
    '"
  fi
}

# Install packages on remote target
cmd_remote_pkg_install() {
  local target="$1"
  local verbose_flag="$2"
  local force_flag="$3"
  local custom_path="$4"
  local custom_is_dir="$5"
  
  if [[ -z "${target}" ]]; then
    echo "Error: Please specify a package or config to install" >&2
    echo "Usage: servobox pkg-install <package|config>" >&2
    exit 1
  fi
  
  local ip=$(get_remote_ip)
  
  if ! check_remote_connection; then
    exit 1
  fi
  
  echo "═══════════════════════════════════════════════════════════════"
  echo "              📦 REMOTE PACKAGE INSTALLATION"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "Target: ${ip}"
  echo "Package: ${target}"
  echo ""
  
  # Determine recipe directory
  local recipes_dir=""
  if [[ "${custom_is_dir}" == "1" && -n "${custom_path}" ]]; then
    recipes_dir="${custom_path}"
  else
    recipes_dir="$(recipe_source_recipes_dir)" || exit 1
  fi

  local config_dir=""
  config_dir="$(recipe_source_configs_dir "${recipes_dir}" || true)"
  
  # Check if target is a config file
  local config_file=""
  if [[ -f "${target}" ]]; then
    config_file="${target}"
  elif [[ -n "${config_dir}" && -f "${config_dir}/${target}.conf" ]]; then
    config_file="${config_dir}/${target}.conf"
  elif [[ -n "${config_dir}" && -f "${config_dir}/${target}" ]]; then
    config_file="${config_dir}/${target}"
  fi
  
  if [[ -n "${config_file}" ]]; then
    # Install from config file
    echo "Installing packages from config: $(basename "${config_file}")"
    echo ""
    
    mapfile -t pkgs < <(grep -v '^#' "${config_file}" | grep -v '^$' || true)
    if [[ ${#pkgs[@]} -eq 0 ]]; then
      echo "No packages in config ${target}"
      exit 0
    fi
    
    for p in "${pkgs[@]}"; do
      echo ""
      echo "Installing package: $p"
      install_package_remote "$p" "${recipes_dir}" "${verbose_flag}" "${force_flag}"
    done
  else
    # Install single package (with dependencies in order, same as VM install)
    local install_order=()
    local pm_args=(--recipe-dir "${recipes_dir}")
    if [[ -x "${PACKAGES_PM:-}" ]]; then
      while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && install_order+=("$pkg")
      done < <("${PACKAGES_PM}" "${pm_args[@]}" install-order "${target}" 2>/dev/null) || true
    fi
    if [[ ${#install_order[@]} -eq 0 ]]; then
      install_order=("${target}")
    else
      echo "Resolving dependencies for ${target}..."
      echo "Will install ${#install_order[@]} packages in order: ${install_order[*]}"
      echo ""
    fi
    for p in "${install_order[@]}"; do
      echo "Installing package: $p"
      install_package_remote "$p" "${recipes_dir}" "${verbose_flag}" "${force_flag}" || exit 1
      echo ""
    done
  fi
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "✓ Remote package installation completed!"
  echo "═══════════════════════════════════════════════════════════════"
}

# Helper: Install a single package on remote target
install_package_remote() {
  local pkg_name="$1"
  local recipes_dir="$2"
  local verbose_flag="$3"
  local force_flag="$4"
  
  local recipe_dir="${recipes_dir}/${pkg_name}"
  if [[ ! -d "${recipe_dir}" ]]; then
    # Support --custom pointing directly to a single recipe directory.
    if [[ -f "${recipes_dir}/recipe.conf" && ( -f "${recipes_dir}/install.sh" || -f "${recipes_dir}/install-online.sh" ) ]]; then
      local recipe_name=""
      recipe_name=$(grep -E '^name=' "${recipes_dir}/recipe.conf" 2>/dev/null | cut -d'"' -f2 | xargs || true)
      if [[ -z "${recipe_name}" || "${recipe_name}" == "${pkg_name}" ]]; then
        recipe_dir="${recipes_dir}"
      fi
    fi
  fi
  
  if [[ ! -d "${recipe_dir}" ]]; then
    echo "Error: Recipe '${pkg_name}' not found in ${recipes_dir}" >&2
    return 1
  fi
  
  local ip=$(get_remote_ip)
  local remote_tmp="/tmp/servobox-recipe-${pkg_name}-$$"
  
  echo "Syncing recipe '${pkg_name}' to remote target..."
  
  # Create remote directory
  remote_exec "mkdir -p ${remote_tmp}" 10
  
  # Copy recipe files to remote
  if ! remote_copy_to "${recipe_dir}/." "${remote_tmp}/"; then
    echo "Error: Failed to copy recipe to remote target" >&2
    return 1
  fi

  # Copy pkg-helpers.sh so install scripts can use apt_update/apt_install etc.
  local recipe_root
  recipe_root="$(dirname "${recipes_dir}")"
  local helpers_src=""
  local helper_candidate
  for helper_candidate in \
    "${REPO_ROOT}/scripts/servobox-tools/pkg-helpers.sh" \
    "${REPO_ROOT}/servobox-tools/pkg-helpers.sh" \
    "/usr/share/servobox/servobox-tools/pkg-helpers.sh" \
    "${recipe_root}/scripts/pkg-helpers.sh" \
    "$(dirname "${recipe_root}")/scripts/pkg-helpers.sh" \
    "${REPO_ROOT}/scripts/pkg-helpers.sh"; do
    if [[ -f "${helper_candidate}" ]]; then
      helpers_src="${helper_candidate}"
      break
    fi
  done
  if [[ -n "${helpers_src}" ]]; then
    if ! remote_copy_to "${helpers_src}" "${remote_tmp}/pkg-helpers.sh"; then
      echo "Warning: Failed to copy pkg-helpers.sh to remote (install may fail if recipe needs it)" >&2
    fi
  fi
  
  # Find install script
  local install_script=""
  if [[ -f "${recipe_dir}/install.sh" ]]; then
    install_script="install.sh"
  elif [[ -f "${recipe_dir}/install-online.sh" ]]; then
    install_script="install-online.sh"
  else
    echo "Error: No install script found in recipe '${pkg_name}'" >&2
    echo "Expected: install.sh or install-online.sh" >&2
    remote_exec "rm -rf ${remote_tmp}" 10 2>/dev/null || true
    return 1
  fi
  
  echo "Running install script: ${install_script}"
  echo ""

  # Run installation on remote. Use stdin from /dev/null so apt/dpkg triggers
  # (e.g. man-db, libc-bin) never block waiting for input when run over SSH.
  # Use env so PACKAGE_HELPERS and RECIPE_DIR are passed through sudo (sudo often strips env).
  # RECIPE_DIR matches package-manager.sh and build-image.sh so install scripts get it consistently.
  # servobox init bakes NOPASSWD sudo for servobox-usr into the image, so no password is needed.
  local user=$(get_remote_user)
  local port=$(get_remote_port)
  local ssh_opts=$(get_ssh_opts)
  local env_vars="RECIPE_DIR=${remote_tmp}"
  if [[ -n "${helpers_src}" ]]; then
    env_vars="${env_vars} PACKAGE_HELPERS=${remote_tmp}/pkg-helpers.sh"
  fi

  # Check if passwordless sudo works for this user
  local use_sshpass=0
  if ! ssh ${ssh_opts} -p "${port}" "${user}@${ip}" "sudo -n true" 2>/dev/null; then
    if [[ "${user}" == "servobox-usr" ]] && command -v sshpass >/dev/null 2>&1; then
      use_sshpass=1
    fi
  fi

  # Run install on remote; capture exit code immediately so we don't lose it (e.g. to cleanup or TTY quirks).
  local exit_code
  if [[ ${use_sshpass} -eq 1 ]]; then
    # Fallback: use known VM password (helps existing VMs or slow cloud-init)
    local run_cmd="sudo -v && cd ${remote_tmp} && chmod +x ${install_script} && sudo env ${env_vars} ./${install_script} </dev/null"
    sshpass -p "servobox-pwd" ssh -t ${ssh_opts} -p "${port}" "${user}@${ip}" "${run_cmd}"
    exit_code=$?
  else
    # Passwordless sudo is available
    local run_cmd="cd ${remote_tmp} && chmod +x ${install_script} && sudo -n env ${env_vars} ./${install_script} </dev/null"
    ssh ${ssh_opts} -p "${port}" "${user}@${ip}" "${run_cmd}"
    exit_code=$?
  fi

  # Cleanup remote temp directory
  remote_exec "rm -rf ${remote_tmp}" 10 2>/dev/null || true

  if [[ ${exit_code} -eq 0 ]]; then
    echo "✓ Package '${pkg_name}' installed successfully on ${ip}"
  else
    echo "❌ Package '${pkg_name}' installation failed on ${ip}" >&2
    return 1
  fi
  
  return 0
}

# List installed packages on remote target
cmd_remote_pkg_installed() {
  local ip=$(get_remote_ip)
  
  if ! check_remote_connection; then
    exit 1
  fi
  
  echo "Installed packages on remote target ${ip}:"
  echo ""
  
  # Check for servobox tracking file on remote
  local tracking_file="/var/lib/servobox/installed-packages"
  local packages=$(remote_exec "cat ${tracking_file} 2>/dev/null" 10 2>/dev/null)
  
  if [[ -n "${packages}" ]]; then
    echo "${packages}"
  else
    echo "No servobox packages tracked on remote target."
    echo ""
    echo "Note: Packages may be installed but not tracked."
    echo "The tracking file is created when using 'servobox pkg-install'."
  fi
}
