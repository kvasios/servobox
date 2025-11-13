#!/usr/bin/env bash
# Recipe execution functions for ServoBox

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# List available recipes
list_available_recipes() {
  local recipes_dir="${REPO_ROOT}/packages/recipes"
  
  for recipe_dir in "${recipes_dir}"/*; do
    if [[ -d "$recipe_dir" ]]; then
      local recipe_name=$(basename "$recipe_dir")
      echo "  - ${recipe_name}"
    fi
  done
}

# List recipes that have run.sh scripts
list_recipes_with_run() {
  local recipes_dir="${REPO_ROOT}/packages/recipes"
  local found=false
  
  for recipe_dir in "${recipes_dir}"/*; do
    if [[ -d "$recipe_dir" ]]; then
      local recipe_name=$(basename "$recipe_dir")
      if [[ -f "${recipe_dir}/run.sh" ]]; then
        echo "  - ${recipe_name}"
        found=true
      fi
    fi
  done
  
  if [[ "$found" != "true" ]]; then
    echo "  (No recipes with run.sh found)"
  fi
}

# Ensure VM is running and SSH is ready
ensure_vm_running() {
  # Check if VM domain exists
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: VM '${NAME}' does not exist." >&2
    echo "Use 'servobox init --name ${NAME}' to create the VM first." >&2
    exit 1
  fi
  
  # Check VM state directly
  local vm_state
  vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
  
  case "${vm_state}" in
    "shut off")
      echo "VM '${NAME}' is not running. Starting it now..." >&2
      echo "" >&2
      
      # Start the VM using the cmd_start function (NAME is already set globally)
      if cmd_start; then
        echo "" >&2
        echo "✓ VM '${NAME}' started successfully" >&2
        echo "" >&2
      else
        echo "Error: Failed to start VM '${NAME}'" >&2
        exit 1
      fi
      ;;
    "paused")
      echo "Error: VM '${NAME}' is paused." >&2
      echo "Use 'virsh -c qemu:///system resume ${NAME}' to resume the VM." >&2
      exit 1
      ;;
    "in shutdown")
      echo "VM '${NAME}' is currently shutting down." >&2
      echo "Waiting for shutdown to complete..." >&2
      
      # Wait for shutdown to complete (max 60 seconds)
      local shutdown_timeout=60
      local shutdown_attempts=0
      while [[ ${shutdown_attempts} -lt ${shutdown_timeout} ]]; do
        vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
        if [[ "${vm_state}" == "shut off" ]]; then
          echo "Shutdown complete. Starting VM now..." >&2
          echo "" >&2
          
          # Start the VM (NAME is already set globally)
          if cmd_start; then
            echo "" >&2
            echo "✓ VM '${NAME}' started successfully" >&2
            echo "" >&2
            break
          else
            echo "Error: Failed to start VM '${NAME}'" >&2
            exit 1
          fi
        fi
        ((shutdown_attempts++))
        sleep 1
      done
      
      if [[ ${shutdown_attempts} -ge ${shutdown_timeout} ]]; then
        echo "Error: VM shutdown timed out after ${shutdown_timeout} seconds" >&2
        exit 1
      fi
      ;;
    "running")
      # VM is running, continue
      ;;
    *)
      echo "Error: VM '${NAME}' is in unknown state: ${vm_state}" >&2
      echo "Use 'servobox status --name ${NAME}' for more information." >&2
      exit 1
      ;;
  esac
}

# Execute recipe run script in VM
exec_recipe_in_vm() {
  local recipe_name="$1"
  local run_script="$2"
  local vm_ip
  
  # Try to get VM IP with timeout
  echo "Getting VM IP address..."
  local ip_timeout=30
  local ip_attempts=0
  vm_ip=""
  
  while [[ ${ip_attempts} -lt ${ip_timeout} ]]; do
    vm_ip=$(vm_ip || true)
    if [[ -n "${vm_ip}" ]]; then
      break
    fi
    ((ip_attempts++))
    if [[ ${ip_attempts} -lt ${ip_timeout} ]]; then
      echo "Waiting for IP assignment... (${ip_attempts}/${ip_timeout})"
      sleep 2
    fi
  done
  
  if [[ -z "${vm_ip}" ]]; then
    echo "Error: VM '${NAME}' is running but has no IP address assigned." >&2
    echo "This may indicate:" >&2
    echo "  • Network configuration issues" >&2
    echo "  • Cloud-init is still running" >&2
    echo "  • VM is in an intermediate boot state" >&2
    echo "" >&2
    echo "Try:" >&2
    echo "  • servobox status --name ${NAME}  # Check detailed status" >&2
    echo "  • virsh console ${NAME}          # Check VM console" >&2
    echo "  • Wait a few minutes and try again" >&2
    exit 1
  fi
  
  echo "Connecting to VM at ${vm_ip} to run recipe '${recipe_name}'..."
  echo ""
  
  # Copy the run script to VM and execute it
  local script_content
  script_content=$(cat "$run_script")
  
  # Execute the script in the VM with proper environment
  ssh -t "servobox-usr@${vm_ip}" "bash -l -c '
    echo \"=== Starting recipe ${recipe_name} ===\"
    echo \"Working directory: \$(pwd)\"
    echo \"User: \$(whoami)\"
    echo \"Date: \$(date)\"
    echo \"\"
    
    # Create a temporary script file
    cat > /tmp/recipe_run.sh << \"EOF\"
${script_content}
EOF
    
    # Make it executable and run it
    chmod +x /tmp/recipe_run.sh
    echo \"Executing recipe run script...\"
    echo \"\"
    
    # Execute with proper error handling
    if /tmp/recipe_run.sh; then
      echo \"\"
      echo \"=== Recipe ${recipe_name} completed successfully ===\"
    else
      echo \"\"
      echo \"=== Recipe ${recipe_name} failed with exit code \$? ===\"
      echo \"Check the output above for error details.\"
      echo \"Common issues:\"
      echo \"  - Hardware not connected or powered on\"
      echo \"  - Network connectivity issues\"
      echo \"  - Missing dependencies\"
      echo \"  - Permission issues\"
      echo \"\"
      echo \"You can fix the issue and run: servobox run ${recipe_name}\"
    fi
    
    echo \"\"
    echo \"Press Enter to exit or Ctrl+C to terminate...\"
    read
  '"
}

# Execute arbitrary command in VM
exec_command_in_vm() {
  local command="$1"
  local vm_ip
  
  # Try to get VM IP with timeout
  local ip_timeout=30
  local ip_attempts=0
  vm_ip=""
  
  while [[ ${ip_attempts} -lt ${ip_timeout} ]]; do
    vm_ip=$(vm_ip || true)
    if [[ -n "${vm_ip}" ]]; then
      break
    fi
    ((ip_attempts++))
    if [[ ${ip_attempts} -lt ${ip_timeout} ]]; then
      sleep 2
    fi
  done
  
  if [[ -z "${vm_ip}" ]]; then
    echo "Error: VM '${NAME}' is running but has no IP address assigned." >&2
    echo "This may indicate:" >&2
    echo "  • Network configuration issues" >&2
    echo "  • Cloud-init is still running" >&2
    echo "  • VM is in an intermediate boot state" >&2
    echo "" >&2
    echo "Try:" >&2
    echo "  • servobox status --name ${NAME}  # Check detailed status" >&2
    echo "  • virsh console ${NAME}          # Check VM console" >&2
    echo "  • Wait a few minutes and try again" >&2
    exit 1
  fi
  
  # Execute the command directly via SSH (no verbose output)
  ssh "servobox-usr@${vm_ip}" "bash -l -c '${command}'"
}

# Main recipe run command
cmd_recipe_run() {
  # Custom arg parsing for recipe run (avoid global parse_args which treats
  # positional recipe names as unknown args)
  local recipe_name=""
  local recipe_dir=""
  local run_script=""
  local is_command=false
  
  # Parse arguments manually to extract recipe name and options
  shift || true  # Remove command name
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) NAME="$2"; shift 2;;
      --debug) DEBUG=1; shift 1;;
      --force) FORCE=1; shift 1;;
      *)
        # First non-option argument could be a recipe name or a command
        if [[ -z "$recipe_name" ]]; then
          recipe_name="$1"
          # Check if it's a command (contains spaces - recipes don't have spaces)
          if [[ "$recipe_name" =~ [[:space:]] ]]; then
            is_command=true
          fi
          shift
        else
          echo "Unknown arg: $1" >&2
          usage
          exit 1
        fi
        ;;
    esac
  done
  
  # Check if recipe name/command was provided
  if [[ -z "$recipe_name" ]]; then
    echo "Error: Please provide a valid recipe name or command." >&2
    echo "" >&2
    echo "Usage: servobox run <recipe-name> [options]" >&2
    echo "       servobox run \"<command>\" [options]" >&2
    echo "" >&2
    echo "Available recipes with run.sh:" >&2
    list_recipes_with_run
    echo "" >&2
    echo "Note: The 'run' command is only valid for packages that are already installed in the VM." >&2
    echo "Use 'servobox pkg-install <recipe-name>' to install packages first." >&2
    exit 1
  fi
  
  # Ensure VM is running
  ensure_vm_running
  
  if [[ "$is_command" == "true" ]]; then
    # Execute arbitrary command
    exec_command_in_vm "$recipe_name"
  else
    # Execute recipe
    # Find recipe directory
    recipe_dir="${REPO_ROOT}/packages/recipes/${recipe_name}"
    if [[ ! -d "$recipe_dir" ]]; then
      echo "Error: Recipe '${recipe_name}' not found in ${REPO_ROOT}/packages/recipes/" >&2
      echo "Available recipes:" >&2
      list_available_recipes
      exit 1
    fi
    
    # Check if run.sh exists
    run_script="${recipe_dir}/run.sh"
    if [[ ! -f "$run_script" ]]; then
      echo "Error: Recipe '${recipe_name}' does not have a run.sh script." >&2
      echo "Run scripts are optional and used to launch services/processes for the recipe." >&2
      echo "Available recipes with run.sh:" >&2
      list_recipes_with_run
      exit 1
    fi
    
    echo "Running recipe '${recipe_name}' in VM '${NAME}'..."
    echo "Recipe run script: ${run_script}"
    echo ""
    echo "Note: This will keep the terminal open in the VM for monitoring."
    echo "Press Ctrl+C to stop the recipe execution."
    echo ""
    
    # Execute the run script in the VM
    exec_recipe_in_vm "$recipe_name" "$run_script"
  fi
}
