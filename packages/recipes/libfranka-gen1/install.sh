#!/usr/bin/env bash
set -euo pipefail

# libfranka-gen1 installation script
# This script builds and installs libfranka 0.9.2 from source

echo "Installing libfranka 0.9.2 for Panda robot control..."

# Be non-interactive inside image customization
export DEBIAN_FRONTEND=noninteractive

# Source pkg-helpers for DNS configuration and timeout-wrapped apt functions
if [[ -f "${PACKAGE_HELPERS:-/tmp/pkg-helpers.sh}" ]]; then
  source "${PACKAGE_HELPERS}"
fi

# Install libfranka-specific dependencies
echo "Installing libfranka dependencies..."
# Use pkg-helpers functions if available (have DNS + timeouts), otherwise fall back to direct apt-get
if command -v apt_update >/dev/null 2>&1 && command -v apt_install >/dev/null 2>&1; then
  apt_update
  apt_install build-essential cmake git libpoco-dev libeigen3-dev
else
  apt-get update
  apt-get install -y build-essential cmake git libpoco-dev libeigen3-dev
fi

# If libfranka already installed at the desired version, skip rebuild unless FORCE=1
if dpkg-query -W -f='${Status} ${Version}\n' libfranka 2>/dev/null | awk '/installed/ {print $NF}' | grep -q '^0.9.2'; then
  if [[ "${FORCE:-0}" != "1" ]]; then
    echo "libfranka 0.9.2 already installed; skipping rebuild (set FORCE=1 to rebuild)"
    exit 0
  else
    echo "FORCE=1 specified; rebuilding libfranka 0.9.2"
  fi
fi

# Clone directly to user home directory (create if missing to be safe)
echo "Cloning libfranka to user directory..."
mkdir -p /home/servobox-usr
cd /home/servobox-usr || { echo "Error: /home/servobox-usr not available" >&2; exit 1; }

# Clone libfranka for Panda (0.9.2) — idempotent
# Note: Using version-specific directory to avoid conflicts with libfranka-fr3
# Always do a fresh clone to avoid ownership/permission issues with virt-customize
echo "Cloning libfranka repository..."
rm -rf libfranka-0.9.2
git clone --recursive https://github.com/frankaemika/libfranka libfranka-0.9.2
cd libfranka-0.9.2
echo "Checking out libfranka 0.9.2..."
git checkout 0.9.2
git submodule update --init --recursive
cd - >/dev/null

cd libfranka-0.9.2

# Create build directory and configure
echo "Building libfranka..."
rm -rf build
mkdir -p build
cd build

# Configure with CMake - install to /usr/local for proper path resolution
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DBUILD_TESTS=OFF \
      ..

# Build
cmake --build . -j$(nproc)

# Install directly to system (better than debian package for path consistency)
echo "Installing libfranka to /usr/local..."
cmake --install .

# Refresh shared library cache (critical for virt-customize environment)
ldconfig

# Copy example executables to libfranka directory
echo "Copying libfranka example executables..."
find "/home/servobox-usr/libfranka-0.9.2/build" -name "*_example" -type f -executable -exec cp {} "/home/servobox-usr/libfranka-0.9.2/" \;
find "/home/servobox-usr/libfranka-0.9.2/build" -name "*_test" -type f -executable -exec cp {} "/home/servobox-usr/libfranka-0.9.2/" \;

# Create a README with usage instructions
cat > "/home/servobox-usr/libfranka-0.9.2/README.md" << 'EOF'
# libfranka-gen1 Examples and Tests

This directory contains libfranka 0.9.2 example executables and source code for Panda robot control.

## Example Executables

The following example programs are available for testing:

- `communication_test` - Test communication with Panda robot
- `motion_generator_example` - Example motion generation
- `cartesian_impedance_control_example` - Cartesian impedance control
- `joint_impedance_control_example` - Joint impedance control
- `force_control_example` - Force control example
- `gripper_example` - Gripper control example

## Usage

1. Connect to your Panda robot via Ethernet
2. Set robot IP: `export FRANKA_IP=192.168.1.100` (replace with your robot's IP)
3. Run examples: `./communication_test` or `./motion_generator_example`

## Source Code

- `examples/` - Source code for all examples
- `tests/` - Test programs source code

## Notes

- Make sure the robot is in the correct mode (FCI mode for libfranka)
- Check robot connection before running examples
- Examples require proper robot calibration and safety setup

## Version Conflicts

**IMPORTANT**: This version (0.9.2) conflicts with libfranka-fr3 (0.16.1) at the system level.
If you install both recipes, the last one installed will be active system-wide in `/usr/local/lib`.
However, the source code and examples for each version are preserved in separate directories:
- libfranka 0.9.2 (Panda): `/home/servobox-usr/libfranka-0.9.2/`
- libfranka 0.16.1 (FR3): `/home/servobox-usr/libfranka-0.16.1/`
EOF

# Set proper ownership
chown -R servobox-usr:servobox-usr "/home/servobox-usr/libfranka-0.9.2"
chmod +x "/home/servobox-usr/libfranka-0.9.2"/*_example "/home/servobox-usr/libfranka-0.9.2"/*_test 2>/dev/null || true

echo "libfranka 0.9.2 installation completed!"
echo "libfranka is now available for Panda robot control"
echo "Examples and tests are available in: /home/servobox-usr/libfranka-0.9.2"
echo "Run 'ls /home/servobox-usr/libfranka-0.9.2' to see available examples"
echo ""
echo "NOTE: If libfranka-fr3 (0.16.1) is also installed, system libraries will be"
echo "      from whichever package was installed last. Examples remain separate."
