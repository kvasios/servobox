#!/usr/bin/env bash
# VM lifecycle management functions

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Ensure libvirt's 'default' network is active (required for NAT networking)
ensure_default_network() {
  # Check if we're using a custom bridge (skip default network check)
  if [[ -n "${BRIDGE}" ]]; then
    return 0
  fi
  
  # Check if default network exists
  if ! virsh_cmd net-info default >/dev/null 2>&1; then
    echo "Warning: libvirt 'default' network not found." >&2
    echo "ServoBox requires libvirt's default NAT network for VM connectivity." >&2
    echo "This is usually created automatically by libvirt-daemon-system." >&2
    echo "" >&2
    echo "Attempting to create it now..." >&2
    
    # Define the default network
    if virsh_cmd net-define /usr/share/libvirt/networks/default.xml >/dev/null 2>&1; then
      echo "✓ Created default network" >&2
    else
      echo "Error: Failed to create default network." >&2
      echo "Please run: sudo virsh net-define /usr/share/libvirt/networks/default.xml" >&2
      exit 1
    fi
  fi
  
  # Check if default network is active
  if ! virsh_cmd net-info default 2>/dev/null | grep -q "Active:.*yes"; then
    echo "Starting libvirt 'default' network..." >&2
    if ! virsh_cmd net-start default >/dev/null 2>&1; then
      echo "Error: Failed to start libvirt 'default' network." >&2
      echo "Please run: sudo virsh net-start default" >&2
      exit 1
    fi
    echo "✓ Started default network" >&2
  fi
  
  # Ensure it's set to autostart
  if ! virsh_cmd net-info default 2>/dev/null | grep -q "Autostart:.*yes"; then
    echo "Enabling autostart for libvirt 'default' network..." >&2
    if ! virsh_cmd net-autostart default >/dev/null 2>&1; then
      echo "Warning: Failed to set autostart for default network" >&2
    else
      echo "✓ Enabled autostart for default network" >&2
    fi
  fi
}

# Add DHCP reservation for VM's MAC address to ensure consistent IP assignment
ensure_dhcp_reservation() {
  # Skip if using custom bridge
  if [[ -n "${BRIDGE}" ]]; then
    return 0
  fi
  
  local target_mac="${MAC_ADDR}"
  local effective_cidr="${STATIC_IP_CIDR:-${DEFAULT_NAT_STATIC}}"
  local vm_ip="${effective_cidr%/*}"
  local vm_name="${NAME}"
  
  # Check if reservation already exists for this MAC address
  local existing_reservation
  existing_reservation=$(virsh_cmd net-dumpxml default 2>/dev/null | grep -i "mac='${target_mac}'" || true)
  
  if [[ -n "${existing_reservation}" ]]; then
    # Check if the existing reservation has the correct IP
    if echo "${existing_reservation}" | grep -q "ip='${vm_ip}'"; then
      echo "DHCP reservation already exists for ${target_mac} → ${vm_ip}"
      return 0
    else
      # Remove old reservation with different IP
      echo "Updating DHCP reservation for ${target_mac}..."
      virsh_cmd net-update default delete ip-dhcp-host "<host mac='${target_mac}'/>" --live --config 2>/dev/null || true
    fi
  fi
  
  # Add DHCP reservation
  echo "Adding DHCP reservation: ${target_mac} → ${vm_ip}"
  local host_xml="<host mac='${target_mac}' name='${vm_name}' ip='${vm_ip}'/>"
  
  if virsh_cmd net-update default add ip-dhcp-host "${host_xml}" --live --config 2>/dev/null; then
    echo "✓ DHCP reservation added for ${vm_name} (${vm_ip})"
    return 0
  else
    # Try with sudo if non-sudo failed
    if sudo virsh net-update default add ip-dhcp-host "${host_xml}" --live --config 2>/dev/null; then
      echo "✓ DHCP reservation added for ${vm_name} (${vm_ip})"
      return 0
    else
      echo "Warning: Could not add DHCP reservation. The VM may get a random IP from DHCP pool." >&2
      echo "Falling back to in-guest static IP configuration via netplan." >&2
      return 1
    fi
  fi
}

virt_install() {
  echo "Creating libvirt domain ${NAME}..."
  if virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    # Check if domain is already running
    if virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi running; then
      echo "Domain ${NAME} is already running."
      return
    else
      echo "Domain already exists; starting..."
      if ! virsh_cmd start "${NAME}"; then
        echo "Error: Failed to start existing VM domain" >&2
        exit 1
      fi
      return
    fi
  fi

  NETOPTS=("--network network=default,mac=${MAC_ADDR}")
  if [[ -n "${BRIDGE}" ]]; then
    NETOPTS=("--network bridge=${BRIDGE},mac=${MAC_ADDR}")
  fi

  # Optional: add direct/macvtap NICs bound to host devices (up to 2)
  if [[ ${#HOST_NICS[@]} -ge 1 ]]; then
    if [[ -z "${MAC_ADDR2}" ]]; then
      MAC_ADDR2="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
    fi
    NETOPTS+=("--network type=direct,source=${HOST_NICS[0]},source_mode=bridge,model=e1000e,mac=${MAC_ADDR2}")
    echo "Attaching direct NIC #1 via macvtap on host ${HOST_NICS[0]} (mac ${MAC_ADDR2})"
  fi
  
  if [[ ${#HOST_NICS[@]} -ge 2 ]]; then
    if [[ -z "${MAC_ADDR3}" ]]; then
      MAC_ADDR3="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
    fi
    NETOPTS+=("--network type=direct,source=${HOST_NICS[1]},source_mode=bridge,model=e1000e,mac=${MAC_ADDR3}")
    echo "Attaching direct NIC #2 via macvtap on host ${HOST_NICS[1]} (mac ${MAC_ADDR3})"
  fi

  # Use fixed OS info matching our shipped image; allow top-level override if exported
  OSINFO_OPT_VAL="${OSINFO_OPT:-ubuntu22.04}"
  OSINFO_OPT="--osinfo ${OSINFO_OPT_VAL}"

  if [[ "${DEBUG}" -eq 1 ]]; then set -x; fi
  # Test if we can use virt-install without sudo
  if virsh -c qemu:///system version >/dev/null 2>&1; then
    virt-install \
      --connect qemu:///system \
      --name "${NAME}" \
      --memory "${MEMORY}" --vcpus "${VCPUS}" \
      --cpu host-passthrough,cache.mode=passthrough \
      ${OSINFO_OPT} \
      --disk "path=${DISK_QCOW},format=qcow2,cache=none,discard=unmap" \
      --disk "path=${SEED_ISO},device=cdrom" \
      ${NETOPTS[@]} \
      --graphics none \
      --import \
      --noautoconsole
  else
    sudo virt-install \
      --connect qemu:///system \
      --name "${NAME}" \
      --memory "${MEMORY}" --vcpus "${VCPUS}" \
      --cpu host-passthrough,cache.mode=passthrough \
      ${OSINFO_OPT} \
      --disk "path=${DISK_QCOW},format=qcow2,cache=none,discard=unmap" \
      --disk "path=${SEED_ISO},device=cdrom" \
      ${NETOPTS[@]} \
      --graphics none \
      --import \
      --noautoconsole
  fi
  if [[ "${DEBUG}" -eq 1 ]]; then set +x; fi
}

# Define (but do not start) the libvirt domain using virt-install generated XML
virt_define() {
  echo "Defining libvirt domain ${NAME} (no boot)..."
  if virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Domain ${NAME} already defined."
    return
  fi

  NETOPTS=("--network network=default,mac=${MAC_ADDR}")
  if [[ -n "${BRIDGE}" ]]; then
    NETOPTS=("--network bridge=${BRIDGE},mac=${MAC_ADDR}")
  fi

  # Optional: add direct/macvtap NICs bound to host devices (up to 2)
  if [[ ${#HOST_NICS[@]} -ge 1 ]]; then
    if [[ -z "${MAC_ADDR2}" ]]; then
      MAC_ADDR2="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
    fi
    NETOPTS+=("--network type=direct,source=${HOST_NICS[0]},source_mode=bridge,model=e1000e,mac=${MAC_ADDR2}")
    echo "Attaching direct NIC #1 via macvtap on host ${HOST_NICS[0]} (mac ${MAC_ADDR2})"
  fi
  
  if [[ ${#HOST_NICS[@]} -ge 2 ]]; then
    if [[ -z "${MAC_ADDR3}" ]]; then
      MAC_ADDR3="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
    fi
    NETOPTS+=("--network type=direct,source=${HOST_NICS[1]},source_mode=bridge,model=e1000e,mac=${MAC_ADDR3}")
    echo "Attaching direct NIC #2 via macvtap on host ${HOST_NICS[1]} (mac ${MAC_ADDR3})"
  fi

  OSINFO_OPT_VAL="${OSINFO_OPT:-ubuntu22.04}"
  OSINFO_OPT="--osinfo ${OSINFO_OPT_VAL}"

  if [[ "${DEBUG}" -eq 1 ]]; then set -x; fi
  # Test if we can use virsh without sudo
  if virsh -c qemu:///system version >/dev/null 2>&1; then
    if ! virt-install \
        --connect qemu:///system \
        --name "${NAME}" \
        --memory "${MEMORY}" --vcpus "${VCPUS}" \
        --cpu host-passthrough,cache.mode=passthrough \
        ${OSINFO_OPT} \
        --disk "path=${DISK_QCOW},format=qcow2,cache=none,discard=unmap" \
        --disk "path=${SEED_ISO},device=cdrom" \
        ${NETOPTS[@]} \
        --graphics none \
        --import \
        --noautoconsole \
        --print-xml --dry-run | virsh -c qemu:///system define /dev/stdin; then
      echo "Error: failed to define domain ${NAME}" >&2
      exit 1
    fi
  else
    if ! sudo virt-install \
        --connect qemu:///system \
        --name "${NAME}" \
        --memory "${MEMORY}" --vcpus "${VCPUS}" \
        --cpu host-passthrough,cache.mode=passthrough \
        ${OSINFO_OPT} \
        --disk "path=${DISK_QCOW},format=qcow2,cache=none,discard=unmap" \
        --disk "path=${SEED_ISO},device=cdrom" \
        ${NETOPTS[@]} \
        --graphics none \
        --import \
        --noautoconsole \
        --print-xml --dry-run | sudo virsh -c qemu:///system define /dev/stdin; then
      echo "Error: failed to define domain ${NAME}" >&2
      exit 1
    fi
  fi
  if [[ "${DEBUG}" -eq 1 ]]; then set +x; fi
  
  # Apply RT optimizations to the XML (CPU pinning, IOThreads, memory locking, etc.)
  apply_rt_xml_config
}

cmd_init() {
  parse_args "$@"
  deps
  
  # Check if user is in required groups for libvirt access
  local user_groups
  user_groups=$(groups 2>/dev/null || echo "")
  local needs_relogin=0
  
  if ! echo "$user_groups" | grep -qw libvirt; then
    echo "⚠️  Warning: Current user is not in the 'libvirt' group"
    echo ""
    echo "Adding user to libvirt group for persistent VM access..."
    if sudo usermod -aG libvirt "$USER" 2>/dev/null; then
      echo "✓ Added $USER to libvirt group"
      needs_relogin=1
    else
      echo "Error: Failed to add user to libvirt group" >&2
      echo "Please run: sudo usermod -aG libvirt $USER" >&2
    fi
  fi
  
  if ! echo "$user_groups" | grep -qw kvm; then
    if ! groups "$USER" 2>/dev/null | grep -qw kvm; then
      echo "Adding user to kvm group for VM hardware access..."
      if sudo usermod -aG kvm "$USER" 2>/dev/null; then
        echo "✓ Added $USER to kvm group"
        needs_relogin=1
      else
        echo "Warning: Could not add user to kvm group (may already be in group)" >&2
      fi
    fi
  fi
  
  if [[ $needs_relogin -eq 1 ]]; then
    echo ""
    echo "⚠️  IMPORTANT: Group membership changes are not active in current shell"
    echo ""
    echo "ServoBox init will continue using sudo for this session."
    echo ""
    echo "To use 'servobox start' and other commands without sudo prompts,"
    echo "activate the new group membership:"
    echo ""
    echo "  Option 1 (Quick): Run this command in your current terminal:"
    echo "    exec sg libvirt newgrp"
    echo ""
    echo "  Option 2 (Permanent): Log out and log back in"
    echo ""
    echo "  Option 3: Reboot your system"
    echo ""
    echo "Without activating group membership, you'll need sudo for VM operations."
    echo ""
  fi
  
  # Ensure libvirtd is enabled to start on boot (for VM persistence after reboot)
  if ! systemctl is-enabled libvirtd >/dev/null 2>&1 && ! systemctl is-enabled libvirtd.service >/dev/null 2>&1; then
    echo "Enabling libvirtd to start on boot (for VM persistence)..."
    if sudo systemctl enable libvirtd >/dev/null 2>&1 || sudo systemctl enable libvirtd.service >/dev/null 2>&1; then
      echo "✓ libvirtd will start automatically on boot"
    else
      echo "Warning: Could not enable libvirtd autostart" >&2
      echo "Your VMs may not be available after reboot" >&2
      echo "Please run: sudo systemctl enable libvirtd" >&2
    fi
  fi
  
  # Ensure libvirtd is currently running
  if ! systemctl is-active libvirtd >/dev/null 2>&1 && ! systemctl is-active libvirtd.service >/dev/null 2>&1; then
    echo "Starting libvirtd service..."
    if sudo systemctl start libvirtd >/dev/null 2>&1 || sudo systemctl start libvirtd.service >/dev/null 2>&1; then
      echo "✓ libvirtd started"
      # Give it a moment to fully initialize
      sleep 1
    else
      echo "Error: Could not start libvirtd" >&2
      echo "Please run: sudo systemctl start libvirtd" >&2
      exit 1
    fi
  fi
  
  # Ensure libvirt's default network is available (unless using custom bridge)
  ensure_default_network
  
  # Interactive NIC chooser if --choose-nic flag was provided
  if [[ ${ASK_NIC} -eq 1 ]]; then
    if ! choose_host_nic; then
      echo "Warning: Failed to choose host NIC interactively" >&2
    fi
  fi
  
  # Validate chosen NICs
  for nic in "${HOST_NICS[@]}"; do
    if ! ip link show "${nic}" >/dev/null 2>&1; then
      echo "Error: host NIC '${nic}' not found" >&2
      exit 1
    fi
    if echo "${nic}" | grep -Eq '^(lo|virbr|vnet|veth|br|docker|tap|tun|macvtap)'; then
      echo "Warning: '${nic}' appears to be a virtual/bridge device; direct attach may fail or not be useful." >&2
    fi
  done

  if virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Domain ${NAME} already defined. You can run: servobox start --name ${NAME}"
    exit 0
  fi
  
  # Add DHCP reservation to ensure consistent IP assignment across reboots
  ensure_dhcp_reservation

  ensure_image
  make_vm_storage
  # Ensure minimal images are ready for console/SSH logins and guest agent
  ensure_guest_basics
  inject_ssh_key
  # Configure RT kernel parameters automatically for optimal real-time performance
  inject_rt_kernel_params
  # Set static IP on the primary NAT NIC (default or --ip override)
  inject_primary_static_netplan
  # Ensure the guest will have persistent static IP on the direct/macvtap NIC
  inject_persistent_netplan
  gen_cloud_init
  virt_define
  echo ""
  echo "✓ VM ${NAME} initialized successfully with full RT optimization!"
  echo ""
  echo "RT Configuration applied:"
  echo "  • Guest kernel: CPU isolation, nohz_full, rcu_nocbs"
  echo "  • XML: CPU pinning, IOThreads, memory locking, clock tuning"
  echo "  • Ready for: sub-microsecond latency real-time workloads"
  echo ""
  echo "Next steps:"
  echo "  1. servobox start --name ${NAME}"
  echo "  2. servobox test --name ${NAME} --duration 30 --stress-ng"
  echo ""
  echo "The test will measure RT latency while optionally stressing the host system."
}

cmd_start() {
  parse_args "$@"
  
  # Ensure libvirtd is running (in case it wasn't started after reboot)
  if ! systemctl is-active libvirtd >/dev/null 2>&1 && ! systemctl is-active libvirtd.service >/dev/null 2>&1; then
    echo "libvirtd is not running. Starting it now..."
    if sudo systemctl start libvirtd >/dev/null 2>&1 || sudo systemctl start libvirtd.service >/dev/null 2>&1; then
      echo "✓ libvirtd started"
      sleep 1
    else
      echo "Error: Could not start libvirtd" >&2
      echo "Please run: sudo systemctl start libvirtd" >&2
      exit 1
    fi
  fi
  
  # Only start an already-defined domain
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: VM ${NAME} is not defined. Run 'servobox init --name ${NAME}' first." >&2
    
    # If we just started libvirtd, suggest waiting a moment
    if ! systemctl is-active libvirtd >/dev/null 2>&1; then
      echo "" >&2
      echo "Note: If you recently created this VM, you may need to:" >&2
      echo "  1. Ensure you're in the 'libvirt' group: groups | grep libvirt" >&2
      echo "  2. If not, log out and log back in to activate group membership" >&2
    fi
    exit 1
  fi
  
  # Ensure libvirt's default network is available before starting
  ensure_default_network
  
  # Extract MAC address from the VM definition for DHCP reservation
  local vm_mac
  vm_mac=$(virsh_cmd domiflist "${NAME}" 2>/dev/null | awk '$3 == "default" || $3 ~ /^virbr/ {print $5; exit}')
  if [[ -n "${vm_mac}" ]]; then
    MAC_ADDR="${vm_mac}"
    # Ensure DHCP reservation exists for this VM (idempotent)
    ensure_dhcp_reservation
  fi
  
  # Require sudo credentials upfront for RT configuration
  echo "RT configuration requires elevated privileges..."
  if ! sudo -v; then
    echo "" >&2
    echo "Error: sudo access required for RT configuration" >&2
    echo "" >&2
    echo "ServoBox needs sudo to configure:" >&2
    echo "  • CPU pinning and affinity" >&2
    echo "  • Real-time thread priorities (SCHED_FIFO)" >&2
    echo "  • IRQ affinity (isolate interrupts to CPU 0)" >&2
    echo "  • CPU frequency governor (performance mode)" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Run: sudo $(basename "$0") start --name ${NAME}" >&2
    echo "  2. Configure NOPASSWD for RT commands (recommended for dev):" >&2
    echo "     sudo visudo -f /etc/sudoers.d/servobox-rt" >&2
    echo "     Add: %sudo ALL=(ALL) NOPASSWD: /usr/bin/chrt, /usr/bin/taskset, /usr/bin/tee" >&2
    exit 1
  fi
  
  local was_already_running=0
  if virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi running; then
    was_already_running=1
    IP=$(vm_ip || true)
    if [[ -n "${IP}" ]]; then
      echo "VM ${NAME} is already running at ${IP}"
      echo "Use 'servobox ssh' to connect or 'servobox stop' to shutdown."
      echo "SSH password: servobox-pwd (standard default)"
      echo ""
      echo "✓ VM ${NAME} is already running - no additional operations needed."
      return 0
    else
      echo "VM ${NAME} is already running."
      echo ""
      echo "✓ VM ${NAME} is already running - no additional operations needed."
      return 0
    fi
  fi
  
  # Check if VM has RT XML configuration before starting
  if [[ ${was_already_running} -eq 0 ]]; then
    echo "Checking RT XML configuration..."
    local xml_file=$(mktemp)
    virsh_cmd dumpxml "${NAME}" > "${xml_file}"
    
    if ! grep -q "<cputune>" "${xml_file}"; then
      echo "⚠️  RT XML optimizations not found in VM definition"
      echo "Applying RT XML configuration before starting..."
      
      # Get vCPU count from domain
      VCPUS=$(virsh_cmd dominfo "${NAME}" 2>/dev/null | grep "CPU(s):" | awk '{print $2}')
      
      # Apply RT XML config
      apply_rt_xml_config
      echo ""
    fi
    rm -f "${xml_file}"
    
    echo "Starting VM ${NAME}..."
    virsh_cmd start "${NAME}"
    echo "Waiting for IP..."
    for i in {1..60}; do
      IP=$(vm_ip || true)
      if [[ -n "${IP}" ]]; then
        echo "VM ${NAME} is up at ${IP}"
        break
      fi
      sleep 2
    done
    
    if [[ -z "${IP}" ]]; then
      echo "Booted, but no IP yet. Try: servobox ip --name ${NAME}"
      echo "Continuing with RT configuration..."
    fi
  fi
  
  # Automatically apply RT CPU pinning and isolation (runtime enhancement)
  echo ""
  echo "Applying runtime RT CPU pinning and isolation..."
  pin_vcpus
  
  echo ""
  echo "✓ VM ${NAME} is RT-ready!"
  if [[ -n "${IP}" ]]; then
    echo "  IP: ${IP}"
    wait_for_sshd "${IP}" 30 || true
  fi
  echo "  SSH password: servobox-pwd"
}

cmd_ip() {
  parse_args "$@"
  
  # Check if VM domain exists
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: VM '${NAME}' does not exist." >&2
    echo "Use 'servobox init --name ${NAME}' to create the VM first." >&2
    exit 1
  fi
  
  # Check VM state
  local vm_state
  vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
  
  case "${vm_state}" in
    "shut off")
      echo "Error: VM '${NAME}' is not running." >&2
      echo "Use 'servobox start --name ${NAME}' to boot the VM first." >&2
      exit 1
      ;;
    "paused")
      echo "Error: VM '${NAME}' is paused." >&2
      echo "Use 'virsh resume ${NAME}' to resume the VM." >&2
      exit 1
      ;;
    "in shutdown")
      echo "Error: VM '${NAME}' is currently shutting down." >&2
      echo "Please wait for shutdown to complete, then use 'servobox start --name ${NAME}' to boot the VM." >&2
      exit 1
      ;;
  esac
  
  # Get VM IP
  IP=$(vm_ip || true)
  if [[ -n "${IP}" ]]; then
    echo "${IP}"
  else
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
}

cmd_stop() { 
  parse_args "$@"
  
  # Ensure VM exists
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: VM '${NAME}' does not exist." >&2
    exit 1
  fi
  
  # Determine current state
  local vm_state
  vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
  
  case "${vm_state}" in
    "shut off")
      echo "VM '${NAME}' is already shut down."
      exit 0
      ;;
    "paused")
      echo "VM '${NAME}' is paused. Attempting resume before shutdown..."
      if ! virsh_cmd resume "${NAME}" >/dev/null 2>&1; then
        echo "Warning: Failed to resume VM before shutdown" >&2
      fi
      ;;
    "running")
      echo "Shutting down VM '${NAME}'..."
      ;;
    "in shutdown")
      echo "VM '${NAME}' is already shutting down..."
      ;;
    *)
      echo "Warning: VM '${NAME}' is in unexpected state '${vm_state}'. Proceeding with shutdown signal." >&2
      ;;
  esac
  
  # Initiate shutdown (idempotent)
  if ! virsh_cmd shutdown "${NAME}" >/dev/null 2>&1; then
    echo "Warning: Failed to initiate VM shutdown" >&2
  fi
  
  # Wait for shutdown to complete (configurable timeout)
  local timeout_seconds="${SHUTDOWN_TIMEOUT:-60}"
  local check_interval=2
  local elapsed=0
  echo "Waiting for shutdown to complete... (timeout: ${timeout_seconds}s)"
  
  while [[ ${elapsed} -lt ${timeout_seconds} ]]; do
    vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
    case "${vm_state}" in
      "shut off")
        echo "VM '${NAME}' has been shut down successfully."
        exit 0
        ;;
      "in shutdown")
        # Show progress every 10 seconds
        if [[ $((elapsed % 10)) -eq 0 && ${elapsed} -gt 0 ]]; then
          echo "Still shutting down... (${elapsed}/${timeout_seconds}s)"
        fi
        ;;
      "paused"|"running")
        # Re-issue a gentle shutdown periodically if still running/paused
        if [[ $((elapsed % 10)) -eq 0 ]]; then
          virsh_cmd shutdown "${NAME}" >/dev/null 2>&1 || true
        fi
        ;;
      *)
        echo "Warning: VM '${NAME}' entered state '${vm_state}' while waiting for shutdown" >&2
        ;;
    esac
    sleep ${check_interval}
    elapsed=$((elapsed + check_interval))
  done
  
  echo "Error: VM '${NAME}' did not shut down within ${timeout_seconds} seconds." >&2
  echo "Current state: $(virsh_cmd domstate "${NAME}" 2>/dev/null || echo 'unknown')" >&2
  echo "" >&2
  echo "You can try:" >&2
  echo "  • virsh destroy ${NAME}  # Force power off" >&2
  echo "  • virsh console ${NAME}  # Check guest console" >&2
  echo "  • servobox status --name ${NAME}  # Detailed status" >&2
  exit 1
}

cmd_destroy() {
  parse_args "$@"
  
  # Check if VM exists
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: VM '${NAME}' does not exist." >&2
    exit 1
  fi
  
  # Prompt for confirmation unless --force is used
  if [[ ${FORCE} -ne 1 ]]; then
    echo "⚠️  WARNING: This will permanently delete VM '${NAME}' and ALL data inside it!"
    echo ""
    echo "This includes:"
    echo "  • VM disk and all files: ${VM_DIR}"
    echo "  • Installed packages and configurations"
    echo "  • Any data you created inside the VM"
    echo ""
    echo "This action CANNOT be undone."
    echo ""
    printf "Type 'yes' to confirm destruction of VM '${NAME}': "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
      echo "Destruction cancelled."
      exit 0
    fi
    echo ""
  fi
  
  echo "Destroying VM '${NAME}'..."
  
  # Destroy only if running
  if virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi running; then
    echo "Stopping running VM..."
    if ! virsh_cmd destroy "${NAME}" >/dev/null 2>&1; then
      echo "Warning: Failed to destroy running VM" >&2
    fi
  fi
  
  # Undefine the domain
  if ! virsh_cmd undefine "${NAME}" --remove-all-storage >/dev/null 2>&1; then
    echo "Error: Failed to undefine VM domain" >&2
    exit 1
  fi
  
  # Remove VM directory
  if [[ -d "${VM_DIR}" ]]; then
    if ! rm -rf "${VM_DIR}" 2>/dev/null; then
      if ! sudo rm -rf "${VM_DIR}" >/dev/null 2>&1; then
        echo "Error: Failed to remove VM directory ${VM_DIR}" >&2
        exit 1
      fi
    fi
  fi
  
  # Clean up package tracking file
  local tracking_file="${HOME}/.local/share/servobox/tracking/${NAME}.servobox-packages"
  if [[ -f "${tracking_file}" ]]; then
    if rm -f "${tracking_file}" 2>/dev/null; then
      echo "✓ Removed package tracking file"
    else
      echo "Warning: Could not remove package tracking file: ${tracking_file}" >&2
    fi
  fi
  
  echo "✓ VM '${NAME}' has been destroyed."
}
cmd_status() {
  parse_args "$@"
  
  echo "=== ServoBox VM Status ==="
  echo "VM Name: ${NAME}"
  echo "VM Directory: ${VM_DIR}"
  
  # Check if domain exists
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Status: VM does not exist"
    echo "Use 'servobox init' to create the VM, then 'servobox start' to boot."
    exit 0
  fi
  
  # Get VM state
  VM_STATE=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
  echo "Status: ${VM_STATE}"
  
  # Get VM configuration
  echo -e "\n=== VM Configuration ==="
  if virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    VCPUS_CONFIG=$(virsh_cmd dominfo "${NAME}" 2>/dev/null | grep "CPU(s):" | awk '{print $2}' || echo "unknown")
    MEMORY_CONFIG=$(virsh_cmd dominfo "${NAME}" 2>/dev/null | grep "Max memory:" | awk '{print $3, $4}' || echo "unknown")
    echo "vCPUs: ${VCPUS_CONFIG}"
    echo "Memory: ${MEMORY_CONFIG}"
  fi
  
  # Get network information
  echo -e "\n=== Network ==="
  IP=$(vm_ip || true)
  if [[ -n "${IP}" ]]; then
    echo "IP Address: ${IP}"
    echo "MAC Address: ${MAC_ADDR}"
    if [[ -n "${MAC_ADDR2}" ]]; then
      echo "MAC Address (Direct): ${MAC_ADDR2}"
    fi
    
    # Test SSH connectivity
    if timeout 2 bash -c "</dev/tcp/${IP}/22" 2>/dev/null; then
      echo "SSH: Available (port 22)"
    else
      echo "SSH: Not responding"
    fi
    
    # Show network validation if there are connectivity issues
    if ! timeout 2 bash -c "</dev/tcp/${IP}/22" 2>/dev/null; then
      echo -e "\n=== Network Troubleshooting ==="
      echo "SSH is not responding. Try:"
      echo "1. Wait a few more minutes for cloud-init to complete"
      echo "2. Check VM console: virsh console ${NAME}"
      echo "3. Check VM logs: servobox debug --name ${NAME}"
    fi
  else
    echo "IP Address: Not assigned yet"
    echo "MAC Address: ${MAC_ADDR}"
    if [[ -n "${MAC_ADDR2}" ]]; then
      echo "MAC Address (Direct): ${MAC_ADDR2}"
    fi
  fi
  
  # Get storage information
  echo -e "\n=== Storage ==="
  if [[ -f "${DISK_QCOW}" ]]; then
    DISK_SIZE=$(qemu-img info "${DISK_QCOW}" 2>/dev/null | grep "virtual size" | awk '{print $3, $4}' || echo "unknown")
    DISK_FORMAT=$(qemu-img info "${DISK_QCOW}" 2>/dev/null | grep "file format" | awk '{print $3}' || echo "unknown")
    echo "Disk: ${DISK_QCOW}"
    echo "Size: ${DISK_SIZE}"
    echo "Format: ${DISK_FORMAT}"
  else
    echo "Disk: Not found"
  fi
  
  if [[ -f "${SEED_ISO}" ]]; then
    SEED_SIZE=$(ls -lh "${SEED_ISO}" 2>/dev/null | awk '{print $5}' || echo "unknown")
    echo "Cloud-init seed: ${SEED_ISO} (${SEED_SIZE})"
  else
    echo "Cloud-init seed: Not found"
  fi
  
  # Get QEMU process information (only if VM is running)
  if [[ "${VM_STATE}" == "running" ]]; then
    echo -e "\n=== Process Information ==="
    QEMU_PID=$(pgrep -f "qemu.*${NAME}" | head -1)
    if [[ -n "${QEMU_PID}" ]]; then
      echo "QEMU PID: ${QEMU_PID}"
      QEMU_CPU=$(ps -o pcpu= -p "${QEMU_PID}" 2>/dev/null | tr -d ' ' || echo "unknown")
      QEMU_MEM=$(ps -o pmem= -p "${QEMU_PID}" 2>/dev/null | tr -d ' ' || echo "unknown")
      echo "QEMU CPU usage: ${QEMU_CPU}%"
      echo "QEMU Memory usage: ${QEMU_MEM}%"
    else
      echo "Warning: VM is running but QEMU process not found"
    fi
  fi
  
  # Get password information
  echo -e "\n=== Access Information ==="
  echo "SSH Password: servobox-pwd (standard default)"
  
  # Show available commands
  echo -e "\n=== Available Commands ==="
  if [[ "${VM_STATE}" == "running" ]]; then
    echo "• servobox ssh     - Connect to the VM"
    echo "• servobox stop    - Shutdown the VM"
    echo "• servobox test    - Run latency test"
    echo "• servobox rt-check - Check RT configuration"
  elif [[ "${VM_STATE}" == "shut off" ]]; then
    echo "• servobox start   - Boot the VM (RT configuration applied automatically)"
    echo "• servobox destroy - Remove the VM completely"
  else
    echo "• servobox init    - Create the VM (RT configuration included)"
    echo "• servobox start   - Boot the VM (RT CPU pinning applied automatically)"
    echo "• servobox destroy - Remove the VM completely"
  fi
}

cmd_ssh() {
  parse_args "$@"
  
  # Check if VM domain exists
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: VM '${NAME}' does not exist." >&2
    echo "Use 'servobox init --name ${NAME}' to create the VM first." >&2
    exit 1
  fi
  
  # Check VM state
  local vm_state
  vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
  
  case "${vm_state}" in
    "shut off")
      echo "Error: VM '${NAME}' is not running." >&2
      echo "Use 'servobox start --name ${NAME}' to boot the VM first." >&2
      exit 1
      ;;
    "paused")
      echo "Error: VM '${NAME}' is paused." >&2
      echo "Use 'virsh resume ${NAME}' to resume the VM, or 'servobox stop --name ${NAME}' and 'servobox start --name ${NAME}' to restart." >&2
      exit 1
      ;;
    "in shutdown")
      echo "Error: VM '${NAME}' is currently shutting down." >&2
      echo "Please wait for shutdown to complete, then use 'servobox start --name ${NAME}' to boot the VM." >&2
      exit 1
      ;;
    "unknown")
      echo "Error: Unable to determine VM '${NAME}' state." >&2
      echo "Try 'servobox status --name ${NAME}' for more information." >&2
      exit 1
      ;;
  esac
  
  # Get VM IP with timeout
  echo "Getting VM IP address..."
  local ip_timeout=10
  local ip_attempts=0
  local IP=""
  
  while [[ ${ip_attempts} -lt ${ip_timeout} ]]; do
    IP=$(vm_ip || true)
    if [[ -n "${IP}" ]]; then
      break
    fi
    ((ip_attempts++))
    if [[ ${ip_attempts} -lt ${ip_timeout} ]]; then
      echo "Waiting for IP assignment... (${ip_attempts}/${ip_timeout})"
      sleep 1
    fi
  done
  
  if [[ -z "${IP}" ]]; then
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
  
  echo "VM IP: ${IP}"
  
  # Re-check VM state after getting IP (VM might have transitioned states)
  vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
  if [[ "${vm_state}" == "in shutdown" ]]; then
    echo "Error: VM '${NAME}' is currently shutting down." >&2
    echo "Please wait for shutdown to complete, then use 'servobox start --name ${NAME}' to boot the VM." >&2
    exit 1
  fi
  
  # Wait for SSH with timeout (shorter timeout for better responsiveness)
  echo "Checking SSH connectivity..."
  if ! wait_for_sshd "${IP}" 15; then
    # Check VM state again in case it changed during SSH wait
    vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
    if [[ "${vm_state}" == "in shutdown" ]]; then
      echo "Error: VM '${NAME}' shut down while waiting for SSH." >&2
      echo "Use 'servobox start --name ${NAME}' to boot the VM." >&2
      exit 1
    fi
    
    echo "Error: SSH is not responding on ${IP}." >&2
    echo "This may indicate:" >&2
    echo "  • SSH service is not running in the VM" >&2
    echo "  • Cloud-init is still configuring the system" >&2
    echo "  • Network connectivity issues" >&2
    echo "" >&2
    echo "Try:" >&2
    echo "  • virsh console ${NAME}          # Check VM console" >&2
    echo "  • servobox debug --name ${NAME}  # Check VM logs" >&2
    echo "  • Wait a few minutes for cloud-init to complete" >&2
    exit 1
  fi
  
  # Remove stale known_hosts entry if present to avoid host key mismatch
  ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${IP}" >/dev/null 2>&1 || true
  # Prefer not storing/updating host keys for quick dev cycles
  SSH_OPTS=(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o UpdateHostKeys=no)
  # If user provided a private key or we can infer it from pubkey, use it
  local id_opt=()
  if [[ -n "${SSH_PRIVKEY_PATH:-}" && -f "${SSH_PRIVKEY_PATH}" ]]; then
    id_opt=(-i "${SSH_PRIVKEY_PATH}")
  else
    if [[ -n "${SSH_PUBKEY_PATH:-}" ]]; then
      local guess_priv="${SSH_PUBKEY_PATH%.pub}"
      [[ -f "${guess_priv}" ]] && id_opt=(-i "${guess_priv}")
    else
      for cand in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa"; do
        [[ -f "${cand}" ]] && { id_opt=(-i "${cand}"); break; }
      done
    fi
  fi
  # Try plain SSH first (like manual): lets agent/defaults pick the key
  if ssh "${SSH_OPTS[@]}" servobox-usr@"${IP}"; then
    exit 0
  fi
  # Then try explicit identity with publickey only
  if ssh ${id_opt:+"${id_opt[@]}"} -o IdentitiesOnly=yes -o PreferredAuthentications=publickey "${SSH_OPTS[@]}" servobox-usr@"${IP}"; then
    exit 0
  fi
  # Fallback to password if available
  PW="servobox-pwd"
  if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "${PW}" ssh "${SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no -o PasswordAuthentication=yes servobox-usr@"${IP}"
    exit $?
  else
    echo "Tip: Install sshpass to auto-use the standard password."
    echo "Password for servobox-usr@${IP}: ${PW}"
    echo "Try: ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no servobox-usr@${IP}"
  fi
  exit 1
}

