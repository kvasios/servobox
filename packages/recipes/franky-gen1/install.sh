#!/usr/bin/env bash
set -euo pipefail

# Franky for Franka Panda Gen1 installation script
echo "Installing Franky for Franka Panda Gen1 via micromamba..."

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

# Verify expected home directory exists
if [[ ! -d "${TARGET_HOME}" ]]; then
  mkdir -p "${TARGET_HOME}"
fi

# Install system dependencies
echo "Installing system dependencies..."
apt_update
apt_install curl wget unzip bzip2 ca-certificates

# Install micromamba if not found
if [[ ! -f ${TARGET_HOME}/.local/bin/micromamba ]]; then
    echo "micromamba not found, installing..."
    
    # Install micromamba for target user
    echo "Installing micromamba for ${TARGET_USER}..."
    su - ${TARGET_USER} -c 'bash -c "$(curl -L micro.mamba.pm/install.sh)" -- -y'
    
    echo "✓ micromamba installed successfully"
else
    echo "✓ micromamba already installed"
fi

# Clean up any previous franky-gen1 environments
echo "Cleaning up any existing franky-gen1 environment..."
su - ${TARGET_USER} -c "
    if ${TARGET_HOME}/.local/bin/micromamba env list | grep -q '^franky-gen1'; then
        echo 'Removing existing franky-gen1 environment...'
        ${TARGET_HOME}/.local/bin/micromamba env remove -n franky-gen1 -y
    fi
" || true

# Create franky-gen1 environment with Python 3.10
echo "Creating franky-gen1 environment with Python 3.10..."
su - ${TARGET_USER} -c "
    ${TARGET_HOME}/.local/bin/micromamba create -n franky-gen1 python=3.10 -y -c conda-forge
"

# Download and install franky wheels for libfranka 0.9.2
echo "Downloading franky wheels for libfranka 0.9.2..."
VERSION="0-9-2"
su - ${TARGET_USER} -c "
    cd ~
    # Clean up any previous downloads
    rm -rf libfranka_${VERSION}_wheels.zip dist
    
    # Download wheels
    wget https://github.com/TimSchneider42/franky/releases/latest/download/libfranka_${VERSION}_wheels.zip
    
    # Unzip wheels
    unzip libfranka_${VERSION}_wheels.zip
    
    echo '✓ Franky wheels downloaded and extracted'
"

# Install numpy first, then franky-control from local wheels
echo "Installing numpy and franky-control..."
if su - ${TARGET_USER} -c "
    ${TARGET_HOME}/.local/bin/micromamba run -n franky-gen1 pip install numpy &&
    ${TARGET_HOME}/.local/bin/micromamba run -n franky-gen1 pip install --no-index --find-links=~/dist franky-control
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

# Clean up downloaded files
echo "Cleaning up downloaded files..."
su - ${TARGET_USER} -c "
    cd ~
    rm -f libfranka_${VERSION}_wheels.zip
    echo '✓ Cleaned up temporary files (kept dist/ folder for reference)'
"

# Set proper ownership
chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/franky 2>/dev/null || true
chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/dist 2>/dev/null || true

# Clean up apt cache
apt_cleanup || true

echo ""
echo "✓ Franky for Franka Panda Gen1 installation complete!"
echo ""
echo "Environment: franky-gen1 (micromamba)"
echo "libfranka version: 0.9.2"
echo "Repository: ~/franky"
echo "Wheels: ~/dist"
echo ""
echo "To use:"
echo "  micromamba activate franky-gen1"
echo "  python -c 'import franky'  # Test import"
echo ""
echo "Or run interactively:"
echo "  servobox run franky-gen1"
echo ""

