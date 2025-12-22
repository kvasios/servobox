#!/usr/bin/env bash
set -euo pipefail

# Franky Remote for Franka Research 3 installation script
echo "Installing Franky Remote for Franka Research 3..."

export DEBIAN_FRONTEND=noninteractive

# Load helper functions if available
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

# Determine target user and home directory
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
[[ "${TARGET_USER}" == "root" ]] && TARGET_HOME="/root" || TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
[[ -z "${TARGET_HOME}" ]] && TARGET_HOME="/home/${TARGET_USER}"
echo "Installing for user: ${TARGET_USER} (home: ${TARGET_HOME})"
mkdir -p "${TARGET_HOME}"

# Clone franky-remote repository in user space
echo "Cloning franky-remote repository..."
su - ${TARGET_USER} -c "
    cd ~
    if [ ! -d franky-remote ]; then
        git clone https://github.com/kvasios/franky-remote.git
        echo '✓ franky-remote repository cloned successfully'
    else
        echo 'franky-remote directory already exists, updating...'
        cd franky-remote
        git fetch origin
        git pull origin main || true
    fi
"

# Install rpyc in the existing franky-fr3 environment
echo "Installing rpyc in franky-fr3 environment..."
if su - ${TARGET_USER} -c "
    ${TARGET_HOME}/.local/bin/micromamba run -n franky-fr3 pip install rpyc
"; then
    echo "✓ rpyc installed successfully"
else
    echo "✗ Error: rpyc installation failed"
    exit 1
fi

# Set proper ownership
chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/franky-remote 2>/dev/null || true

echo ""
echo "✓ Franky Remote for Franka Research 3 installation complete!"
echo ""
