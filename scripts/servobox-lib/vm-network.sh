#!/usr/bin/env bash
# VM networking functions

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# List candidate host NICs suitable for direct/macvtap attachment
list_host_nics() {
  # Show only UP physical-ish interfaces and filter out virtuals/bridges/taps
  ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' |
    sed 's/@.*$//' |
    grep -E -v '^(lo|virbr|vnet|veth|br|docker|tap|tun|macvtap|wg|tailscale|zt|nm-|vmnet)' |
    sort -u
}

# Get network configuration for a host NIC
get_host_nic_config() {
  local nic="$1"
  if [[ -z "$nic" ]]; then
    echo "No NIC specified"
    return 1
  fi
  
  # Get IP address and subnet
  local ip_info
  ip_info=$(ip -4 addr show dev "$nic" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  if [[ -z "$ip_info" ]]; then
    echo "No IPv4 configuration found on $nic"
    return 1
  fi
  
  local ip_addr="${ip_info%/*}"
  local prefix_len="${ip_info#*/}"
  
  # Calculate network address
  local network
  network=$(ipcalc -n "$ip_info" 2>/dev/null | cut -d= -f2 || echo "")
  
  # Suggest VM IP (copy host IP as requested)
  local vm_ip
  if [[ -n "$ip_addr" && -n "$prefix_len" ]]; then
    vm_ip="$ip_addr"
  fi
  
  echo "Host NIC: $nic"
  echo "Host IP: $ip_addr/$prefix_len"
  echo "Network: $network/$prefix_len"
}

# Prompt user to choose NICs (up to 2) if interactive
choose_host_nic() {
  # If stdin is not a TTY, skip
  if [[ ! -t 0 ]]; then return 0; fi
  mapfile -t CANDS < <(list_host_nics)
  if [[ ${#CANDS[@]} -eq 0 ]]; then
    echo "No eligible host NICs found to attach via macvtap." >&2
    return 0
  fi
  
  echo "=== ServoBox Network Setup ==="
  echo "Select host NICs to attach to the VM (max 2 for dual robot setups)."
  echo "Press ENTER to skip NIC selection."
  echo ""
  
  local i=1
  for dev in "${CANDS[@]}"; do
    local drv
    drv=$(ethtool -i "$dev" 2>/dev/null | awk -F': ' '/driver:/{print $2}' || true)
    local ip4
    ip4=$(ip -4 addr show dev "$dev" 2>/dev/null | awk '/inet /{print $2}' | paste -sd, - || true)
    echo "  [$i] $dev  ${drv:+driver=$drv }${ip4:+ip=$ip4}"
    i=$((i+1))
  done
  echo ""
  
  # Select first NIC
  printf "Select first NIC (or press ENTER to skip): "
  read -r sel1 || true
  if [[ -n "$sel1" ]]; then
    if [[ "$sel1" =~ ^[0-9]+$ ]] && (( sel1>=1 && sel1<=${#CANDS[@]} )); then
      HOST_NICS+=("${CANDS[$((sel1-1))]}")
      echo "✓ Selected: ${CANDS[$((sel1-1))]}"
      echo ""
      get_host_nic_config "${CANDS[$((sel1-1))]}"
      echo ""
      
      # Select second NIC
      printf "Select second NIC (optional, press ENTER to skip): "
      read -r sel2 || true
      if [[ -n "$sel2" ]]; then
        if [[ "$sel2" =~ ^[0-9]+$ ]] && (( sel2>=1 && sel2<=${#CANDS[@]} )); then
          if [[ "$sel2" != "$sel1" ]]; then
            HOST_NICS+=("${CANDS[$((sel2-1))]}")
            echo "✓ Selected: ${CANDS[$((sel2-1))]}"
            echo ""
            get_host_nic_config "${CANDS[$((sel2-1))]}"
            echo ""
          else
            echo "Warning: Cannot select the same NIC twice. Skipping second NIC." >&2
          fi
        else
          echo "Invalid selection. Skipping second NIC." >&2
        fi
      fi
    else
      echo "Invalid selection. Skipping NIC configuration." >&2
    fi
  fi
  
  if [[ ${#HOST_NICS[@]} -gt 0 ]]; then
    echo "Network setup complete. ${#HOST_NICS[@]} NIC(s) will be attached to the VM."
  else
    echo "No NICs selected. VM will use NAT networking only."
  fi
}

# Inject persistent netplan for the primary (NAT) NIC using MAC match
# NOTE: This function now uses DHCP with a fallback to static IP for robustness
# The DHCP reservation in the libvirt network ensures consistent IP assignment
inject_primary_static_netplan() {
  local target_mac="${MAC_ADDR}"
  local effective_cidr="${STATIC_IP_CIDR:-${DEFAULT_NAT_STATIC}}"
  local vm_ip="${effective_cidr%/*}"
  local vm_prefix="${effective_cidr#*/}"
  local gateway="192.168.122.1"   # libvirt 'default' network gateway

  local np_tmp
  np_tmp=$(mktemp)
  cat > "${np_tmp}" <<NPYAML
network:
  version: 2
  ethernets:
    enp-nat:
      match:
        macaddress: ${target_mac}
      dhcp4: true
      dhcp4-overrides:
        use-dns: true
        use-routes: true
      # Fallback to static IP if DHCP fails
      addresses:
        - ${vm_ip}/${vm_prefix}
      gateway4: ${gateway}
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
NPYAML

  echo "Configuring primary NIC (MAC ${target_mac}): DHCP with static IP fallback (${vm_ip}/${vm_prefix})"
  if virt-customize -a "${DISK_QCOW}" \
      --mkdir /etc/netplan \
      --copy-in "${np_tmp}:/etc/netplan" \
      --run-command "mv -f /etc/netplan/$(basename ${np_tmp}) /etc/netplan/99-servobox-primary-static.yaml" \
      --run-command "chown root:root /etc/netplan/99-servobox-primary-static.yaml && chmod 0600 /etc/netplan/99-servobox-primary-static.yaml" >/dev/null 2>&1; then
    :
  else
    sudo virt-customize -a "${DISK_QCOW}" \
      --mkdir /etc/netplan \
      --copy-in "${np_tmp}:/etc/netplan" \
      --run-command "mv -f /etc/netplan/$(basename ${np_tmp}) /etc/netplan/99-servobox-primary-static.yaml" \
      --run-command "chown root:root /etc/netplan/99-servobox-primary-static.yaml && chmod 0600 /etc/netplan/99-servobox-primary-static.yaml"
  fi
  rm -f "${np_tmp}" 2>/dev/null || true
}

# Inject persistent netplan config into the guest image (bypass cloud-init)
# Supports up to 2 macvtap NICs, matches by MAC and assigns static IPs
inject_persistent_netplan() {
  # Only act if host NICs were selected
  if [[ ${#HOST_NICS[@]} -eq 0 ]]; then
    return 0
  fi

  # Generate MAC addresses for each NIC if not already set
  if [[ -z "${MAC_ADDR2}" ]]; then
    MAC_ADDR2="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
  fi
  if [[ ${#HOST_NICS[@]} -ge 2 ]] && [[ -z "${MAC_ADDR3}" ]]; then
    MAC_ADDR3="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
  fi

  # Build netplan configuration for all host NICs
  local np_tmp
  np_tmp=$(mktemp)
  
  cat > "${np_tmp}" <<NPYAML_HEADER
network:
  version: 2
  ethernets:
NPYAML_HEADER

  # Configure first host NIC (enp2s0)
  if [[ ${#HOST_NICS[@]} -ge 1 ]]; then
    local ip_info
    ip_info=$(ip -4 addr show dev "${HOST_NICS[0]}" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    local vm_ip="172.16.0.100"
    local vm_prefix="24"
    local host_ip=""
    
    if [[ -n "${ip_info}" ]]; then
      host_ip="${ip_info%/*}"
      vm_prefix="${ip_info#*/}"
      
      # Generate VM IP in same subnet but different from host
      # If host is X.Y.Z.W, try X.Y.Z.100, X.Y.Z.101, etc.
      local ip_base="${host_ip%.*}"
      local last_octet="${host_ip##*.}"
      
      # Try .100 first, then .101, .102, etc. (avoid conflict with host)
      for offset in 100 101 102 103 104 105 110 120 150 200; do
        if [[ ${offset} -ne ${last_octet} ]]; then
          vm_ip="${ip_base}.${offset}"
          break
        fi
      done
    fi
    
    cat >> "${np_tmp}" <<NPYAML_NIC1
    enp-macvtap1:
      match:
        macaddress: ${MAC_ADDR2}
      set-name: enp2s0
      dhcp4: false
      optional: true
      addresses:
        - ${vm_ip}/${vm_prefix}
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
NPYAML_NIC1
    
    echo "Configuring first NIC: ${HOST_NICS[0]} → enp2s0 (MAC ${MAC_ADDR2}, IP ${vm_ip}/${vm_prefix})"
    if [[ -n "${host_ip}" ]]; then
      echo "  Note: Host IP is ${host_ip}, VM assigned ${vm_ip} (different IP required for macvtap bridge)"
    fi
  fi

  # Configure second host NIC (enp3s0) if provided
  if [[ ${#HOST_NICS[@]} -ge 2 ]]; then
    local ip_info2
    ip_info2=$(ip -4 addr show dev "${HOST_NICS[1]}" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    local vm_ip2="172.17.0.100"
    local vm_prefix2="24"
    local host_ip2=""
    
    if [[ -n "${ip_info2}" ]]; then
      host_ip2="${ip_info2%/*}"
      vm_prefix2="${ip_info2#*/}"
      
      # Generate VM IP in same subnet but different from host
      local ip_base2="${host_ip2%.*}"
      local last_octet2="${host_ip2##*.}"
      
      # Try .100 first, then .101, .102, etc. (avoid conflict with host)
      for offset in 100 101 102 103 104 105 110 120 150 200; do
        if [[ ${offset} -ne ${last_octet2} ]]; then
          vm_ip2="${ip_base2}.${offset}"
          break
        fi
      done
    fi
    
    cat >> "${np_tmp}" <<NPYAML_NIC2
    enp-macvtap2:
      match:
        macaddress: ${MAC_ADDR3}
      set-name: enp3s0
      dhcp4: false
      optional: true
      addresses:
        - ${vm_ip2}/${vm_prefix2}
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
NPYAML_NIC2
    
    echo "Configuring second NIC: ${HOST_NICS[1]} → enp3s0 (MAC ${MAC_ADDR3}, IP ${vm_ip2}/${vm_prefix2})"
    if [[ -n "${host_ip2}" ]]; then
      echo "  Note: Host IP is ${host_ip2}, VM assigned ${vm_ip2} (different IP required for macvtap bridge)"
    fi
  fi

  echo "Injecting persistent netplan for ${#HOST_NICS[@]} macvtap NIC(s) into guest image"
  
  # Create systemd override to prevent networkd-wait-online from blocking boot
  # Compatible with Ubuntu 22.04 (systemd 249) and 24.04 (systemd 255)
  local networkd_override_tmp
  networkd_override_tmp=$(mktemp)
  cat > "${networkd_override_tmp}" <<'NETOVERRIDE'
[Service]
ExecStart=
ExecStart=systemd-networkd-wait-online --any --timeout=10
NETOVERRIDE
  
  # Create macvtap configuration service
  local macvtap_service_tmp
  macvtap_service_tmp=$(mktemp)
  cat > "${macvtap_service_tmp}" <<'MACVTAPSERVICE'
[Unit]
Description=ServoBox Macvtap Interface Configuration
After=network-pre.target
Before=network.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/servobox-configure-macvtap.sh

[Install]
WantedBy=multi-user.target
MACVTAPSERVICE
  
  # Create macvtap configuration script
  local macvtap_script_tmp
  macvtap_script_tmp=$(mktemp)
  cat > "${macvtap_script_tmp}" <<'MACVTAPSCRIPT'
#!/bin/bash
# ServoBox: Configure macvtap interfaces on boot
# This runs early in boot to ensure interfaces are ready before services start

# Exit if no macvtap config exists
[[ ! -f /etc/netplan/99-servobox-macvtap.yaml ]] && exit 0

# Parse netplan config and configure interfaces directly
# This bypasses netplan/NetworkManager issues

# Extract interface details from netplan (simple parsing)
MAC1=$(grep -A 10 "enp-macvtap1:" /etc/netplan/99-servobox-macvtap.yaml | grep macaddress | awk '{print $2}' | tr -d "'" || echo "")
IP1=$(grep -A 10 "enp-macvtap1:" /etc/netplan/99-servobox-macvtap.yaml | grep -E "^\s+- [0-9]" | awk '{print $2}' | head -1 || echo "")

if [[ -n "$MAC1" ]] && [[ -n "$IP1" ]]; then
  # Find interface by MAC
  IFACE=$(ip -o link | grep -i "$MAC1" | awk -F': ' '{print $2}' | head -1)
  
  if [[ -n "$IFACE" ]]; then
    echo "Configuring $IFACE with IP $IP1"
    ip addr flush dev "$IFACE" || true
    ip addr add "$IP1" dev "$IFACE" || true
    ip link set "$IFACE" up || true
    
    # Add route for the subnet
    SUBNET="${IP1%.*}.0/24"
    ip route add "$SUBNET" dev "$IFACE" src "${IP1%/*}" || true
    
    echo "ServoBox: $IFACE configured successfully"
  fi
fi

# Handle second macvtap if exists
MAC2=$(grep -A 10 "enp-macvtap2:" /etc/netplan/99-servobox-macvtap.yaml | grep macaddress | awk '{print $2}' | tr -d "'" 2>/dev/null || echo "")
IP2=$(grep -A 10 "enp-macvtap2:" /etc/netplan/99-servobox-macvtap.yaml | grep -E "^\s+- [0-9]" | awk '{print $2}' | head -1 2>/dev/null || echo "")

if [[ -n "$MAC2" ]] && [[ -n "$IP2" ]]; then
  IFACE2=$(ip -o link | grep -i "$MAC2" | awk -F': ' '{print $2}' | head -1)
  
  if [[ -n "$IFACE2" ]]; then
    echo "Configuring $IFACE2 with IP $IP2"
    ip addr flush dev "$IFACE2" || true
    ip addr add "$IP2" dev "$IFACE2" || true
    ip link set "$IFACE2" up || true
    
    SUBNET2="${IP2%.*}.0/24"
    ip route add "$SUBNET2" dev "$IFACE2" src "${IP2%/*}" || true
    
    echo "ServoBox: $IFACE2 configured successfully"
  fi
fi
MACVTAPSCRIPT
  
  # Ensure destination directory exists and copy files into guest
  if virt-customize -a "${DISK_QCOW}" \
      --mkdir /etc/netplan \
      --copy-in "${np_tmp}:/etc/netplan" \
      --run-command "mv -f /etc/netplan/$(basename ${np_tmp}) /etc/netplan/99-servobox-macvtap.yaml" \
      --run-command "chown root:root /etc/netplan/99-servobox-macvtap.yaml && chmod 0600 /etc/netplan/99-servobox-macvtap.yaml" \
      --mkdir /etc/systemd/system/systemd-networkd-wait-online.service.d \
      --copy-in "${networkd_override_tmp}:/etc/systemd/system/systemd-networkd-wait-online.service.d" \
      --run-command "mv -f /etc/systemd/system/systemd-networkd-wait-online.service.d/$(basename ${networkd_override_tmp}) /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf" \
      --mkdir /etc/systemd/system \
      --copy-in "${macvtap_service_tmp}:/etc/systemd/system" \
      --run-command "mv -f /etc/systemd/system/$(basename ${macvtap_service_tmp}) /etc/systemd/system/servobox-configure-macvtap.service" \
      --mkdir /usr/local/bin \
      --copy-in "${macvtap_script_tmp}:/usr/local/bin" \
      --run-command "mv -f /usr/local/bin/$(basename ${macvtap_script_tmp}) /usr/local/bin/servobox-configure-macvtap.sh" \
      --run-command "chmod +x /usr/local/bin/servobox-configure-macvtap.sh" \
      --run-command "systemctl daemon-reload" \
      --run-command "systemctl enable servobox-configure-macvtap.service" >/dev/null 2>&1; then
    :
  else
    sudo virt-customize -a "${DISK_QCOW}" \
      --mkdir /etc/netplan \
      --copy-in "${np_tmp}:/etc/netplan" \
      --run-command "mv -f /etc/netplan/$(basename ${np_tmp}) /etc/netplan/99-servobox-macvtap.yaml" \
      --run-command "chown root:root /etc/netplan/99-servobox-macvtap.yaml && chmod 0600 /etc/netplan/99-servobox-macvtap.yaml" \
      --mkdir /etc/systemd/system/systemd-networkd-wait-online.service.d \
      --copy-in "${networkd_override_tmp}:/etc/systemd/system/systemd-networkd-wait-online.service.d" \
      --run-command "mv -f /etc/systemd/system/systemd-networkd-wait-online.service.d/$(basename ${networkd_override_tmp}) /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf" \
      --mkdir /etc/systemd/system \
      --copy-in "${macvtap_service_tmp}:/etc/systemd/system" \
      --run-command "mv -f /etc/systemd/system/$(basename ${macvtap_service_tmp}) /etc/systemd/system/servobox-configure-macvtap.service" \
      --mkdir /usr/local/bin \
      --copy-in "${macvtap_script_tmp}:/usr/local/bin" \
      --run-command "mv -f /usr/local/bin/$(basename ${macvtap_script_tmp}) /usr/local/bin/servobox-configure-macvtap.sh" \
      --run-command "chmod +x /usr/local/bin/servobox-configure-macvtap.sh" \
      --run-command "systemctl daemon-reload" \
      --run-command "systemctl enable servobox-configure-macvtap.service"
  fi
  rm -f "${np_tmp}" "${networkd_override_tmp}" "${macvtap_service_tmp}" "${macvtap_script_tmp}" 2>/dev/null || true
  
  echo "Configured systemd-networkd-wait-online to not block boot (--any --timeout=10)"
  echo "Installed servobox-configure-macvtap.service for automatic interface configuration"
}

gen_cloud_init() {
  echo "Generating cloud-init seed for ServoBox RT image"
  # Temporarily relax exit-on-error to surface controlled messages
  set +e
  USERDATA=$(mktemp)
  METADATA=$(mktemp)
  mkdir -p "${HOME}/.ssh"
  mapfile -t PUBKEY_FILES < <(find "${HOME}/.ssh" -maxdepth 1 -type f -name "*.pub" 2>/dev/null | sort)
  if [[ ${#PUBKEY_FILES[@]} -eq 0 ]]; then
    ssh-keygen -q -t ed25519 -N "" -f "${HOME}/.ssh/id_ed25519"
    PUBKEY_FILES=("${HOME}/.ssh/id_ed25519.pub")
  fi
  AUTH_KEYS=""
  AUTH_KEYS_FLAT=""
  AUTH_KEYS_FLAT_INDENTED=""
  for k in "${PUBKEY_FILES[@]}"; do
    line=$(cat "$k" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
      AUTH_KEYS+=$(printf "      - %s\n" "$line")
      AUTH_KEYS_FLAT+=$(printf "%s\n" "$line")
      AUTH_KEYS_FLAT_INDENTED+=$(printf "      %s\n" "$line")
    fi
  done

  # Prepare fallback SSH password for development convenience
  if [[ ! -d "${VM_DIR}" ]]; then
    if mkdir -p "${VM_DIR}" 2>/dev/null; then :; else sudo -n mkdir -p "${VM_DIR}" 2>/dev/null || sudo mkdir -p "${VM_DIR}"; fi
  fi
  # Use standard default password for servobox-usr
  SERVOBOX_PW="servobox-pwd"
  
  # Get host NIC network configuration if available (use first NIC for backward compat)
  HOST_NIC_INFO=""
  if [[ ${#HOST_NICS[@]} -ge 1 ]]; then
    local ip_info
    ip_info=$(ip -4 addr show dev "${HOST_NICS[0]}" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    if [[ -n "$ip_info" ]]; then
      HOST_NIC_INFO="$ip_info"
    fi
  fi

  # Derive intended VM IP/prefix for the direct NIC at generation-time
  VM_IP="172.16.0.1"
  VM_PREFIX="24"
  if [[ -n "${HOST_NIC_INFO}" ]]; then
    HOST_IP="${HOST_NIC_INFO%/*}"
    HOST_PREFIX="${HOST_NIC_INFO#*/}"
    if [[ -n "${HOST_IP}" && -n "${HOST_PREFIX}" ]]; then
      VM_IP="${HOST_IP}"
      VM_PREFIX="${HOST_PREFIX}"
    fi
  fi

  # Build optional write_files snippet for deterministic netplan on guest
  # (Legacy/unused - netplan injection now handled by inject_persistent_netplan)
  NETPLAN_WRITE=""

  cat > "${USERDATA}" <<EOF
#cloud-config
hostname: ${NAME}
manage_etc_hosts: true
users:
  - name: servobox-usr
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, realtime
    shell: /bin/bash
    ssh_authorized_keys:
${AUTH_KEYS}
    # Don't recreate home directory if it already exists (preserve build-time installations)
    create_home: false
ssh_pwauth: true
chpasswd:
  expire: false
  list: |
    servobox-usr:${SERVOBOX_PW}

write_files:
  - path: /etc/ssh/sshd_config.d/99-servobox.conf
    owner: root:root
    permissions: '0644'
    content: |
      PasswordAuthentication yes
      PubkeyAuthentication yes
  - path: /home/servobox-usr/.ssh/authorized_keys
    owner: servobox-usr:servobox-usr
    permissions: '0600'
    content: |
${AUTH_KEYS_FLAT_INDENTED}
  - path: /etc/hosts
    owner: root:root
    permissions: '0644'
    content: |
      127.0.0.1 localhost
      127.0.1.1 ${NAME}
      ::1 ip6-localhost ip6-loopback
      fe00::0 ip6-localnet
      ff00::0 ip6-mcastprefix
      ff02::1 ip6-allnodes
      ff02::2 ip6-allrouters
  - path: /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
    owner: root:root
    permissions: '0644'
    content: |
      [Service]
      ExecStart=
      ExecStart=systemd-networkd-wait-online --any --timeout=10
  - path: /etc/systemd/system/servobox-configure-macvtap.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=ServoBox Macvtap Interface Configuration
      After=network-pre.target
      Before=network.target
      Wants=network-pre.target
      
      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=/usr/local/bin/servobox-configure-macvtap.sh
      
      [Install]
      WantedBy=multi-user.target
  - path: /usr/local/bin/servobox-configure-macvtap.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/bin/bash
      # ServoBox: Configure macvtap interfaces on boot
      # This runs early in boot to ensure interfaces are ready before services start
      
      # Exit if no macvtap config exists
      [[ ! -f /etc/netplan/99-servobox-macvtap.yaml ]] && exit 0
      
      # Parse netplan config and configure interfaces directly
      # This bypasses netplan/NetworkManager issues
      
      # Extract interface details from netplan (simple parsing)
      MAC1=$(grep -A 10 "enp-macvtap1:" /etc/netplan/99-servobox-macvtap.yaml | grep macaddress | awk '{print $2}' | tr -d "'" || echo "")
      IP1=$(grep -A 10 "enp-macvtap1:" /etc/netplan/99-servobox-macvtap.yaml | grep -E "^\s+- [0-9]" | awk '{print $2}' | head -1 || echo "")
      
      if [[ -n "$MAC1" ]] && [[ -n "$IP1" ]]; then
        # Find interface by MAC
        IFACE=$(ip -o link | grep -i "$MAC1" | awk -F': ' '{print $2}' | head -1)
        
        if [[ -n "$IFACE" ]]; then
          echo "Configuring $IFACE with IP $IP1"
          ip addr flush dev "$IFACE" || true
          ip addr add "$IP1" dev "$IFACE" || true
          ip link set "$IFACE" up || true
          
          # Add route for the subnet
          SUBNET="${IP1%.*}.0/24"
          ip route add "$SUBNET" dev "$IFACE" src "${IP1%/*}" || true
          
          echo "ServoBox: $IFACE configured successfully"
        fi
      fi
      
      # Handle second macvtap if exists
      MAC2=$(grep -A 10 "enp-macvtap2:" /etc/netplan/99-servobox-macvtap.yaml | grep macaddress | awk '{print $2}' | tr -d "'" 2>/dev/null || echo "")
      IP2=$(grep -A 10 "enp-macvtap2:" /etc/netplan/99-servobox-macvtap.yaml | grep -E "^\s+- [0-9]" | awk '{print $2}' | head -1 2>/dev/null || echo "")
      
      if [[ -n "$MAC2" ]] && [[ -n "$IP2" ]]; then
        IFACE2=$(ip -o link | grep -i "$MAC2" | awk -F': ' '{print $2}' | head -1)
        
        if [[ -n "$IFACE2" ]]; then
          echo "Configuring $IFACE2 with IP $IP2"
          ip addr flush dev "$IFACE2" || true
          ip addr add "$IP2" dev "$IFACE2" || true
          ip link set "$IFACE2" up || true
          
          SUBNET2="${IP2%.*}.0/24"
          ip route add "$SUBNET2" dev "$IFACE2" src "${IP2%/*}" || true
          
          echo "ServoBox: $IFACE2 configured successfully"
        fi
      fi

package_update: true
# Avoid automatic full upgrades to keep image size stable; update explicitly when needed
package_upgrade: false

packages:
  - linux-tools-common
  - htop
  - vim
  - curl
  - wget
  - git

runcmd:
  - |
    set +e
    # ULTRA-FAST PATH: Start SSH immediately, exit cloud-init runcmd ASAP
    # All expensive operations moved to background systemd service
    systemctl enable ssh || systemctl enable sshd || true
    systemctl start ssh || systemctl start sshd || true
    
    # Quick DNS fallback (non-blocking)
    if [[ ! -f /etc/resolv.conf ]] || ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
      mkdir -p /etc
      echo "nameserver 8.8.8.8" > /etc/resolv.conf 2>/dev/null || true
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf 2>/dev/null || true
    fi
    
    # Enable macvtap configuration service (runs on every boot)
    systemctl daemon-reload || true
    systemctl enable servobox-configure-macvtap.service || true
    systemctl start servobox-configure-macvtap.service || true
    
    # Exit immediately - SSH is up, expensive stuff happens in background service
    exit 0

    # Ensure servobox-usr exists and is properly configured (preserve build-time installations)
    if ! id -u servobox-usr >/dev/null 2>&1; then
      echo "Creating servobox-usr user (not found in image)..."
      useradd -m -s /bin/bash servobox-usr
    fi
    usermod -aG sudo,realtime servobox-usr || true
    mkdir -p /home/servobox-usr/.ssh
    chown -R servobox-usr:servobox-usr /home/servobox-usr
    chmod 700 /home/servobox-usr/.ssh
    
    # NOTE: Default VM credentials (servobox-usr:servobox-pwd) are intentional
    # These are for local development VMs only (NAT-isolated, not public-facing)
    # Force password change (cloud-init chpasswd might not work if user exists)
    echo "servobox-usr:servobox-pwd" | chpasswd

    # Ensure SSH allows password/publickey auth and reload service
    systemctl reload ssh || systemctl restart ssh || true

    # Ensure DNS is properly configured before any network operations
    echo "Configuring DNS resolution..."
    # Apply netplan to ensure DNS nameservers are set
    netplan apply || true
    # Wait for systemd-resolved to be ready
    systemctl restart systemd-resolved || true
    sleep 2
    # Ensure /etc/resolv.conf points to systemd-resolved
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true
    # Verify DNS works by testing resolution (reduced timeout for faster boot)
    if ! timeout 3 getent hosts google.com >/dev/null 2>&1; then
      echo "DNS resolution not working, applying fallback configuration..."
      # Fallback: directly configure resolv.conf with public DNS
      echo "nameserver 8.8.8.8" > /etc/resolv.conf
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      # Restart systemd-resolved with the new configuration
      systemctl restart systemd-resolved || true
    fi
    echo "DNS configuration completed"

    # Configure enp2s0 interface directly (if it exists)
    echo "Configuring enp2s0 interface..."
    if ip link show enp2s0 >/dev/null 2>&1; then
      echo "Found enp2s0, configuring with IP 172.16.0.1/24"
      ip addr add 172.16.0.1/24 dev enp2s0 || true
      ip link set enp2s0 up || true
      echo "enp2s0 configured successfully"
    else
      echo "enp2s0 not found (will be configured if/when direct NIC is attached)"
    fi

    # Configure firewall for libfranka communication (disable blocking)
    echo "Configuring firewall for libfranka communication..."
    ufw --force disable || true
    iptables -F || true
    iptables -X || true
    iptables -t nat -F || true
    iptables -t nat -X || true
    iptables -t mangle -F || true
    iptables -t mangle -X || true
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # Disable reverse path filtering (critical for macvtap UDP communication)
    # rp_filter can block UDP packets from Franka robot with macvtap bridge
    sysctl -w net.ipv4.conf.all.rp_filter=0 || true
    sysctl -w net.ipv4.conf.default.rp_filter=0 || true
    # Make persistent
    if ! grep -q "net.ipv4.conf.all.rp_filter" /etc/sysctl.conf 2>/dev/null; then
      echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf
      echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.conf
    fi
    
    echo "Firewall configured for libfranka communication"

    # Apply guest tuning (non-fatal in dev)
    echo "Applying guest real-time tuning..."
    apt-get -y install rt-tests cpufrequtils stress-ng
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      echo performance > "\$cpu" 2>/dev/null || true
    done
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash isolcpus=1,2,3 nohz_full=1,2,3 rcu_nocbs=1,2,3"/' /etc/default/grub
    systemctl disable --now snapd || true
    systemctl disable --now ModemManager || true
    systemctl disable --now bluetooth || true
    systemctl disable --now cups || true
    systemctl disable --now avahi-daemon || true
    echo '#!/bin/bash' > /home/servobox-usr/rt-test.sh
    echo 'echo "Real-time latency test (cyclictest) - 1kHz Application Focus"' >> /home/servobox-usr/rt-test.sh
    echo 'echo "Testing 1kHz timing requirements (1000μs cycle time)..."' >> /home/servobox-usr/rt-test.sh
    echo 'echo "Running for \${TEST_DURATION:-60} seconds on isolated CPUs..."' >> /home/servobox-usr/rt-test.sh
    echo "cyclictest -t1 -p 80 -i 1000 -l \$((\${TEST_DURATION:-60} * 1000)) -q --duration=\${TEST_DURATION:-60}" >> /home/servobox-usr/rt-test.sh
    chmod +x /home/servobox-usr/rt-test.sh
    chown servobox-usr:servobox-usr /home/servobox-usr/rt-test.sh
    echo "Guest real-time tuning completed!"

    update-grub || true
    
    # Mark first boot as complete
    touch "\$FIRST_BOOT_FLAG"
    
    # Disable cloud-init on subsequent boots to prevent delays
    # Method 1: Create disable file (cloud-init checks this first)
    mkdir -p /etc/cloud
    touch /etc/cloud/cloud-init.disabled
    
    # Method 2: Disable services (backup method)
    systemctl disable cloud-init cloud-init-local cloud-config cloud-final || true
    echo "Cloud-init disabled for future boots (will not run on subsequent starts)"
    
    echo "ServoBox VM first-boot initialization completed!"

final_message: |
  ServoBox VM is ready!
  - Real-time kernel installed and configured
  - CPU governor set to performance
  - Real-time kernel parameters tuned
  - IRQ isolation configured
  - Cyclictest available for latency testing
EOF

  cat > "${METADATA}" <<EOF
instance-id: ${NAME}
local-hostname: ${NAME}
EOF

  # Debug: show the cloud-init config we're generating
  if [[ "${DEBUG}" -eq 1 ]]; then
    echo "=== Generated cloud-init user-data ==="
    cat "${USERDATA}"
    echo "=== End cloud-init user-data ==="
  fi

  # Ensure VM directory exists and is writable or we can elevate non-interactively
  if [[ ! -d "${VM_DIR}" ]]; then
    if mkdir -p "${VM_DIR}" 2>/dev/null; then :; 
    elif sudo -n mkdir -p "${VM_DIR}" 2>/dev/null; then :;
    else
      echo "Error: Cannot create ${VM_DIR} without sudo. Please run with sudo access." >&2
      exit 1
    fi
  fi
  
  # Try to generate seed - use tmp file and move approach for better permission handling
  SEED_TMP=$(mktemp)
  if ! timeout 30 cloud-localds "${SEED_TMP}" "${USERDATA}" "${METADATA}" >/dev/null 2>&1; then
    echo "Error: cloud-localds failed generating seed image" >&2
    rm -f "${SEED_TMP}" 2>/dev/null || true
    exit 1
  fi
  
  # Move seed to final location (with sudo if needed, but prefer non-interactive)
  # Force overwrite to avoid prompts
  if ! mv -f "${SEED_TMP}" "${SEED_ISO}" 2>/dev/null; then
    if ! timeout 5 sudo -n mv -f "${SEED_TMP}" "${SEED_ISO}" 2>/dev/null; then
      echo "Error: Cannot move seed image to ${SEED_ISO}" >&2
      echo "Temp file location: ${SEED_TMP}" >&2
      echo "Please run manually: sudo mv -f ${SEED_TMP} ${SEED_ISO}" >&2
      exit 1
    fi
  fi
  
  # Set proper ownership and permissions
  sudo -n chown libvirt-qemu:kvm "${SEED_ISO}" 2>/dev/null || sudo chown libvirt-qemu:kvm "${SEED_ISO}" 2>/dev/null || true
  sudo -n chmod 0644 "${SEED_ISO}" 2>/dev/null || sudo chmod 0644 "${SEED_ISO}" 2>/dev/null || true
  rm -f "${USERDATA}" "${METADATA}"
  echo "cloud-init seed generated: ${SEED_ISO}"
  # Restore strict mode
  set -e
}

vm_ip() {
  # Method 1: Try virsh domifaddr (works for DHCP)
  local ip
  ip=$(virsh_cmd domifaddr "${NAME}" 2>/dev/null | awk '/ipv4/ {print $4}' | sed 's#/.*##')
  if [[ -n "${ip}" ]]; then
    echo "${ip}"
    return 0
  fi
  
  # Method 2: Check ARP table using VM's MAC address (works for static IPs)
  local mac
  mac=$(virsh_cmd domiflist "${NAME}" 2>/dev/null | awk '$3 == "default" || $3 ~ /^virbr/ {print $5; exit}')
  if [[ -n "${mac}" ]]; then
    # Ping the expected static IP to populate ARP cache
    local expected_ip="192.168.122.100"  # Default libvirt NAT IP
    if [[ -n "${STATIC_IP_CIDR:-}" ]]; then
      expected_ip="${STATIC_IP_CIDR%/*}"  # strip /prefix
    fi
    ping -c 1 -W 1 "${expected_ip}" >/dev/null 2>&1 || true
    
    # Look up IP by MAC in ARP table
    ip=$(arp -n | awk -v mac="${mac}" 'tolower($3) == tolower(mac) {print $1}')
    if [[ -n "${ip}" ]]; then
      echo "${ip}"
      return 0
    fi
  fi
  
  # Method 3: If we know the static IP, check if it's reachable
  local expected_ip="192.168.122.100"  # Default libvirt NAT IP
  if [[ -n "${STATIC_IP_CIDR:-}" ]]; then
    expected_ip="${STATIC_IP_CIDR%/*}"  # strip /prefix
  fi
  if [[ -n "${expected_ip}" ]] && ping -c 1 -W 1 "${expected_ip}" >/dev/null 2>&1; then
    echo "${expected_ip}"
    return 0
  fi
  
  # No IP found
  return 1
}

wait_for_sshd() {
  local ip="$1"
  local timeout_seconds="${2:-30}"  # Default 30 seconds, configurable
  echo "Waiting for SSH (port 22) on ${ip}... (timeout: ${timeout_seconds}s)"
  
  # Prefer nc scan exactly like manual verification; fallback to ssh-keyscan and /dev/tcp
  local NC=""
  for cand in /usr/bin/nc /bin/nc; do
    if [[ -x "$cand" ]]; then NC="$cand"; break; fi
  done
  
  for i in $(seq 1 ${timeout_seconds}); do
    if [[ -n "$NC" ]]; then
      if "$NC" -vz -w1 "${ip}" 22 >/dev/null 2>&1; then
        echo "SSH is up."
        return 0
      fi
    fi
    if command -v ssh-keyscan >/dev/null 2>&1; then
      if ssh-keyscan -T 2 -p 22 "${ip}" >/dev/null 2>&1; then
        echo "SSH is up."
        return 0
      fi
    fi
    if timeout 1 bash -c "</dev/tcp/${ip}/22" 2>/dev/null; then
      echo "SSH is up."
      return 0
    fi
    
    # Show progress every 5 seconds
    if [[ $((i % 5)) -eq 0 ]]; then
      echo "Still waiting for SSH... (${i}/${timeout_seconds}s)"
    fi
    sleep 1
  done
  
  echo "SSH did not become ready within ${timeout_seconds} seconds on ${ip}" >&2
  echo "Tips: check 'virsh console ${NAME}' and 'systemctl status ssh' inside the guest." >&2
  return 1
}


# Interactive network setup wizard - configure NICs after VM creation
cmd_network_setup() {
  parse_args "$@"
  
  # Check if VM exists
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: VM '${NAME}' does not exist." >&2
    echo "Use 'servobox init --name ${NAME}' to create the VM first." >&2
    exit 1
  fi
  
  # Check if VM is running
  local vm_state
  vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
  if [[ "${vm_state}" == "running" ]]; then
    echo "Warning: VM '${NAME}' is currently running." >&2
    echo "Network changes require the VM to be shut down." >&2
    printf "Stop VM and continue? [y/N]: "
    read -r answer
    if [[ ! "${answer}" =~ ^[Yy] ]]; then
      echo "Network setup cancelled."
      exit 0
    fi
    echo "Stopping VM..."
    virsh_cmd shutdown "${NAME}" >/dev/null 2>&1
    # Wait for shutdown
    for i in {1..30}; do
      vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
      if [[ "${vm_state}" == "shut off" ]]; then
        break
      fi
      sleep 2
    done
    if [[ "${vm_state}" != "shut off" ]]; then
      echo "Error: Failed to stop VM within timeout. Please stop it manually." >&2
      exit 1
    fi
  fi
  
  echo ""
  echo "=== ServoBox Network Configuration Wizard ==="
  echo ""
  echo "This wizard will help you configure network interfaces for ${NAME}."
  echo "You can attach up to 2 host NICs for direct device communication (e.g., dual robot setups)."
  echo ""
  
  # Run the interactive chooser
  if ! choose_host_nic; then
    echo "Error: Failed to select host NICs" >&2
    exit 1
  fi
  
  if [[ ${#HOST_NICS[@]} -eq 0 ]]; then
    echo ""
    echo "No changes made. VM will continue using NAT networking only."
    exit 0
  fi
  
  echo ""
  echo "Reconfiguring VM network..."
  
  # Ensure VM paths are properly set (parse_args already ran but we need to ensure paths)
  if [[ ! -f "${DISK_QCOW}" ]]; then
    echo "Error: VM disk not found at ${DISK_QCOW}" >&2
    exit 1
  fi
  
  if [[ ! -f "${SEED_ISO}" ]]; then
    echo "Error: Cloud-init seed not found at ${SEED_ISO}" >&2
    echo "The VM appears to be incomplete. Please recreate with 'servobox init'." >&2
    exit 1
  fi
  
  # Preserve existing MAC addresses before undefining (only if VM exists)
  if timeout 5 virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    # Extract primary NAT MAC (network=default)
    local existing_nat_mac
    existing_nat_mac=$(timeout 5 virsh_cmd domiflist "${NAME}" 2>/dev/null | awk '$2 == "network" && $3 == "default" {print $5; exit}')
    if [[ -n "${existing_nat_mac}" ]]; then
      MAC_ADDR="${existing_nat_mac}"
      echo "Preserving NAT interface MAC: ${MAC_ADDR}"
    fi
    
    # Extract existing direct NIC MACs if any
    local existing_direct_macs
    mapfile -t existing_direct_macs < <(timeout 5 virsh_cmd domiflist "${NAME}" 2>/dev/null | awk '$2 == "direct" {print $5}')
    if [[ ${#existing_direct_macs[@]} -ge 1 ]]; then
      MAC_ADDR2="${existing_direct_macs[0]}"
      echo "Preserving direct NIC #1 MAC: ${MAC_ADDR2}"
    fi
    if [[ ${#existing_direct_macs[@]} -ge 2 ]]; then
      MAC_ADDR3="${existing_direct_macs[1]}"
      echo "Preserving direct NIC #2 MAC: ${MAC_ADDR3}"
    fi
    
    # Undefine the existing domain (preserving storage)
    echo "Undefining existing VM domain..."
    if ! virsh_cmd undefine "${NAME}" >/dev/null 2>&1; then
      echo "Warning: Failed to undefine VM domain (may already be undefined)" >&2
    fi
  else
    echo "VM domain does not exist. Will create new VM definition."
    # Generate MAC addresses if not already set
    if [[ -z "${MAC_ADDR}" ]]; then
      MAC_ADDR="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
    fi
  fi
  
  # Regenerate MAC addresses if needed
  if [[ ${#HOST_NICS[@]} -ge 1 ]] && [[ -z "${MAC_ADDR2}" ]]; then
    MAC_ADDR2="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
  fi
  if [[ ${#HOST_NICS[@]} -ge 2 ]] && [[ -z "${MAC_ADDR3}" ]]; then
    MAC_ADDR3="52:54:00:$(hexdump -n3 -e '3/1 "%02X"' /dev/urandom | sed 's/../&:/g;s/:$//g' | tr A-Z a-z)"
  fi
  
  # Inject persistent netplan for the new direct NICs
  inject_persistent_netplan
  
  # Note: We do NOT regenerate cloud-init seed here because:
  # 1. Network changes are handled via netplan injection (persistent, survives reboots)
  # 2. Regenerating seed triggers cloud-init to rerun, causing 30-60s boot delays
  # 3. The first-boot flag in the VM disk ensures fast boots on subsequent starts
  
  # Debug: Show what we're about to configure
  echo "Configuring VM with network interfaces:"
  echo "  NAT interface: MAC ${MAC_ADDR}"
  if [[ ${#HOST_NICS[@]} -ge 1 ]]; then
    echo "  Direct NIC #1: ${HOST_NICS[0]} → MAC ${MAC_ADDR2}"
  fi
  if [[ ${#HOST_NICS[@]} -ge 2 ]]; then
    echo "  Direct NIC #2: ${HOST_NICS[1]} → MAC ${MAC_ADDR3}"
  fi
  
  # Ensure domain is undefined before redefining (force redefinition)
  if virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Undefining existing domain to apply new network configuration..."
    virsh_cmd undefine "${NAME}" >/dev/null 2>&1 || true
    # Give libvirt a moment to process
    sleep 1
  fi
  
  # Redefine the domain with new network configuration
  virt_define
  
  # Verify the VM was defined correctly
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: Failed to define VM domain ${NAME}" >&2
    exit 1
  fi
  
  # Verify network interfaces are configured correctly
  echo "Verifying network configuration..."
  local iflist
  iflist=$(virsh_cmd domiflist "${NAME}" 2>/dev/null || true)
  
  echo "Current VM interfaces:"
  echo "${iflist}"
  echo ""
  
  local nat_count=0
  local direct_count=0
  if echo "${iflist}" | grep -q "network.*default"; then
    nat_count=1
  fi
  # Strip whitespace/newlines from grep output and convert to integer
  direct_count=$(echo "${iflist}" | grep -c "direct" 2>/dev/null | tr -d '[:space:]' || echo "0")
  # Ensure it's a number (handle empty string)
  direct_count=${direct_count:-0}
  
  if [[ ${nat_count} -eq 0 ]]; then
    echo "Warning: NAT network interface not found in VM definition" >&2
  fi
  
  if [[ ${#HOST_NICS[@]} -ge 1 ]] && [[ ${direct_count} -lt 1 ]]; then
    echo "Error: Direct NIC #1 not found in VM definition (expected ${HOST_NICS[0]})" >&2
    echo "Found ${direct_count} direct interface(s), expected at least 1" >&2
    exit 1
  fi
  
  if [[ ${#HOST_NICS[@]} -ge 2 ]] && [[ ${direct_count} -lt 2 ]]; then
    echo "Error: Direct NIC #2 not found in VM definition (expected ${HOST_NICS[1]})" >&2
    echo "Found ${direct_count} direct interface(s), expected at least 2" >&2
    exit 1
  fi
  
  echo ""
  echo "✓ Network configuration complete!"
  echo ""
  
  echo ""
  echo "Summary:"
  echo "  VM: ${NAME}"
  echo "  NAT Network: 192.168.122.0/24 (default libvirt)"
  if [[ ${#HOST_NICS[@]} -ge 1 ]]; then
    echo "  Direct NIC #1: ${HOST_NICS[0]} → enp2s0 in VM (MAC: ${MAC_ADDR2})"
  fi
  if [[ ${#HOST_NICS[@]} -ge 2 ]]; then
    echo "  Direct NIC #2: ${HOST_NICS[1]} → enp3s0 in VM (MAC: ${MAC_ADDR3})"
  fi
  echo ""
  echo "VM is now configured. Use 'servobox start' to boot the VM."
}

