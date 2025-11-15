#!/usr/bin/env bash
set -euo pipefail

# geoik-velctrl installation script
# This script builds and installs geoik-velctrl velocity control server

echo "Installing geoik-velctrl velocity control server..."

# Be non-interactive inside image customization
export DEBIAN_FRONTEND=noninteractive

# Source pkg-helpers for DNS configuration and timeout-wrapped apt functions
if [[ -f "${PACKAGE_HELPERS:-/tmp/pkg-helpers.sh}" ]]; then
  source "${PACKAGE_HELPERS}"
fi

# Install dependencies
echo "Installing geoik-velctrl dependencies..."
# Use pkg-helpers functions if available (have DNS + timeouts), otherwise fall back to direct apt-get
if command -v apt_update >/dev/null 2>&1 && command -v apt_install >/dev/null 2>&1; then
  apt_update
  apt_install build-essential cmake git libeigen3-dev
else
  apt-get update
  apt-get install -y build-essential cmake git libeigen3-dev
fi

# Install ruckig motion generation library
echo "Installing ruckig library..."
RUCKIG_VERSION="0.9.2"
if [[ ! -d "/usr/local/include/ruckig" ]] || [[ "${FORCE:-0}" == "1" ]]; then
  cd /tmp
  rm -rf ruckig
  git clone --depth 1 --branch v${RUCKIG_VERSION} https://github.com/pantor/ruckig.git
  cd ruckig
  mkdir -p build
  cd build
  cmake -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        ..
  cmake --build . -j$(nproc)
  cmake --install .
  ldconfig
  cd /tmp
  rm -rf ruckig
  echo "ruckig ${RUCKIG_VERSION} installed successfully"
else
  echo "ruckig already installed; skipping (set FORCE=1 to rebuild)"
fi

# Create user home directory if missing
echo "Setting up project directory..."
mkdir -p /home/servobox-usr
cd /home/servobox-usr || { echo "Error: /home/servobox-usr not available" >&2; exit 1; }

# Clone geoik-velctrl from GitHub
echo "Cloning geoik-velctrl repository..."
PROJECT_DIR="/home/servobox-usr/geoik-velctrl"
rm -rf "${PROJECT_DIR}"
git clone https://github.com/kvasios/geoik-velctrl.git "${PROJECT_DIR}"
cd "${PROJECT_DIR}"

# Create build directory and configure
echo "Building geoik-velctrl..."
rm -rf build
mkdir -p build
cd build

# Configure with CMake
# libfranka is installed to /usr/local by the libfranka-gen1 dependency
cmake -DCMAKE_BUILD_TYPE=Release \
      -DFRANKA_INSTALL_PATH=/usr/local \
      ..

# Build
cmake --build . -j$(nproc)

# Copy executable to project root for easy access
echo "Copying executable to project directory..."
cp franka_velocity_server "${PROJECT_DIR}/"

# Create a README with usage instructions
cat > "${PROJECT_DIR}/USAGE.md" << 'EOF'
# geoik-velctrl - Geometric IK-based Velocity Control Server

This directory contains the geoik-velctrl velocity control server for Franka robots.

## Executable

- `franka_velocity_server` - Main velocity control server

## Usage

The velocity server accepts commands via UDP and translates them to robot motion:

```bash
# Run the velocity server (connect to robot at 172.16.0.2)
./franka_velocity_server 172.16.0.2
```

## Network Architecture

- **Server** listens on UDP port 8888 for pose commands
- **Server** connects to Franka robot at 172.16.0.2
- **Client** (e.g., marker_track.py) sends commands to server IP (e.g., 192.168.122.100:8888)

## Command Protocol

The server listens on UDP port 8888 for pose commands in the format:
```
x y z qx qy qz qw
```
Where:
- `x y z`: Position in meters (robot base frame)
- `qx qy qz qw`: Orientation quaternion

## Build

To rebuild the project:

```bash
cd build
cmake --build .
```

## Notes

- Ensure the robot is in FCI mode and properly configured
- Check network connectivity to the robot
- The server requires real-time priority for optimal performance
- Make sure libfranka is properly installed and accessible

## Dependencies

- libfranka (0.9.2 or compatible)
- Eigen3
- ruckig (motion generation)
- pthreads
EOF

# Set proper ownership
chown -R servobox-usr:servobox-usr "${PROJECT_DIR}"
chmod +x "${PROJECT_DIR}/franka_velocity_server"

echo "geoik-velctrl installation completed!"
echo "Velocity control server is available at: ${PROJECT_DIR}/franka_velocity_server"
echo "Run './franka_velocity_server <robot-ip>' to start the server"
echo ""
echo "See ${PROJECT_DIR}/USAGE.md for detailed usage instructions"
