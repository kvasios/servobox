#!/usr/bin/env bash
# Common utilities shared across ServoBox library files

# Smart virsh wrapper: uses sudo only if we can't connect to libvirt
# Always connects to qemu:///system for persistence
# Tests actual connectivity rather than group membership (groups command is session-specific)
virsh_cmd() {
  # Try without sudo first - if it works, we have access
  if virsh -c qemu:///system version >/dev/null 2>&1; then
    virsh -c qemu:///system "$@"
  else
    # Need sudo for access
    sudo virsh -c qemu:///system "$@"
  fi
}

# Check if a command exists
have() { 
  command -v "$1" >/dev/null 2>&1
}

# Ensure host KVM device permissions work with libvirt's QEMU user.
# This fixes a common regression where /dev/kvm ends up in group "plugdev",
# which prevents libvirt (running QEMU as libvirt-qemu) from using hardware accel.
#
# Behavior:
# - If /dev/kvm is missing: return non-zero with a clear error.
# - If /dev/kvm perms are wrong: install a persistent udev rule (requires sudo),
#   reload rules, and apply perms immediately.
# - Can be disabled via SERVOBOX_SKIP_KVM_FIX=1 (useful for restricted environments).
servobox_detect_qemu_user() {
  local u
  # Allow explicit override for unusual setups.
  if [[ -n "${SERVOBOX_QEMU_USER:-}" ]]; then
    echo "${SERVOBOX_QEMU_USER}"
    return 0
  fi
  for u in libvirt-qemu qemu; do
    if getent passwd "${u}" >/dev/null 2>&1; then
      echo "${u}"
      return 0
    fi
  done
  return 1
}

servobox_require_sudo() {
  # Prefer non-interactive sudo if already authorized; otherwise prompt once.
  if sudo -n true >/dev/null 2>&1; then
    return 0
  fi
  sudo -v
}

ensure_kvm_device_permissions() {
  if [[ "${SERVOBOX_SKIP_KVM_FIX:-0}" == "1" ]]; then
    return 0
  fi

  if [[ ! -e /dev/kvm ]]; then
    echo "Error: /dev/kvm not found. KVM acceleration is unavailable on this host." >&2
    echo "Check BIOS/UEFI virtualization (VT-x/AMD-V), then ensure modules are loaded:" >&2
    echo "  sudo modprobe kvm && (sudo modprobe kvm_intel || sudo modprobe kvm_amd)" >&2
    return 1
  fi

  # Expected defaults on Ubuntu/Debian-style libvirt installs.
  local want_owner="root"
  local want_group="kvm"
  local want_mode="660"

  local cur_owner cur_group cur_mode
  cur_owner=$(stat -c '%U' /dev/kvm 2>/dev/null || echo "")
  cur_group=$(stat -c '%G' /dev/kvm 2>/dev/null || echo "")
  cur_mode=$(stat -c '%a' /dev/kvm 2>/dev/null || echo "")

  # Fast path: looks correct.
  if [[ "${cur_owner}" == "${want_owner}" && "${cur_group}" == "${want_group}" && "${cur_mode}" == "${want_mode}" ]]; then
    return 0
  fi

  echo "Host KVM device permissions look wrong: /dev/kvm is ${cur_owner:-?}:${cur_group:-?} mode ${cur_mode:-?} (expected ${want_owner}:${want_group} mode ${want_mode})." >&2
  echo "Fixing this so libvirt can start VMs with hardware acceleration..." >&2

  servobox_require_sudo >/dev/null 2>&1 || {
    echo "Error: sudo is required to fix /dev/kvm permissions." >&2
    return 1
  }

  # Ensure QEMU runtime user is in the kvm group (usually already true).
  local qemu_user
  qemu_user=$(servobox_detect_qemu_user 2>/dev/null || echo "")
  if [[ -n "${qemu_user}" ]]; then
    if ! id -nG "${qemu_user}" 2>/dev/null | grep -qw "${want_group}"; then
      sudo usermod -aG "${want_group}" "${qemu_user}" >/dev/null 2>&1 || true
    fi
  fi

  # Persistent fix via udev rule.
  local rule_path="/etc/udev/rules.d/99-kvm-permissions.rules"
  sudo install -d -m 0755 /etc/udev/rules.d >/dev/null 2>&1 || true
  sudo tee "${rule_path}" >/dev/null <<'EOF'
SUBSYSTEM=="misc", KERNEL=="kvm", GROUP="kvm", MODE="0660"
EOF

  sudo udevadm control --reload-rules >/dev/null 2>&1 || true
  sudo udevadm trigger --subsystem-match=misc --sysname-match=kvm >/dev/null 2>&1 || true

  # Apply immediately for the current session, even if udev trigger is delayed.
  sudo chown root:kvm /dev/kvm >/dev/null 2>&1 || true
  sudo chmod 0660 /dev/kvm >/dev/null 2>&1 || true

  # Re-check and hard-fail if still wrong: better to surface clearly than fail at VM start.
  cur_owner=$(stat -c '%U' /dev/kvm 2>/dev/null || echo "")
  cur_group=$(stat -c '%G' /dev/kvm 2>/dev/null || echo "")
  cur_mode=$(stat -c '%a' /dev/kvm 2>/dev/null || echo "")
  if [[ "${cur_owner}" != "${want_owner}" || "${cur_group}" != "${want_group}" || "${cur_mode}" != "${want_mode}" ]]; then
    echo "Error: failed to fix /dev/kvm permissions (now ${cur_owner:-?}:${cur_group:-?} mode ${cur_mode:-?})." >&2
    echo "Expected: ${want_owner}:${want_group} mode ${want_mode}. Check for conflicting udev rules." >&2
    return 1
  fi

  echo "✓ Fixed KVM device permissions (persistent udev rule installed at ${rule_path})." >&2
  return 0
}

