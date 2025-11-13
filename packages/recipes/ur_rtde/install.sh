#!/usr/bin/env bash
set -euo pipefail

# ur_rtde installation script
echo "Installing ur_rtde (Universal Robots Real-Time Data Exchange) via micromamba..."

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

# Install system-wide C++ library first
echo "Installing system-wide librtde from PPA..."
apt_update

# Add PPA repository
echo "Adding sdurobotics PPA..."
apt_install software-properties-common
add-apt-repository -y ppa:sdurobotics/ur-rtde

# Update and install librtde
apt_update
apt_install librtde librtde-dev

echo "✓ System-wide librtde installed successfully"

# Install micromamba if not found
if [[ ! -f /home/servobox-usr/.local/bin/micromamba ]]; then
    echo "micromamba not found, installing..."
    
    # Install prerequisites
    apt_install curl bzip2 ca-certificates
    
    # Install micromamba for servobox-usr
    echo "Installing micromamba for servobox-usr..."
    su - servobox-usr -c 'bash -c "$(curl -L micro.mamba.pm/install.sh)" -- -y'
    
    echo "✓ micromamba installed successfully"
else
    echo "✓ micromamba already installed"
fi

# Clean up any previous ur_rtde environments
echo "Cleaning up any existing ur_rtde environment..."
su - servobox-usr -c "
    if /home/servobox-usr/.local/bin/micromamba env list | grep -q '^ur_rtde'; then
        echo 'Removing existing ur_rtde environment...'
        /home/servobox-usr/.local/bin/micromamba env remove -n ur_rtde -y
    fi
" || true

# Create ur_rtde environment with Python 3.10
echo "Creating ur_rtde environment with Python 3.10..."
su - servobox-usr -c "
    /home/servobox-usr/.local/bin/micromamba create -n ur_rtde python=3.10 -y -c conda-forge
"

# Install ur_rtde via pip
echo "Installing ur_rtde Python package..."
if su - servobox-usr -c "
    /home/servobox-usr/.local/bin/micromamba run -n ur_rtde pip install ur_rtde
"; then
    echo "✓ ur_rtde Python package installed successfully"
else
    echo "✗ Error: ur_rtde installation failed"
    exit 1
fi

# Clone ur_rtde repository in user space
echo "Cloning ur_rtde repository..."
su - servobox-usr -c "
    cd ~
    if [ ! -d ur_rtde ]; then
        git clone https://gitlab.com/sdurobotics/ur_rtde.git
        echo '✓ ur_rtde repository cloned successfully'
    else
        echo 'ur_rtde directory already exists, updating...'
        cd ur_rtde
        git fetch origin
        git pull origin master || true
    fi
"

# Install build dependencies for C++ examples
echo "Installing build dependencies for C++ examples..."
apt_install cmake build-essential libboost-dev libboost-system-dev libboost-thread-dev

# Build C++ examples
echo "Building C++ examples..."
cd /home/servobox-usr/ur_rtde/examples/cpp

# Clean previous build if exists
if [[ -d build ]]; then
  rm -rf build
fi

mkdir -p build
cd build

# Configure with CMake (librtde is installed system-wide, so it should be found automatically)
echo "Configuring examples with CMake..."
if cmake .. -DCMAKE_BUILD_TYPE=Release; then
  echo "✓ CMake configuration successful"
else
  echo "⚠ Warning: CMake configuration failed, skipping C++ examples build"
  echo "Python bindings are still available via micromamba environment"
  cd /home/servobox-usr
fi

# Build examples
if [[ -f Makefile ]]; then
  echo "Building examples..."
  if make -j"$(nproc)"; then
    echo "✓ C++ examples built successfully"
    echo "Examples are available in: ~/ur_rtde/examples/build/"
  else
    echo "⚠ Warning: Build failed, but Python bindings are still available"
  fi
fi

# Return to home directory
cd /home/servobox-usr

# Set proper ownership
chown -R servobox-usr:servobox-usr /home/servobox-usr/ur_rtde 2>/dev/null || true

# Clean up apt cache
apt_cleanup || true

echo ""
echo "✓ ur_rtde (Universal Robots RTDE) installation complete!"
echo ""
echo "Environment: ur_rtde (micromamba)"
echo "Repository: ~/ur_rtde"
echo ""
echo "Installed components:"
echo "  - System-wide: librtde, librtde-dev (C++ library)"
echo "  - Python: ur_rtde package in micromamba environment"
echo "  - C++ examples: Built in ~/ur_rtde/examples/cpp/build/"
echo ""
echo "To use Python interface:"
echo "  micromamba activate ur_rtde"
echo "  python -c 'import rtde_control'  # Test import"
echo ""
echo "To run C++ examples:"
echo "  cd ~/ur_rtde/examples/cpp/build"
echo "  ./forcemode_example        # Force mode control"
echo "  ./move_async               # Async movement"
echo "  ./servoj                   # ServoJ control"
echo "  # ... and more"
echo ""
echo "Or run Python interactively:"
echo "  servobox run ur_rtde"
echo ""

