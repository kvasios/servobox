#!/usr/bin/env bash
set -euo pipefail

# Franky Remote for Franka Panda Gen1 installation script
echo "Installing Franky Remote for Franka Panda Gen1..."

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

# Clone franky-remote repository in user space
echo "Cloning franky-remote repository..."
su - servobox-usr -c "
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

# Install rpyc in the existing franky-gen1 environment
echo "Installing rpyc in franky-gen1 environment..."
if su - servobox-usr -c "
    /home/servobox-usr/.local/bin/micromamba run -n franky-gen1 pip install rpyc
"; then
    echo "✓ rpyc installed successfully"
else
    echo "✗ Error: rpyc installation failed"
    exit 1
fi

# Set proper ownership
chown -R servobox-usr:servobox-usr /home/servobox-usr/franky-remote 2>/dev/null || true

echo ""
echo "✓ Franky Remote for Franka Panda Gen1 installation complete!"
echo ""

