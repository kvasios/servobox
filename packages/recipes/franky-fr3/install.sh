#!/usr/bin/env bash
set -euo pipefail

# Franky for Franka Research 3 (FER) installation script
echo "Installing Franky for Franka Research 3 (FER) via micromamba..."

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

# Install micromamba if not found
if [[ ! -f ${TARGET_HOME}/.local/bin/micromamba ]]; then
    echo "micromamba not found, installing..."
    
    # Install prerequisites
    apt_update
    apt_install curl bzip2 ca-certificates
    
    # Install micromamba for target user
    echo "Installing micromamba for ${TARGET_USER}..."
    su - ${TARGET_USER} -c 'bash -c "$(curl -L micro.mamba.pm/install.sh)" -- -y'
    
    echo "✓ micromamba installed successfully"
else
    echo "✓ micromamba already installed"
fi

# Clean up any previous franky-fr3 environments
echo "Cleaning up any existing franky-fr3 environment..."
su - ${TARGET_USER} -c "
    if ${TARGET_HOME}/.local/bin/micromamba env list | grep -q '^franky-fr3'; then
        echo 'Removing existing franky-fr3 environment...'
        ${TARGET_HOME}/.local/bin/micromamba env remove -n franky-fr3 -y
    fi
" || true

# Create franky-fr3 environment with Python 3.10
echo "Creating franky-fr3 environment with Python 3.10..."
su - ${TARGET_USER} -c "
    ${TARGET_HOME}/.local/bin/micromamba create -n franky-fr3 python=3.10 -y -c conda-forge
"

# Install franky-control via pip
echo "Installing franky-control..."
if su - ${TARGET_USER} -c "
    ${TARGET_HOME}/.local/bin/micromamba run -n franky-fr3 pip install franky-control
"; then
    echo "✓ franky-control installed successfully"
else
    echo "✗ Error: franky-control installation failed"
    exit 1
fi

# Clone franky repository in user space
echo "Cloning franky repository..."
su - ${TARGET_USER} -c "
    cd ~
    if [ ! -d franky ]; then
        git clone https://github.com/TimSchneider42/franky.git
        echo '✓ franky repository cloned successfully'
    else
        echo 'franky directory already exists, updating...'
        cd franky
        git fetch origin
        git pull origin master || true
    fi
"

# Set proper ownership
chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/franky 2>/dev/null || true

# Clean up apt cache
apt_cleanup || true

echo ""
echo "✓ Franky for Franka Research 3 (FER) installation complete!"
echo ""
echo "Environment: franky-fr3 (micromamba)"
echo "Repository: ~/franky"
echo ""
echo "To use:"
echo "  micromamba activate franky-fr3"
echo "  python -c 'import franky'  # Test import"
echo ""
echo "Or run interactively:"
echo "  servobox run franky-fr3"
echo ""

