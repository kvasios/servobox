#!/usr/bin/env bash
# VM image preparation and customization functions

ensure_image() {
  mkdir -p "${DOWNLOAD_DIR}"
  # If user provided a local artifact, use it
  if [[ -n "${BASE_OVERRIDE}" ]]; then
    if [[ ! -f "${BASE_OVERRIDE}" ]]; then
      echo "Error: --image path not found: ${BASE_OVERRIDE}" >&2
      exit 1
    fi
    echo "Using local base image artifact: ${BASE_OVERRIDE}"
    if echo "${BASE_OVERRIDE}" | grep -qiE "\.xz$" || xz -t "${BASE_OVERRIDE}" >/dev/null 2>&1; then
      echo "Decompressing provided image..."
      if ! xz -dc "${BASE_OVERRIDE}" > "${IMG}"; then
        echo "Error: Failed to decompress image ${BASE_OVERRIDE}" >&2
        exit 1
      fi
    else
      if ! cp "${BASE_OVERRIDE}" "${IMG}"; then
        echo "Error: Failed to copy image ${BASE_OVERRIDE} to ${IMG}" >&2
        exit 1
      fi
    fi
    return
  fi
  if [[ -f "${SYSTEM_BASE_IMG}" ]]; then
    if [[ ! -f "${IMG}" ]]; then
      echo "Copying pre-cached ServoBox base image..."
      if ! cp "${SYSTEM_BASE_IMG}" "${IMG}"; then
        echo "Error: Failed to copy pre-cached image from ${SYSTEM_BASE_IMG} to ${IMG}" >&2
        exit 1
      fi
    fi
    return
  fi
  if [[ ! -f "${IMG}" ]]; then
    echo "Downloading ServoBox prebuilt RT VM image..."

    # Try to derive the correct GitHub release asset URL
    # 1) Prefer tag matching installed servobox version
    # 2) Fallback to latest release
    # 3) Fallback to legacy BASE_IMG_URL_FILE (if present)

    GH_REPO="kvasios/servobox"
    PKG_VER=""
    if command -v dpkg-query >/dev/null 2>&1; then
      PKG_VER=$(dpkg-query -W -f='${Version}' servobox 2>/dev/null || true)
    fi

    # Set up auth for API calls
    API_AUTH_OPTS=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        API_AUTH_OPTS+=("-H" "Authorization: token ${GITHUB_TOKEN}")
    fi

    URL=""
    if [[ -n "${PKG_VER}" ]]; then
      # Normalize tag (common pattern: v<version>)
      TAG="v${PKG_VER}"
      API_URL="https://api.github.com/repos/${GH_REPO}/releases/tags/${TAG}"
      echo "Checking for release tag: ${TAG} (from installed package)"
      # Get the raw API response first
      RAW_RESPONSE=$( (
        set +e
        set +o pipefail 2>/dev/null || true
        local api_exit_code=0
        if command -v curl >/dev/null 2>&1; then
          if [[ ${#API_AUTH_OPTS[@]} -gt 0 ]]; then
            curl -s --max-time 10 "${API_AUTH_OPTS[@]}" "${API_URL}" 2>&1
            api_exit_code=$?
          else
            curl -s --max-time 10 "${API_URL}" 2>&1
            api_exit_code=$?
          fi
        else
          WGET_AUTH_ARGS=()
          if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            WGET_AUTH_ARGS+=("--header=Authorization: token ${GITHUB_TOKEN}")
          fi
          if [[ ${#WGET_AUTH_ARGS[@]} -gt 0 ]]; then
            wget -qO- --timeout=10 --tries=1 "${WGET_AUTH_ARGS[@]}" "${API_URL}" 2>&1
            api_exit_code=$?
          else
            wget -qO- --timeout=10 --tries=1 "${API_URL}" 2>&1
            api_exit_code=$?
          fi
        fi
        exit ${api_exit_code}
      ) )
      local api_exit_code=$?
      if [[ ${api_exit_code} -ne 0 ]]; then
        echo "Warning: Failed to fetch release info for tag ${TAG} (exit code: ${api_exit_code})" >&2
      fi
      
      # Check if we got a valid response
      if [[ -z "${RAW_RESPONSE}" ]]; then
        echo "Warning: Empty response from GitHub API for tag ${TAG}" >&2
      elif echo "${RAW_RESPONSE}" | grep -q '"message": "Not Found"' 2>/dev/null; then
        echo "Warning: Release tag ${TAG} not found on GitHub" >&2
      elif echo "${RAW_RESPONSE}" | grep -q '"message": "Bad credentials"' 2>/dev/null; then
        echo "Warning: GitHub API authentication failed" >&2
      fi
      
      # Extract the correct URL based on whether we have a token
      ASSET_URL=""
      if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        # Private repo: use API asset URL
        ASSET_ID=$(echo "${RAW_RESPONSE}" | \
          grep -A 20 '"assets"' 2>/dev/null | \
          grep -B 5 -A 15 '\.qcow2\.xz' 2>/dev/null | \
          grep '"id"' 2>/dev/null | \
          head -n1 | sed -E 's/.*"id"\s*:\s*([0-9]+).*/\1/')
        
        if [[ -n "${ASSET_ID}" ]]; then
          ASSET_URL="https://api.github.com/repos/${GH_REPO}/releases/assets/${ASSET_ID}"
          echo "Found asset ID: ${ASSET_ID}"
        else
          echo "Warning: Could not find .qcow2.xz asset ID in release response" >&2
        fi
      else
        # Public repo: use browser_download_url
        ASSET_URL=""
        if echo "${RAW_RESPONSE}" | grep -q '"browser_download_url"' 2>/dev/null; then
          ASSET_URL=$(echo "${RAW_RESPONSE}" | \
            grep -Eo '"browser_download_url"\s*:\s*"[^"]+\.qcow2\.xz"' 2>/dev/null | \
            head -n1 | sed -E 's/.*"(https:[^"]+)"/\1/')
        fi
        if [[ -z "${ASSET_URL}" ]]; then
          echo "Warning: Could not find .qcow2.xz download URL in release response" >&2
        fi
      fi
      if [[ -n "${ASSET_URL}" ]]; then
        URL="${ASSET_URL}"
        echo "Found version-specific release: ${URL}"
      else
        echo "Warning: No valid asset URL found for tag ${TAG}" >&2
      fi
    fi

    if [[ -z "${URL}" ]]; then
      # Fallback: auto-detect version from debian/changelog (when running from source)
      if [[ -f "debian/changelog" ]]; then
        DEFAULT_TAG="v$(head -n1 debian/changelog | sed -n 's/.*(\([^)]\+\)).*/\1/p')"
        echo "Checking for release tag: ${DEFAULT_TAG} (from debian/changelog)"
      else
        DEFAULT_TAG="v0.1.2"
        echo "Checking for release tag: ${DEFAULT_TAG} (fallback)"
      fi
      API_URL_TAG="https://api.github.com/repos/${GH_REPO}/releases/tags/${DEFAULT_TAG}"
      # Get the raw API response
      RAW_RESPONSE=$( (
        set +e
        set +o pipefail 2>/dev/null || true
        local api_exit_code=0
        if command -v curl >/dev/null 2>&1; then
          if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            curl -s --max-time 10 -H "Authorization: token ${GITHUB_TOKEN}" "${API_URL_TAG}" 2>&1
            api_exit_code=$?
          else
            curl -s --max-time 10 "${API_URL_TAG}" 2>&1
            api_exit_code=$?
          fi
        else
          if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            wget -qO- --timeout=10 --tries=1 --header="Authorization: token ${GITHUB_TOKEN}" "${API_URL_TAG}" 2>&1
            api_exit_code=$?
          else
            wget -qO- --timeout=10 --tries=1 "${API_URL_TAG}" 2>&1
            api_exit_code=$?
          fi
        fi
        exit ${api_exit_code}
      ) )
      local api_exit_code=$?
      if [[ ${api_exit_code} -ne 0 ]]; then
        echo "Warning: Failed to fetch release info for tag ${DEFAULT_TAG} (exit code: ${api_exit_code})" >&2
      fi
      
      # Check if we got a valid response
      if [[ -z "${RAW_RESPONSE}" ]]; then
        echo "Warning: Empty response from GitHub API for tag ${DEFAULT_TAG}" >&2
      elif echo "${RAW_RESPONSE}" | grep -q '"message": "Not Found"' 2>/dev/null; then
        echo "Warning: Release tag ${DEFAULT_TAG} not found on GitHub" >&2
      elif echo "${RAW_RESPONSE}" | grep -q '"message": "Bad credentials"' 2>/dev/null; then
        echo "Warning: GitHub API authentication failed" >&2
      fi
      
      
      # Extract the asset URL - use browser_download_url for public repos, API URL for private
      ASSET_URL=""
      if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        # Private repo: use API asset URL
        ASSET_ID=$(echo "${RAW_RESPONSE}" | \
          grep -A 20 '"assets"' 2>/dev/null | \
          grep -B 5 -A 15 '\.qcow2\.xz' 2>/dev/null | \
          grep '"id"' 2>/dev/null | \
          head -n1 | sed -E 's/.*"id"\s*:\s*([0-9]+).*/\1/')
        if [[ -n "${ASSET_ID}" ]]; then
          ASSET_URL="https://api.github.com/repos/${GH_REPO}/releases/assets/${ASSET_ID}"
        else
          echo "Warning: Could not find .qcow2.xz asset ID in fallback release response" >&2
        fi
      else
        # Public repo: use browser_download_url
        ASSET_URL=""
        if echo "${RAW_RESPONSE}" | grep -q '"browser_download_url"' 2>/dev/null; then
          ASSET_URL=$(echo "${RAW_RESPONSE}" | \
            grep -Eo '"browser_download_url"\s*:\s*"[^"]+\.qcow2\.xz"' 2>/dev/null | \
            head -n1 | sed -E 's/.*"(https:[^"]+)"/\1/')
        fi
        if [[ -z "${ASSET_URL}" ]]; then
          echo "Warning: Could not find .qcow2.xz download URL in fallback release response" >&2
        fi
      fi
      if [[ -n "${ASSET_URL}" ]]; then
        URL="${ASSET_URL}"
        echo "Found release ${DEFAULT_TAG}: ${URL}"
      else
        echo "Warning: No valid asset URL found for fallback tag ${DEFAULT_TAG}" >&2
      fi
    fi

      if [[ -z "${URL}" ]]; then
        if [[ -f "${BASE_IMG_URL_FILE}" ]]; then
          URL=$(cat "${BASE_IMG_URL_FILE}")
        else
          echo "Error: Could not determine the VM image download URL." >&2
          echo "Please check your internet connection, or provide a local image with --image, or set a direct URL in ${BASE_IMG_URL_FILE}." >&2
          exit 1
        fi
      fi

    echo "Fetching: ${URL}"
    
    # Single download attempt with proper auth
    local download_success=0
    if command -v curl >/dev/null 2>&1; then
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            if curl -fL --connect-timeout 10 --max-time 1800 --retry 2 -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/octet-stream" -o "${IMG}" "${URL}"; then
                download_success=1
            fi
        else
            if curl -fL --connect-timeout 10 --max-time 1800 --retry 2 -o "${IMG}" "${URL}"; then
                download_success=1
            fi
        fi
    else
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            if wget --timeout=30 --tries=2 --read-timeout=30 --progress=dot:giga --header="Authorization: token ${GITHUB_TOKEN}" --header="Accept: application/octet-stream" -O "${IMG}" "${URL}"; then
                download_success=1
            fi
        else
            if wget --timeout=30 --tries=2 --read-timeout=30 --progress=dot:giga -O "${IMG}" "${URL}"; then
                download_success=1
            fi
        fi
    fi
    
    if [[ ${download_success} -eq 0 ]]; then
        echo "Error: Failed to download VM image from ${URL}" >&2
        echo "Please check your internet connection or provide a local image with --image." >&2
        exit 1
    fi

    if [[ ! -s "${IMG}" ]]; then
      echo "Error: Download produced an empty file: ${IMG}" >&2
      echo "Please check your internet connection or provide a local image with --image." >&2
      exit 1
    fi

    # Check if downloaded file is compressed and decompress if needed
    if xz -t "${IMG}" >/dev/null 2>&1; then
      echo "Decompressing downloaded image..."
      if ! xz -dc "${IMG}" > "${IMG}.tmp"; then
        echo "Error: Failed to decompress downloaded image" >&2
        exit 1
      fi
      if ! mv "${IMG}.tmp" "${IMG}"; then
        echo "Error: Failed to replace compressed image with decompressed version" >&2
        exit 1
      fi
    fi

  fi
}

make_vm_storage() {
  if [[ ! -d "${VM_DIR}" ]]; then
    # Try to create directory without sudo first
    if ! mkdir -p "${VM_DIR}" 2>/dev/null; then 
      # If that fails, try with sudo
      echo "Creating VM directory ${VM_DIR} (requires sudo privileges)..."
      if ! sudo mkdir -p "${VM_DIR}" 2>/dev/null; then
        echo "Error: Failed to create VM directory ${VM_DIR}" >&2
        echo "Please ensure you have sudo privileges or run: sudo mkdir -p ${VM_DIR}" >&2
        exit 1
      fi
    fi
    
    # Set permissions - make directories accessible and writable by kvm group
    # This is critical for allowing users to create files before group membership is active
    echo "Setting up directory permissions..."
    sudo chmod 0755 "${LIBVIRT_IMAGES_BASE}" 2>/dev/null || true
    sudo chmod 0755 "${LIBVIRT_IMAGES_BASE}/servobox" 2>/dev/null || true
    
    # Make directory group-owned by kvm and setgid so new files inherit group  
    sudo chgrp kvm "${VM_DIR}" 2>/dev/null || true
    sudo chmod 2775 "${VM_DIR}" 2>/dev/null || true
    
    # Also make the current user owner so they can write even before group membership is active
    sudo chown "$USER:kvm" "${VM_DIR}" 2>/dev/null || true
    
    # If ACLs are available, grant kvm group rwx and set default ACLs
    if command -v setfacl >/dev/null 2>&1; then
      sudo setfacl -m g:kvm:rwx "${VM_DIR}" 2>/dev/null || true
      sudo setfacl -d -m g:kvm:rwx "${VM_DIR}" 2>/dev/null || true
      # Also grant current user full access via ACL
      sudo setfacl -m u:$USER:rwx "${VM_DIR}" 2>/dev/null || true
      sudo setfacl -d -m u:$USER:rwx "${VM_DIR}" 2>/dev/null || true
    fi
  fi
  if [[ ! -f "${DISK_QCOW}" ]]; then
    echo "Preparing VM disk ${DISK_QCOW} from base image..."
    if ( : >"${DISK_QCOW}" ) 2>/dev/null; then
      rm -f "${DISK_QCOW}" 2>/dev/null || true
      if ! qemu-img convert -O qcow2 "${IMG}" "${DISK_QCOW}"; then
        echo "Error: Failed to convert base image to VM disk" >&2
        exit 1
      fi
    else
      if ! sudo qemu-img convert -O qcow2 "${IMG}" "${DISK_QCOW}"; then
        echo "Error: Failed to convert base image to VM disk (with sudo)" >&2
        exit 1
      fi
    fi
    # Optionally grow disk if user requested larger size than base
    if [[ -n "${DISK_GB}" ]]; then
      echo "Resizing VM disk to ${DISK_GB}G..."
      if [[ -w "${DISK_QCOW}" ]]; then
        if ! qemu-img resize "${DISK_QCOW}" ${DISK_GB}G >/dev/null 2>&1; then
          echo "Error: Failed to resize VM disk to ${DISK_GB}G" >&2
          exit 1
        fi
      else
        if ! sudo qemu-img resize "${DISK_QCOW}" ${DISK_GB}G >/dev/null 2>&1; then
          echo "Error: Failed to resize VM disk to ${DISK_GB}G (with sudo)" >&2
          exit 1
        fi
      fi
    fi
    # Ensure libvirt can read the disk
    sudo chown libvirt-qemu:kvm "${DISK_QCOW}" >/dev/null 2>&1 || echo "Warning: Could not set libvirt ownership on disk" >&2
    # Also allow kvm group to write so unprivileged virt-customize works
    sudo chmod 0664 "${DISK_QCOW}" >/dev/null 2>&1 || echo "Warning: Could not set disk permissions" >&2
  fi
}

# Prepare minimal/stripped images so console/SSH work without relying on cloud-init
ensure_guest_basics() {
  echo "Ensuring guest basics (SSH, cloud-init, user, guest agent) are present..."
  # Detect if the image already has sshd and cloud-init; if yes, avoid heavy prep
  local has_sshd=0 has_cloud=0
  if command -v virt-cat >/dev/null 2>&1; then
    if virt-cat -a "${DISK_QCOW}" /usr/sbin/sshd >/dev/null 2>&1; then has_sshd=1; fi
    if virt-cat -a "${DISK_QCOW}" /usr/bin/cloud-init >/dev/null 2>&1; then has_cloud=1; fi
  fi
  # Create a temporary netplan that enables DHCP on all ethernet interfaces by default
  local np_tmp
  np_tmp=$(mktemp)
  cat > "${np_tmp}" <<'NPYAML'
network:
  version: 2
  renderer: networkd
  ethernets:
    all-eth:
      match:
        name: "*"
      dhcp4: true
NPYAML
  # If sshd and cloud-init exist, do a light-touch prep only
  if [[ ${has_sshd} -eq 1 && ${has_cloud} -eq 1 ]]; then
    # NOTE: Default VM credentials (servobox-usr:servobox-pwd) are intentional
    # These are for local development VMs only (NAT-isolated, not public-facing)
    # Users can change via cloud-init user-data or by logging in and running 'passwd'
    local vc_cmd=(virt-customize -a "${DISK_QCOW}" \
      --run-command 'getent group realtime >/dev/null 2>&1 || groupadd realtime' \
      --run-command 'id -u servobox-usr >/dev/null 2>&1 || useradd -m -s /bin/bash servobox-usr' \
      --run-command 'usermod -aG sudo,realtime servobox-usr || true' \
      --run-command 'echo "servobox-usr:servobox-pwd" | chpasswd' \
      --run-command 'mkdir -p /home/servobox-usr/.ssh && chown -R servobox-usr:servobox-usr /home/servobox-usr && chmod 700 /home/servobox-usr/.ssh' \
      --run-command 'mkdir -p /etc/ssh/sshd_config.d && printf "PasswordAuthentication yes\nPubkeyAuthentication yes\n" >/etc/ssh/sshd_config.d/99-servobox.conf' \
      --run-command "sed -i '/^@realtime /d' /etc/security/limits.conf" \
      --run-command "sed -i 's/^# End of file$/@realtime soft rtprio 99\\n@realtime soft priority 99\\n@realtime soft memlock 102400\\n@realtime hard rtprio 99\\n@realtime hard priority 99\\n@realtime hard memlock 102400\\n# End of file/' /etc/security/limits.conf" \
      --run-command 'grep -q pam_limits.so /etc/pam.d/common-session || echo "session required pam_limits.so" >> /etc/pam.d/common-session' \
      --run-command 'grep -q pam_limits.so /etc/pam.d/common-session-noninteractive || echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive' \
      --run-command 'systemctl enable ssh || systemctl enable sshd || true' \
      --run-command 'systemctl enable qemu-guest-agent || true')
    if ! "${vc_cmd[@]}" >/dev/null 2>&1; then 
      echo "Running virt-customize with sudo privileges..."
      if ! sudo "${vc_cmd[@]}"; then
        echo "Error: Failed to customize VM image with guest basics" >&2
        echo "Please ensure you have sudo privileges and virt-customize is available" >&2
        exit 1
      fi
    fi
    rm -f "${np_tmp}" 2>/dev/null || true
    return
  fi

  # First-boot systemd unit to ensure SSH host keys and services come up even if enabling in chroot was ignored
  local fb_tmp
  fb_tmp=$(mktemp)
  cat > "${fb_tmp}" <<'UNIT'
[Unit]
Description=ServoBox first boot provisioning
ConditionFirstBoot=yes

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ssh-keygen -A || true'
ExecStart=/bin/bash -c 'systemctl enable ssh || systemctl enable sshd || true'
ExecStart=/bin/bash -c 'systemctl enable qemu-guest-agent || true'
ExecStart=/bin/bash -c 'systemctl enable systemd-networkd systemd-resolved || true'
ExecStart=/bin/bash -c 'ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true'
ExecStart=/bin/bash -c 'netplan apply || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
  # NOTE: Default VM credentials (servobox-usr:servobox-pwd) are intentional
  # These are for local development VMs only (NAT-isolated, not public-facing)
  # Users can change via cloud-init user-data or by logging in and running 'passwd'
  local vc_cmd=(virt-customize -a "${DISK_QCOW}" \
    --install openssh-server,qemu-guest-agent,cloud-init,netplan.io \
    --run-command 'getent group realtime >/dev/null 2>&1 || groupadd realtime' \
    --run-command 'id -u servobox-usr >/dev/null 2>&1 || useradd -m -s /bin/bash servobox-usr' \
    --run-command 'usermod -aG sudo,realtime servobox-usr || true' \
    --run-command 'echo "servobox-usr:servobox-pwd" | chpasswd' \
    --run-command 'mkdir -p /home/servobox-usr/.ssh && chown -R servobox-usr:servobox-usr /home/servobox-usr && chmod 700 /home/servobox-usr/.ssh' \
    --run-command "sed -i '/^@realtime /d' /etc/security/limits.conf" \
    --run-command "sed -i 's/^# End of file$/@realtime soft rtprio 99\\n@realtime soft priority 99\\n@realtime soft memlock 102400\\n@realtime hard rtprio 99\\n@realtime hard priority 99\\n@realtime hard memlock 102400\\n# End of file/' /etc/security/limits.conf" \
    --run-command 'grep -q pam_limits.so /etc/pam.d/common-session || echo "session required pam_limits.so" >> /etc/pam.d/common-session' \
    --run-command 'grep -q pam_limits.so /etc/pam.d/common-session-noninteractive || echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive' \
    --run-command 'mkdir -p /etc/ssh/sshd_config.d && printf "PasswordAuthentication yes\nPubkeyAuthentication yes\n" >/etc/ssh/sshd_config.d/99-servobox.conf' \
    --upload "${np_tmp}:/etc/netplan/01-servobox-dhcp.yaml" \
    --run-command 'chown root:root /etc/netplan/01-servobox-dhcp.yaml && chmod 0644 /etc/netplan/01-servobox-dhcp.yaml' \
    --upload "${fb_tmp}:/etc/systemd/system/servobox-firstboot.service" \
    --run-command 'chown root:root /etc/systemd/system/servobox-firstboot.service && chmod 0644 /etc/systemd/system/servobox-firstboot.service' \
    --run-command 'ln -sf /etc/systemd/system/servobox-firstboot.service /etc/systemd/system/multi-user.target.wants/servobox-firstboot.service' \
    --run-command 'systemctl enable systemd-networkd systemd-resolved || true' \
    --run-command 'ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true' \
    --run-command 'systemctl enable ssh || systemctl enable sshd || true' \
    --run-command 'systemctl enable qemu-guest-agent || true')
  if ! "${vc_cmd[@]}" >/dev/null 2>&1; then
    echo "Running virt-customize with sudo privileges..."
    if ! sudo "${vc_cmd[@]}"; then
      echo "Error: Failed to customize VM image with full guest setup" >&2
      echo "Please ensure you have sudo privileges and virt-customize is available" >&2
      exit 1
    fi
  fi
  rm -f "${np_tmp}" 2>/dev/null || true
  rm -f "${fb_tmp}" 2>/dev/null || true
}

# Inject SSH authorized_key directly into the VM disk (bypass cloud-init issues)
inject_ssh_key() {
  # Determine public key path
  local pubkey="${SSH_PUBKEY_PATH:-}"
  if [[ -z "${pubkey}" ]]; then
    # Prefer ed25519 then rsa
    if [[ -f "${HOME}/.ssh/id_ed25519.pub" ]]; then pubkey="${HOME}/.ssh/id_ed25519.pub";
    elif [[ -f "${HOME}/.ssh/id_rsa.pub" ]]; then pubkey="${HOME}/.ssh/id_rsa.pub";
    else
      echo "No SSH public key found. Generate one with: ssh-keygen -t ed25519" >&2
      return 0
    fi
  fi
  if [[ ! -f "${pubkey}" ]]; then
    echo "SSH public key not found: ${pubkey}" >&2
    return 0
  fi
  echo "Injecting SSH key into VM image (servobox-usr): ${pubkey}"
  # Try without sudo first, then with sudo if needed
  if ! virt-customize -a "${DISK_QCOW}" --ssh-inject "servobox-usr:file:${pubkey}" >/dev/null 2>&1; then
    # If 'servobox-usr' user doesn't exist in the image yet, create it and retry
    if ! sudo virt-customize -a "${DISK_QCOW}" \
      --run-command 'id -u servobox-usr >/dev/null 2>&1 || (useradd -m -s /bin/bash servobox-usr && usermod -aG sudo servobox-usr && mkdir -p /home/servobox-usr/.ssh && chown -R servobox-usr:servobox-usr /home/servobox-usr && chmod 700 /home/servobox-usr/.ssh)' \
      --ssh-inject "servobox-usr:file:${pubkey}"; then
      echo "Warning: Could not inject SSH key into image. Will rely on cloud-init/write_files." >&2
    fi
  fi
}

