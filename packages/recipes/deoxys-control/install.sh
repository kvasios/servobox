#!/usr/bin/env bash
set -euo pipefail

# deoxys-control server-side installation script for Ubuntu 22.04
# This script installs dependencies and builds the server-side components (BUILD_FRANKA=1)

echo "Installing deoxys-control server-side dependencies..."

export DEBIAN_FRONTEND=noninteractive

# Ensure helpers are available when running inside image via package manager
if [[ -n "${PACKAGE_HELPERS:-}" && -f "${PACKAGE_HELPERS}" ]]; then
  # shellcheck source=/dev/null
  . "${PACKAGE_HELPERS}"
else
  # Fallback to local helpers when running directly
  if [[ -f "$(cd "$(dirname "$0")" && pwd)/scripts/pkg-helpers.sh" ]]; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "$0")" && pwd)/scripts/pkg-helpers.sh"
  fi
fi

# Verify expected home directory exists (do not create it here)
if [[ ! -d /home/servobox-usr ]]; then
  echo "Error: /home/servobox-usr does not exist" >&2
  exit 1
fi

# Refresh shared library cache
ldconfig || true

# Update package lists
apt_update || apt-get update || true

# Base build prerequisites
echo "Installing base build tools..."
apt_install build-essential cmake git pkg-config || \
  apt-get install -y build-essential cmake git pkg-config

# Protobuf (Ubuntu 22.04 has protobuf 3.20.1 in repos - sufficient for our needs)
echo "Installing protobuf..."
apt_install protobuf-compiler libprotobuf-dev libprotoc-dev || \
  apt-get install -y protobuf-compiler libprotobuf-dev libprotoc-dev

# Verify protobuf version (should be >= 3.19.0)
if command -v protoc >/dev/null 2>&1; then
  PROTOC_VER=$(protoc --version | awk '{print $2}')
  PROTOC_MAJOR=$(echo "$PROTOC_VER" | cut -d. -f1)
  PROTOC_MINOR=$(echo "$PROTOC_VER" | cut -d. -f2)
  echo "Found protoc version: $PROTOC_MAJOR.$PROTOC_MINOR"
  
  if [[ "${PROTOC_MAJOR}" -lt 3 ]] || [[ "${PROTOC_MAJOR}" -eq 3 && "${PROTOC_MINOR}" -lt 19 ]]; then
    echo "Warning: protoc version $PROTOC_MAJOR.$PROTOC_MINOR is below 3.19.0" >&2
    echo "Consider upgrading or building from source if issues occur" >&2
  fi
else
  echo "Error: protoc not found after installation" >&2
  exit 1
fi

# ZeroMQ
echo "Installing ZeroMQ..."
apt_install libzmq3-dev || apt-get install -y libzmq3-dev

# System libraries (prefer system packages, CMake will fallback to bundled if needed)
echo "Installing system libraries..."
apt_install libeigen3-dev libyaml-cpp-dev libspdlog-dev || \
  apt-get install -y libeigen3-dev libyaml-cpp-dev libspdlog-dev

# Additional dependencies
apt_install libreadline-dev bzip2 libmotif-dev libglfw3 || \
  apt-get install -y libreadline-dev bzip2 libmotif-dev libglfw3

# Clone deoxys_control dev branch into user home (shallow)
cd /home/servobox-usr
if [[ -d deoxys_control ]]; then
  echo "Updating existing deoxys_control repository..."
  cd deoxys_control
  git fetch origin dev
  git checkout dev
  git pull origin dev || true
else
  echo "Cloning deoxys_control (shallow) into /home/servobox-usr/deoxys_control..."
  git clone --depth 1 --single-branch --branch dev https://github.com/kvasios/deoxys_control.git deoxys_control
  cd deoxys_control
fi

# Initialize and update submodules (only zmqpp is required for server-side)
echo "Initializing and updating submodules..."
git submodule update --init --recursive zmqpp spdlog yaml-cpp || \
  git submodule update --init --recursive

# Ensure proper ownership
chown -R servobox-usr:servobox-usr /home/servobox-usr/deoxys_control || true

# Build zmqpp from submodule (required, not available as system package)
echo "Building zmqpp from submodule..."
cd /home/servobox-usr/deoxys_control/zmqpp || { 
  echo "Error: zmqpp submodule not found" >&2
  exit 1
}

# Clean previous build if exists
if [[ -d build ]]; then
  rm -rf build
fi

# Build zmqpp with CMake (more reliable than Makefile)
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j"$(nproc)"
make install
ldconfig
cd /home/servobox-usr/deoxys_control

# Build deoxys_control server-side components
echo "Building deoxys_control server-side (BUILD_FRANKA=1)..."
cd /home/servobox-usr/deoxys_control/deoxys || { 
  echo "Error: deoxys directory not found" >&2
  exit 1
}

# Clean previous build if exists
if [[ -d build ]]; then
  echo "Removing old build directory for clean configuration..."
  rm -rf build
fi

# Create build directory
mkdir -p build
cd build

# Configure CMake
# Note: CMakeLists.txt prefers system packages and falls back to bundled submodules
echo "Configuring CMake..."
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_FRANKA=ON \
  -DBUILD_DEOXYS=OFF \
  -DCMAKE_INSTALL_PREFIX=/usr/local

# Build (use all available cores)
echo "Building deoxys_control..."
make -j"$(nproc)"

# Install binaries
echo "Installing binaries..."
make install
ldconfig

# Ensure proper ownership
cd /home/servobox-usr/deoxys_control
chown -R servobox-usr:servobox-usr /home/servobox-usr/deoxys_control || true

# Cleanup apt caches if available via helpers
apt_cleanup || true

echo ""
echo "✓ deoxys-control server-side installation complete!"
echo ""
echo "Binaries installed to: /usr/local/bin"
echo "  - franka-interface"
echo "  - gripper-interface"
echo ""
echo "To run the server directly from Host PC:"
echo "  servobox run deoxys-control"