#!/usr/bin/env bash
set -euo pipefail

# libfranka-fr3 installation script
# This script builds and installs libfranka 0.16.1 from source with all dependencies

echo "Installing libfranka 0.16.1 for FR3 robot control..."

# Be non-interactive inside image customization
export DEBIAN_FRONTEND=noninteractive

# Install libfranka-specific dependencies
echo "Installing libfranka dependencies..."
apt-get update
apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    libpoco-dev \
    libeigen3-dev \
    libnlopt-dev \
    libccd-dev \
    libfcl-dev \
    liburdfdom-dev \
    liburdfdom-headers-dev \
    liboctomap-dev \
    libboost-all-dev \
    libfmt-dev

# If libfranka already installed at the desired version, skip rebuild unless FORCE=1
if dpkg-query -W -f='${Status} ${Version}\n' libfranka 2>/dev/null | awk '/installed/ {print $NF}' | grep -q '^0.16.1'; then
  if [[ "${FORCE:-0}" != "1" ]]; then
    echo "libfranka 0.16.1 already installed; skipping rebuild (set FORCE=1 to rebuild)"
    exit 0
  else
    echo "FORCE=1 specified; rebuilding libfranka 0.16.1"
  fi
fi

###### Pinocchio dependency handled by separate recipe ######
echo "Verifying Pinocchio availability via pkg-config..."
if ! pkg-config --exists pinocchio; then
  echo "ERROR: Pinocchio not found. Please install the 'pinocchio' recipe first." >&2
  echo "       Run: ./servobox pkg-install pinocchio" >&2
  exit 1
fi

# Setup home directory for libfranka build
echo "Setting up build directories..."
mkdir -p /home/servobox-usr
cd /home/servobox-usr || { echo "Error: /home/servobox-usr not available" >&2; exit 1; }

###### Build libfranka 0.16.1 ######
echo "Building libfranka 0.16.1..."
# Note: Using version-specific directory to avoid conflicts with libfranka-gen1
# Always do a fresh clone to avoid ownership/permission issues with virt-customize
echo "Cloning libfranka repository..."
rm -rf libfranka-0.16.1
git clone --recursive https://github.com/frankaemika/libfranka libfranka-0.16.1
cd libfranka-0.16.1
echo "Checking out libfranka 0.16.1..."
git checkout 0.16.1
git submodule update --init --recursive
cd - >/dev/null

cd libfranka-0.16.1

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

# Refresh shared library cache
ldconfig

# Copy example executables to libfranka directory
echo "Copying libfranka example executables..."
find "/home/servobox-usr/libfranka-0.16.1/build" -name "*_example" -type f -executable -exec cp {} "/home/servobox-usr/libfranka-0.16.1/" \; 2>/dev/null || true
find "/home/servobox-usr/libfranka-0.16.1/build" -name "*_test" -type f -executable -exec cp {} "/home/servobox-usr/libfranka-0.16.1/" \; 2>/dev/null || true

# Setup realtime group and limits
echo "Setting up realtime group and limits..."
if ! getent group realtime >/dev/null; then
  groupadd realtime
fi

# Add servobox-usr to realtime group
usermod -a -G realtime servobox-usr

# Add realtime limits if not already present
if ! grep -q "@realtime soft rtprio" /etc/security/limits.conf; then
  sed -i '/# End of file/i @realtime soft rtprio 99\n@realtime soft priority 99\n@realtime soft memlock 102400\n@realtime hard rtprio 99\n@realtime hard priority 99\n@realtime hard memlock 102400' /etc/security/limits.conf
fi

# Create a README with usage instructions
cat > "/home/servobox-usr/libfranka-0.16.1/README.md" << 'EOF'
# libfranka-fr3 Examples and Tests

This directory contains libfranka 0.16.1 example executables and source code for FR3 robot control.

## Example Executables

The following example programs are available for testing:

- `communication_test` - Test communication with FR3 robot
- `motion_generator_example` - Example motion generation
- `cartesian_impedance_control_example` - Cartesian impedance control
- `joint_impedance_control_example` - Joint impedance control
- `force_control_example` - Force control example
- `gripper_example` - Gripper control example

## Usage

1. Connect to your FR3 robot via Ethernet
2. Set robot IP: `export FRANKA_IP=192.168.1.100` (replace with your robot's IP)
3. Run examples: `./communication_test` or `./motion_generator_example`

## Dependencies

This installation includes:
- Pinocchio (via robotpkg) - Rigid body dynamics library (optional, may not install on all systems)
- libfranka 0.16.1 - Franka Emika robot control library

**Note**: Pinocchio installation may fail on some Ubuntu versions due to dependency conflicts with casadi/coinor-libipopt.
If Pinocchio is not required for your use case, libfranka will still function normally.

## Source Code

- `examples/` - Source code for all examples
- `tests/` - Test programs source code

## Notes

- Make sure the robot is in the correct mode (FCI mode for libfranka)
- Check robot connection before running examples
- Examples require proper robot calibration and safety setup
- Your user must be in the 'realtime' group for real-time performance

## Version Conflicts

**IMPORTANT**: This version (0.16.1) conflicts with libfranka-gen1 (0.9.2) at the system level.
If you install both recipes, the last one installed will be active system-wide in `/usr/local/lib`.
However, the source code and examples for each version are preserved in separate directories:
- libfranka 0.9.2 (Panda): `/home/servobox-usr/libfranka-0.9.2/`
- libfranka 0.16.1 (FR3): `/home/servobox-usr/libfranka-0.16.1/`
EOF

# Set proper ownership
chown -R servobox-usr:servobox-usr "/home/servobox-usr/libfranka-0.16.1"
chown servobox-usr:servobox-usr "/home/servobox-usr/.bashrc"
chmod +x "/home/servobox-usr/libfranka-0.16.1"/*_example "/home/servobox-usr/libfranka-0.16.1"/*_test 2>/dev/null || true

echo "libfranka 0.16.1 installation completed!"
echo "libfranka is now available for FR3 robot control"
echo "Examples and tests are available in: /home/servobox-usr/libfranka-0.16.1"
echo "Run 'ls /home/servobox-usr/libfranka-0.16.1' to see available examples"
echo ""
echo ""
echo "NOTE: If libfranka-gen1 (0.9.2) is also installed, system libraries will be"
echo "      from whichever package was installed last. Examples remain separate."

