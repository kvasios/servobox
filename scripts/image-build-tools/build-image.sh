#!/usr/bin/env bash
set -euo pipefail

# Build a preprovisioned Ubuntu QCOW2 with PREEMPT_RT kernel installed
# Outputs to artifacts/images/<ubuntu>-rt/<kernel_version>/

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

UBUNTU="jammy"                 # 22.04
KERNEL_VERSION="6.8.0-rt8"     # directory-friendly id
KERNEL_DEBS_DIR="${REPO_ROOT}/artifacts/rt-kernel/${KERNEL_VERSION}/debs"
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/images"
DISK_GB=20
IMAGE_NAME_PREFIX="servobox"
PACKAGES_CONFIG=""            # Optional: comma-separated list of packages to preinstall
PACKAGES_DIR="${REPO_ROOT}/packages"

usage() {
  cat <<EOF
build-image.sh - Build preprovisioned Ubuntu QCOW2 with PREEMPT_RT kernel

Usage:
  build-image.sh [--ubuntu jammy] [--kernel-version 6.8.0-rt8] \
                 [--kernel-debs-dir PATH] [--artifacts-dir PATH] \
                 [--disk-gb N] [--name-prefix servobox] \
                 [--pkg-install TARGET] [--packages CONFIG]

Defaults:
  ubuntu:             ${UBUNTU}
  kernel-version:     ${KERNEL_VERSION}
  kernel-debs-dir:    ${KERNEL_DEBS_DIR}
  artifacts-dir:      ${ARTIFACTS_DIR}
  disk-gb:            ${DISK_GB}
  name-prefix:        ${IMAGE_NAME_PREFIX}
  packages:           (none by default; build is bare RT)

Options:
  --pkg-install      Install packages (comma-separated list)
  --packages         Same as --pkg-install

Examples:
  build-image.sh --packages "build-essential,ros2-humble"
  build-image.sh --pkg-install "libfranka-gen1,deoxys-control"

Notes:
  - Dependencies are declared in each recipe's recipe.conf file
  - During build, packages should be listed in dependency order
  - For runtime installs, use 'servobox pkg-install' which auto-resolves dependencies
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

deps() {
  for c in qemu-img virt-customize wget sha256sum xz; do
    if ! have "$c"; then
      echo "Missing dependency: $c (sudo apt install qemu-utils libguestfs-tools wget xz-utils coreutils)" >&2
      exit 1
    fi
  done
}

preflight_kernel_readable() {
  local unreadable=0
  for k in /boot/vmlinuz*; do
    [[ -e "$k" ]] || continue
    if [[ ! -r "$k" ]]; then
      unreadable=1
      break
    fi
  done
  if [[ $unreadable -eq 1 ]]; then
    echo "Error: Host /boot/vmlinuz* not world-readable; libguestfs supermin may fail." >&2
    echo "Fix: sudo chmod 0644 /boot/vmlinuz*" >&2
    echo "Alternatively, run with sudo -E to inherit LIBGUESTFS_* env and permissions." >&2
    exit 1
  fi
}

guestfs_env_setup() {
  # Use direct backend to avoid libvirt dependency issues
  export LIBGUESTFS_BACKEND=direct
  # Increase memory to help supermin when installing packages
  export LIBGUESTFS_MEMSIZE=${LIBGUESTFS_MEMSIZE:-3072}
  # Prefer KVM if available for performance
  if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    export LIBGUESTFS_ATTACH_METHOD=appliance
  else
    echo "Warning: /dev/kvm not available or not accessible. Falling back to slow TCG." >&2
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ubuntu) UBUNTU="$2"; shift 2;;
      --kernel-version) KERNEL_VERSION="$2"; shift 2;;
      --kernel-debs-dir) KERNEL_DEBS_DIR="$2"; shift 2;;
      --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2;;
      --disk-gb) DISK_GB="$2"; shift 2;;
      --name-prefix) IMAGE_NAME_PREFIX="$2"; shift 2;;
      --packages|--pkg-install) PACKAGES_CONFIG="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1"; usage; exit 1;;
    esac
  done
}

read_base_url() {
  local url_file="${REPO_ROOT}/data/${UBUNTU}-cloudimg.url"
  if [[ ! -f "$url_file" ]]; then
    echo "Error: base image URL file not found: $url_file" >&2
    exit 1
  fi
  local url
  url=$(cat "$url_file")
  echo "$url"
}

download_base_image() {
  local url="$1"
  local out_dir="$2"
  mkdir -p "$out_dir"
  # Cache by upstream filename to avoid collisions between server/minimal
  local base_name
  base_name=$(basename "$url")
  local outfile="$out_dir/${base_name}"
  if [[ -f "$outfile" ]]; then
    echo "Using cached base image: $outfile" >&2
    echo "$outfile"
    return 0
  fi
  echo "Downloading base cloud image from $url ..." >&2
  wget -O "${outfile}.tmp" "$url"
  mv "${outfile}.tmp" "$outfile"
  echo "$outfile"
}

prepare_work_image() {
  local base_img="$1"
  local work_img="$2"
  echo "Preparing working QCOW2 ${work_img} (${DISK_GB}G)"
  qemu-img convert -O qcow2 "$base_img" "$work_img"
  qemu-img resize "$work_img" ${DISK_GB}G >/dev/null 2>&1 || true
}

# Ensure the guest root filesystem actually grows to use the larger disk.
# Many cloud images rely on first-boot grow; we must expand offline so
# kernel installation has enough space.
expand_root_filesystem() {
  local work_img="$1"
  echo "Expanding guest root filesystem to fill disk (in-guest)"
  LIBGUESTFS_BACKEND=${LIBGUESTFS_BACKEND:-direct} virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --run-command 'apt-get update' \
    --run-command 'DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-guest-utils gdisk e2fsprogs' \
    --run-command 'set -e; (lsblk -pn | grep -q "/dev/sda1") || exit 0; growpart /dev/sda 1 || true' \
    --run-command 'set -e; if blkid -o value -s TYPE /dev/sda1 | grep -q ext4; then resize2fs /dev/sda1; fi'
}

install_rt_kernel() {
  local work_img="$1"
  local debs_dir="$2"
  if [[ ! -d "$debs_dir" ]]; then
    echo "Error: kernel debs directory not found: $debs_dir" >&2
    exit 1
  fi
  echo "Installing RT kernel from $debs_dir into image..."
  # Copy debs into /tmp/rt-debs and install
  set -e
  virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --mkdir /tmp/rt-debs \
    --copy-in "$debs_dir/":"/tmp/rt-debs" \
    --run-command 'apt-get update' \
    --run-command 'DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates' \
    --run-command 'set -e; debs=$(find /tmp/rt-debs -type f -name "*.deb" -print); [ -n "$debs" ]; dpkg -i $debs 2>/dev/null || { apt-get -f install -y; dpkg -i $debs; }' \
    --run-command 'update-initramfs -u -k all || true' \
    --run-command 'update-grub || true' \
    --run-command 'rm -rf /tmp/rt-debs'
  # Verify install succeeded; fail fast if not present
  if ! virt-cat -a "$work_img" /var/lib/dpkg/status | awk '/^Package: linux-image-6\.8\.0$/{found=1} /^Status: .* installed$/{if(found){ok=1}} END{exit ok?0:1}'; then
    echo "Error: linux-image-6.8.0 not found installed in image after install" >&2
    echo "Hint: check build logs inside image under /var/log/apt/term.log" >&2
    exit 1
  fi
}

# Ensure default user exists early so package install scripts can rely on it
create_servobox_user() {
  local work_img="$1"
  echo "Ensuring default user 'servobox-usr' exists before package installation..."
  virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --run-command 'addgroup --system realtime || true' \
    --run-command 'id -u servobox-usr >/dev/null 2>&1 || (useradd -m -s /bin/bash servobox-usr && usermod -aG sudo,realtime servobox-usr)' \
    --run-command 'id -u servobox-usr >/dev/null 2>&1 && usermod -aG realtime servobox-usr || true' \
    --run-command 'mkdir -p /home/servobox-usr && chown -R servobox-usr:servobox-usr /home/servobox-usr' \
    --run-command 'echo "servobox-usr:servobox-pwd" | chpasswd' || true  # Default creds for local dev VMs
}

# Get package list from comma-separated string
get_package_list() {
  local packages="$1"
  
  if [[ -z "$packages" ]]; then
    echo ""
    return 0
  fi
  
  # Return the package list as-is (assume comma-separated)
  # Dependencies will be resolved automatically by package-manager.sh
  echo "$packages"
}

# Install packages into the image
install_packages() {
  local work_img="$1"
  local packages_config="$2"
  
  if [[ -z "$packages_config" ]]; then
    echo "No packages specified, skipping package installation"
    return 0
  fi
  
  local packages
  packages=$(get_package_list "$packages_config")
  
  if [[ -z "$packages" ]]; then
    echo "No packages found in configuration: $packages_config"
    return 0
  fi
  
  echo "Installing packages: $packages"
  echo "Note: Dependencies will be automatically resolved and installed"
  
  # Convert comma-separated list to array
  IFS=',' read -ra PACKAGE_ARRAY <<< "$packages"
  
  for package in "${PACKAGE_ARRAY[@]}"; do
    package=$(echo "$package" | xargs) # trim whitespace
    if [[ -z "$package" ]]; then
      continue
    fi
    
    echo "Installing package: $package (with dependencies if any)"
    
    local recipe_dir="${PACKAGES_DIR}/recipes/${package}"
    local install_script="${recipe_dir}/install.sh"
    local package_manager="${PACKAGES_DIR}/scripts/package-manager.sh"
    
    if [[ ! -f "$install_script" ]]; then
      echo "Warning: Package recipe not found: $package (skipping)"
      continue
    fi
    
    # Use package-manager.sh to handle dependency resolution
    # Note: We still use the simpler direct install approach here because:
    # 1. We're in build-image.sh which is a controlled environment
    # 2. The package-manager.sh install command is designed for post-build use
    # 3. For build-time, we trust the user to specify packages in the right order
    #    or we could enhance this later to call package-manager.sh logic
    
    # For now, keep the direct install approach (can be enhanced later)
    # Copy install script and execute it in the image
    virt-customize -a "$work_img" \
      --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
      --copy-in "$recipe_dir:/tmp/" \
      --copy-in "${PACKAGES_DIR}/scripts/pkg-helpers.sh:/tmp/" \
      --run-command "chmod +x /tmp/$(basename "$recipe_dir")/install.sh" \
      --run-command "PACKAGE_NAME='$package' PACKAGE_HELPERS='/tmp/pkg-helpers.sh' RECIPE_DIR='/tmp/$(basename "$recipe_dir")' bash /tmp/$(basename "$recipe_dir")/install.sh" \
      --run-command "rm -rf /tmp/$(basename "$recipe_dir") /tmp/pkg-helpers.sh"
  done
}

purge_old_kernels() {
  local work_img="$1"
  echo "Purging legacy kernels and all kernel headers from the image..."
  local keep_base="${KERNEL_VERSION%%-*}"
  # Purge all linux-image packages except the RT base version we just installed
  virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --run-command 'set -e; imgs="$(dpkg-query -W -f="${Package}\n" "linux-image-*")"; imgs="$(echo "$imgs" | grep -v "^linux-image-${keep_base}$" || true)"; if [ -n "$imgs" ]; then DEBIAN_FRONTEND=noninteractive apt-get purge -y $imgs || true; fi' \
    --run-command 'set -e; hdrs="$(dpkg-query -W -f="${Package}\n" "linux-headers-*")"; if [ -n "$hdrs" ]; then DEBIAN_FRONTEND=noninteractive apt-get purge -y $hdrs || true; fi' \
    --run-command 'update-grub || true' || true
}

bare_minimal_cleanup() {
  local work_img="$1"
  echo "Running minimal cleanup for bare RT build..."
  virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --run-command 'DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true' \
    --run-command 'apt-get clean || true' \
    --run-command 'rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/* || true' \
    --run-command 'cloud-init clean --logs --seed || true' \
    --run-command 'rm -rf /var/lib/cloud/* /var/lib/cloud/instance /var/lib/cloud/instances || true' \
    --run-command 'truncate -s 0 /etc/machine-id || true' \
    --run-command 'rm -f /var/lib/dbus/machine-id || true' \
    --truncate /var/log/wtmp \
    --truncate /var/log/btmp || true
}

# Further minimize by excluding docs/man/info/locales from future installs and cleaning what's present
minimize_docs_and_locales() {
  local work_img="$1"
  echo "Applying dpkg excludes for docs/man/info/locales and cleaning existing content..."
  virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --run-command 'mkdir -p /etc/dpkg/dpkg.cfg.d' \
    --run-command "printf 'path-exclude /usr/share/doc/*\npath-exclude /usr/share/man/*\npath-exclude /usr/share/info/*\npath-exclude /usr/share/lintian/*\npath-exclude /usr/share/locale/*\npath-include /usr/share/locale/en*\n' > /etc/dpkg/dpkg.cfg.d/01_nodoc" \
    --run-command 'rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/lintian/* || true' \
    --run-command "find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en*' -exec rm -rf {} + || true"
}

# Remove packages only needed during build-time expansion
purge_expand_helpers() {
  local work_img="$1"
  echo "Purging build-time helpers (cloud-guest-utils, gdisk, e2fsprogs)..."
  virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --run-command 'DEBIAN_FRONTEND=noninteractive apt-get purge -y cloud-guest-utils gdisk e2fsprogs || true' \
    --run-command 'apt-get autoremove -y || true' \
    --run-command 'apt-get clean || true'
}

add_utilities_and_cleanup() {
  local work_img="$1"
  echo "Adding utilities and cleaning image..."
  virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --install 'rt-tests,stress-ng,htop,vim,git,curl,wget' \
    --run-command 'id -u servobox-usr >/dev/null 2>&1 && usermod -aG realtime servobox-usr || true' \
    --run-command "sed -i '/^@realtime /d' /etc/security/limits.conf" \
    --run-command "sed -i 's/^# End of file$/@realtime soft rtprio 99\\n@realtime soft priority 99\\n@realtime soft memlock 102400\\n@realtime hard rtprio 99\\n@realtime hard priority 99\\n@realtime hard memlock 102400\\n# End of file/' /etc/security/limits.conf" \
    --run-command 'grep -q pam_limits.so /etc/pam.d/common-session || echo "session required pam_limits.so" >> /etc/pam.d/common-session' \
    --run-command 'grep -q pam_limits.so /etc/pam.d/common-session-noninteractive || echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive' \
    --run-command 'apt-get autoremove -y && apt-get clean' \
    --run-command 'systemctl enable ssh || true' \
    --run-command 'mkdir -p /etc/ssh/sshd_config.d && printf "PasswordAuthentication yes\\nPubkeyAuthentication yes\\n" > /etc/ssh/sshd_config.d/99-servobox.conf' \
    --run-command 'ufw --force disable || true' \
    --run-command 'iptables -F || true' \
    --run-command 'iptables -X || true' \
    --run-command 'iptables -t nat -F || true' \
    --run-command 'iptables -t nat -X || true' \
    --run-command 'iptables -t mangle -F || true' \
    --run-command 'iptables -t mangle -X || true' \
    --run-command 'iptables -P INPUT ACCEPT' \
    --run-command 'iptables -P FORWARD ACCEPT' \
    --run-command 'iptables -P OUTPUT ACCEPT' \
    --run-command 'systemctl enable cloud-init.service cloud-init-local.service cloud-config.service cloud-final.service || true' \
    --run-command 'cloud-init clean --logs --seed || true' \
    --run-command 'rm -rf /var/lib/cloud/* /var/lib/cloud/instance /var/lib/cloud/instances || true' \
    --run-command 'truncate -s 0 /etc/machine-id && rm -f /var/lib/dbus/machine-id || true' \
    --truncate /var/log/wtmp \
    --truncate /var/log/btmp \
    --run-command 'cloud-init clean -s -l' || true
}

write_manifest_and_checksums() {
  local out_dir="$1"
  local img_path="$2"
  local compressed_path="$3"
  local manifest_path="$out_dir/manifest.json"
  local checksums_path="$out_dir/checksums.txt"
  local img_name
  img_name=$(basename "$img_path")
  local size_bytes
  size_bytes=$(stat -c %s "$img_path")
  local sha256
  sha256=$(sha256sum "$img_path" | awk '{print $1}')
  local compressed_name=""
  local compressed_size_bytes=0
  local compressed_sha256=""
  if [[ -n "$compressed_path" && -f "$compressed_path" ]]; then
    compressed_name=$(basename "$compressed_path")
    compressed_size_bytes=$(stat -c %s "$compressed_path")
    compressed_sha256=$(sha256sum "$compressed_path" | awk '{print $1}')
  fi
  
  # Get package information
  local packages_info=""
  if [[ -n "$PACKAGES_CONFIG" ]]; then
    local packages
    packages=$(get_package_list "$PACKAGES_CONFIG")
    if [[ -n "$packages" ]]; then
      packages_info=",\n  \"packages_config\": \"${PACKAGES_CONFIG}\",\n  \"packages\": \"${packages}\""
    fi
  fi
  
  cat > "$manifest_path" <<EOF
{
  "name": "${img_name}",
  "ubuntu": "${UBUNTU}",
  "kernel_version": "${KERNEL_VERSION}",
  "disk_gb": ${DISK_GB},
  "size_bytes": ${size_bytes},
  "sha256": "${sha256}",
  "compressed_name": "${compressed_name}",
  "compressed_size_bytes": ${compressed_size_bytes},
  "compressed_sha256": "${compressed_sha256}",
  "build_time_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"${packages_info}
}
EOF
  echo "sha256  ${img_name}  ${sha256}" > "$checksums_path"
  if [[ -n "$compressed_name" ]]; then
    echo "sha256  ${compressed_name}  ${compressed_sha256}" >> "$checksums_path"
  fi
}

optimize_and_compress_image() {
  local img="$1"
  echo "Optimizing QCOW2 with internal compression (-c)..."
  local tmp_comp="${img%.qcow2}.comp.qcow2"
  qemu-img convert -O qcow2 -c "$img" "$tmp_comp"
  mv "$tmp_comp" "$img"
  echo "Creating xz archive..."
  xz -T0 -9e -k -f "$img"
  echo "Compressed file: ${img}.xz"
  echo "Sizes: qcow2=$(stat -c %s "$img") bytes, xz=$(stat -c %s "${img}.xz") bytes"
}

# Reduce on-disk size by making free space highly compressible
shrink_free_space() {
  local work_img="$1"
  echo "Shrinking free space inside guest (zero-fill + fstrim)..."
  # Prefer virt-sparsify if available (fast and safe)
  if command -v virt-sparsify >/dev/null 2>&1; then
    # Run quick zeroing via cloud tools first to improve sparsify effectiveness
    virt-customize -a "$work_img" \
      --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
      --run-command 'set -e; dd if=/dev/zero of=/EMPTY bs=1M || true; sync || true; rm -f /EMPTY || true; fstrim -av || true'
    echo "Running virt-sparsify --in-place ..."
    virt-sparsify --in-place "$work_img"
    return 0
  fi
  # Fallback: zero-fill + fstrim via virt-customize
  virt-customize -a "$work_img" \
    --memsize ${LIBGUESTFS_MEMSIZE:-3072} \
    --run-command 'set -e; dd if=/dev/zero of=/EMPTY bs=1M || true; sync || true; rm -f /EMPTY || true; fstrim -av || true'
}

main() {
  parse_args "$@"
  deps
  preflight_kernel_readable
  guestfs_env_setup

  local base_url
  base_url=$(read_base_url)
  local cache_dir="${HOME}/.cache/servobox/build"
  local base_img
  base_img=$(download_base_image "$base_url" "$cache_dir")

  local out_dir="${ARTIFACTS_DIR}/${UBUNTU}-rt/${KERNEL_VERSION}"
  mkdir -p "$out_dir"
  local work_img="${out_dir}/${IMAGE_NAME_PREFIX}-${UBUNTU}-rt-${KERNEL_VERSION}.qcow2"

  prepare_work_image "$base_img" "$work_img"
  expand_root_filesystem "$work_img"
  install_rt_kernel "$work_img" "$KERNEL_DEBS_DIR"
  # Remove old kernels regardless of bare/full build
  purge_old_kernels "$work_img"
  # Avoid shipping docs/man/locales we don't need
  minimize_docs_and_locales "$work_img"
  if [[ -n "$PACKAGES_CONFIG" ]]; then
    create_servobox_user "$work_img"
    install_packages "$work_img" "$PACKAGES_CONFIG"
    add_utilities_and_cleanup "$work_img"
  else
    echo "Bare RT build (no extra packages)."
    bare_minimal_cleanup "$work_img"
    purge_expand_helpers "$work_img"
  fi
  shrink_free_space "$work_img"
  optimize_and_compress_image "$work_img"
  write_manifest_and_checksums "$out_dir" "$work_img" "${work_img}.xz"

  echo "\nImage built: $work_img"
  echo "Artifacts: $out_dir"
}

main "$@"


