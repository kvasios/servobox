#!/usr/bin/env bash
set -euo pipefail

# Polymetis installation script - simplified micromamba approach
echo "Installing Polymetis via micromamba..."

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

# Install micromamba if not found
if [[ ! -f ${TARGET_HOME}/.local/bin/micromamba ]]; then
    echo "micromamba not found, installing..."
    
    # Install prerequisites
    apt_update
    apt_install curl bzip2 ca-certificates
    
    # Install micromamba for target user
    echo "Installing micromamba for ${TARGET_USER}..."
    su - ${TARGET_USER} -c 'bash -c "$(curl -L micro.mamba.pm/install.sh)" -- -y'
    
    echo "micromamba installed successfully"
else
    echo "micromamba already installed"
fi

# Clean up any previous polymetis environments
echo "Cleaning up any existing polymetis environments..."
su - ${TARGET_USER} -c "
    if ${TARGET_HOME}/.local/bin/micromamba env list | grep -q polymetis; then
        echo 'Removing existing polymetis environment...'
        ${TARGET_HOME}/.local/bin/micromamba env remove -n polymetis -y
    fi
" || true

# Install system dependencies for OpenGL
echo "Installing system dependencies..."
apt_update
apt_install libgl1-mesa-glx libglib2.0-0

# Polymetis conda packages are x86_64 only. Build-from-source on aarch64 hits
# dependency mismatches (protobuf/grpc versions, C++14 vs C++17) and the
# fairo/polymetis repo has been archived since 2023.
ARCH=$(uname -m)
if [[ "${ARCH}" != "x86_64" ]]; then
  echo ""
  echo "Polymetis is not supported on ${ARCH} (Jetson/ARM)."
  echo ""
  echo "  • Conda packages: x86_64 only"
  echo "  • Build from source: has known protobuf/grpc/C++ compatibility issues"
  echo ""
  echo "Use a ServoBox x86_64 VM (pkg-install without remote target) for polymetis."
  echo "For manual aarch64 attempts: https://facebookresearch.github.io/fairo/polymetis/installation.html"
  echo ""
  exit 1
fi

# === x86_64: install from conda packages ===
echo "Setting up polymetis environment from exported specification..."
cp "${RECIPE_DIR}/polymetis-env.yml" ${TARGET_HOME}/
chown ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/polymetis-env.yml

echo "Installing polymetis via micromamba using exported environment..."
if ! su - ${TARGET_USER} -c "
  ${TARGET_HOME}/.local/bin/micromamba env create -f polymetis-env.yml --channel-priority flexible
"; then
  echo "YML approach failed, trying spec.txt approach..."
  cp "${RECIPE_DIR}/polymetis-spec.txt" ${TARGET_HOME}/
  chown ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/polymetis-spec.txt

  su - ${TARGET_USER} -c "
    ${TARGET_HOME}/.local/bin/micromamba create -n polymetis --file polymetis-spec.txt
  "
fi

echo "Cloning fairo repository for scripts and examples..."
su - ${TARGET_USER} -c "
  cd ~
  if [ ! -d fairo ]; then
    git clone https://github.com/facebookresearch/fairo.git
    echo '✓ fairo repository cloned successfully'
  else
    echo 'fairo directory already exists, skipping clone...'
  fi
"

echo "Fixing polymetis version detection..."
su - ${TARGET_USER} -c "
  ${TARGET_HOME}/.local/bin/micromamba run -n polymetis python -c '
import os
import site
site_packages = site.getsitepackages()[0]
version_file = os.path.join(site_packages, \"polymetis\", \"_version.py\")
# Create a simple version file that just returns a version
with open(version_file, \"w\") as f:
  f.write(\"__version__ = \\\"0.2\\\"\\n\")
print(\"✓ Fixed polymetis version detection\")
'
"

# Verify installation
echo "Verifying Polymetis installation..."
if su - ${TARGET_USER} -c "${TARGET_HOME}/.local/bin/micromamba run -n polymetis python -c 'import polymetis; print(\"✓ polymetis imported successfully\")'" 2>/dev/null; then
    echo "✓ polymetis Python package installed successfully"
else
    echo "✗ Error: polymetis Python package verification failed"
    exit 1
fi

# Create environment setup script
echo "Creating environment setup script..."
cat > ${TARGET_HOME}/activate_polymetis.sh << EOF
#!/bin/bash
# Polymetis environment activation script

# Activate conda environment
source ${TARGET_HOME}/.local/bin/micromamba activate polymetis

echo "Polymetis environment activated!"
echo "Python version: \$(python --version)"
echo "Polymetis version: \$(python -c 'import polymetis; print(polymetis.__version__)' 2>/dev/null || echo 'unknown')"
EOF

chown ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/activate_polymetis.sh
chmod +x ${TARGET_HOME}/activate_polymetis.sh

echo ""
echo "Polymetis installation completed!"
echo ""
echo "Environment: polymetis (conda)"
echo ""
echo "To use:"
echo "  source ~/activate_polymetis.sh"
echo "  python -c 'import polymetis'  # Test import"
echo ""

apt_cleanup