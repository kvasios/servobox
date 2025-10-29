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

# Install micromamba if not found
if [[ ! -f /home/servobox-usr/.local/bin/micromamba ]]; then
    echo "micromamba not found, installing..."
    
    # Install prerequisites
    apt_update
    apt_install curl bzip2 ca-certificates
    
    # Install micromamba for servobox-usr
    echo "Installing micromamba for servobox-usr..."
    su - servobox-usr -c 'bash -c "$(curl -L micro.mamba.pm/install.sh)" -- -y'
    
    echo "micromamba installed successfully"
else
    echo "micromamba already installed"
fi

# Clean up any previous polymetis environments
echo "Cleaning up any existing polymetis environments..."
su - servobox-usr -c "
    if /home/servobox-usr/.local/bin/micromamba env list | grep -q polymetis; then
        echo 'Removing existing polymetis environment...'
        /home/servobox-usr/.local/bin/micromamba env remove -n polymetis -y
    fi
" || true

# Install system dependencies for OpenGL
echo "Installing system dependencies..."
apt_update
apt_install libgl1-mesa-glx libglib2.0-0

# Try the .yml file first with flexible channel priority
echo "Setting up polymetis environment from exported specification..."
cp "${RECIPE_DIR}/polymetis-env.yml" /home/servobox-usr/
chown servobox-usr:servobox-usr /home/servobox-usr/polymetis-env.yml

# Install polymetis using the exported environment file with flexible channel priority
echo "Installing polymetis via micromamba using exported environment..."
if ! su - servobox-usr -c "
    /home/servobox-usr/.local/bin/micromamba env create -f polymetis-env.yml --channel-priority flexible
"; then
    echo "YML approach failed, trying spec.txt approach..."
    # Fallback to spec.txt file
    cp "${RECIPE_DIR}/polymetis-spec.txt" /home/servobox-usr/
    chown servobox-usr:servobox-usr /home/servobox-usr/polymetis-spec.txt
    
    su - servobox-usr -c "
        /home/servobox-usr/.local/bin/micromamba create -n polymetis --file polymetis-spec.txt
    "
fi

# Clone fairo repository for scripts and examples
echo "Cloning fairo repository for scripts and examples..."
su - servobox-usr -c "
    cd ~
    if [ ! -d fairo ]; then
        git clone https://github.com/facebookresearch/fairo.git
        echo '✓ fairo repository cloned successfully'
    else
        echo 'fairo directory already exists, skipping clone...'
    fi
"

# Fix polymetis version detection issue
echo "Fixing polymetis version detection..."
su - servobox-usr -c "
    /home/servobox-usr/.local/bin/micromamba run -n polymetis python -c '
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
if su - servobox-usr -c "/home/servobox-usr/.local/bin/micromamba run -n polymetis python -c 'import polymetis; print(\"✓ polymetis imported successfully\")'" 2>/dev/null; then
    echo "✓ polymetis Python package installed successfully"
else
    echo "✗ Error: polymetis Python package verification failed"
    exit 1
fi

# Create environment setup script
echo "Creating environment setup script..."
cat > /home/servobox-usr/activate_polymetis.sh << 'EOF'
#!/bin/bash
# Polymetis environment activation script

# Activate conda environment
source /home/servobox-usr/.local/bin/micromamba activate polymetis

echo "Polymetis environment activated!"
echo "Python version: $(python --version)"
echo "Polymetis version: $(python -c 'import polymetis; print(polymetis.__version__)' 2>/dev/null || echo 'unknown')"
EOF

chown servobox-usr:servobox-usr /home/servobox-usr/activate_polymetis.sh
chmod +x /home/servobox-usr/activate_polymetis.sh

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