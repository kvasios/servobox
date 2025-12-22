#!/usr/bin/env bash
set -euo pipefail

# RoboStack with micromamba installation script
echo "Installing micromamba for RoboStack..."

export DEBIAN_FRONTEND=noninteractive

# Prefer helper injected by the package manager when customizing images
if [[ -n "${PACKAGE_HELPERS:-}" && -f "${PACKAGE_HELPERS}" ]]; then
  # shellcheck source=/dev/null
  . "${PACKAGE_HELPERS}"
else
  # Fallback to repo-relative helper for local execution
  if [[ -f "$(cd "$(dirname "$0")/../.." && pwd)/scripts/pkg-helpers.sh" ]]; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "$0")/../.." && pwd)/scripts/pkg-helpers.sh"
  fi
fi

# Check if already installed (optional - package manager handles this, but good for local testing)
if is_package_installed "${PACKAGE_NAME:-robostack}"; then
    echo "Package ${PACKAGE_NAME:-robostack} is already installed, skipping..."
    exit 0
fi

# Install prerequisites
apt_update
apt_install curl bzip2 ca-certificates

# Determine target user
if [[ -n "${SERVOBOX_INSTALL_USER:-}" ]]; then
  TARGET_USER="${SERVOBOX_INSTALL_USER}"
elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="${SUDO_USER}"
elif id "servobox-usr" &>/dev/null; then
  TARGET_USER="servobox-usr"
else
  TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home/ {print $1; exit}')
  [[ -z "${TARGET_USER}" ]] && TARGET_USER="root"
fi
echo "Installing for user: ${TARGET_USER}"

# Install micromamba for target user
# The -y flag tells the installer to:
# 1. Install to ~/.local/bin/micromamba
# 2. Run shell init automatically
# 3. Configure conda-forge channels
if su - ${TARGET_USER} -c 'command -v micromamba' &>/dev/null; then
    echo "micromamba already exists for ${TARGET_USER}, skipping installation..."
else
    echo "Installing micromamba for ${TARGET_USER}..."
    su - ${TARGET_USER} -c 'bash -c "$(curl -L micro.mamba.pm/install.sh)" -- -y'
fi

# Install micromamba for root as well
if su - root -c 'command -v micromamba' &>/dev/null; then
    echo "micromamba already exists for root, skipping installation..."
else
    echo "Installing micromamba for root..."
    su - root -c 'bash -c "$(curl -L micro.mamba.pm/install.sh)" -- -y'
fi

# Mark package as installed (package manager will also do this, but good for consistency)
mark_package_installed "${PACKAGE_NAME:-robostack}"

echo ""
echo "Micromamba for RoboStack installation completed!"
echo ""
echo "Usage:"
echo "  micromamba activate                    # Activate base environment"
echo "  micromamba create -n myenv ...         # Create a new environment"
echo ""
echo "Example - Create ROS environment:"
echo "  micromamba create -n ros_env -c conda-forge -c robostack-humble ros-humble-desktop"
echo ""

apt_cleanup

