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

# Verify expected home directory exists
if [[ ! -d /home/servobox-usr ]]; then
  echo "Error: /home/servobox-usr does not exist" >&2
  exit 1
fi

# Install micromamba if not found
if [[ ! -f /home/servobox-usr/.local/bin/micromamba ]]; then
    echo "micromamba not found, installing..."
    
    # Install prerequisites
    apt_update
    apt_install curl bzip2 ca-certificates
    
    # Install micromamba for servobox-usr
    echo "Installing micromamba for servobox-usr..."
    su - servobox-usr -c 'bash -c "$(curl -L micro.mamba.pm/install.sh)" -- -y'
    
    echo "✓ micromamba installed successfully"
else
    echo "✓ micromamba already installed"
fi

# Clean up any previous franky-fer environments
echo "Cleaning up any existing franky-fer environment..."
su - servobox-usr -c "
    if /home/servobox-usr/.local/bin/micromamba env list | grep -q '^franky-fer'; then
        echo 'Removing existing franky-fer environment...'
        /home/servobox-usr/.local/bin/micromamba env remove -n franky-fer -y
    fi
" || true

# Create franky-fer environment with Python 3.10
echo "Creating franky-fer environment with Python 3.10..."
su - servobox-usr -c "
    /home/servobox-usr/.local/bin/micromamba create -n franky-fer python=3.10 -y -c conda-forge
"

# Install franky-control via pip
echo "Installing franky-control..."
if su - servobox-usr -c "
    /home/servobox-usr/.local/bin/micromamba run -n franky-fer pip install franky-control
"; then
    echo "✓ franky-control installed successfully"
else
    echo "✗ Error: franky-control installation failed"
    exit 1
fi

# Clone franky repository in user space
echo "Cloning franky repository..."
su - servobox-usr -c "
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
chown -R servobox-usr:servobox-usr /home/servobox-usr/franky 2>/dev/null || true

# Clean up apt cache
apt_cleanup || true

echo ""
echo "✓ Franky for Franka Research 3 (FER) installation complete!"
echo ""
echo "Environment: franky-fer (micromamba)"
echo "Repository: ~/franky"
echo ""
echo "To use:"
echo "  micromamba activate franky-fer"
echo "  python -c 'import franky'  # Test import"
echo ""
echo "Or run interactively:"
echo "  servobox run franky-fer"
echo ""

