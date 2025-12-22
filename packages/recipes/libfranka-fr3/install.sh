#!/usr/bin/env bash
set -euo pipefail

# libfranka-fr3 installation script
# This script builds and installs libfranka 0.16.1 from source with all dependencies

echo "Installing libfranka 0.16.1 for FR3 robot control..."

# Be non-interactive inside image customization
export DEBIAN_FRONTEND=noninteractive

# Determine target user and home directory
# Priority: SERVOBOX_INSTALL_USER > SUDO_USER > servobox-usr > first non-root user
if [[ -n "${SERVOBOX_INSTALL_USER:-}" ]]; then
  TARGET_USER="${SERVOBOX_INSTALL_USER}"
elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="${SUDO_USER}"
elif id "servobox-usr" &>/dev/null; then
  TARGET_USER="servobox-usr"
else
  TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home/ {print $1; exit}')
  if [[ -z "${TARGET_USER}" ]]; then
    TARGET_USER="root"
  fi
fi
if [[ "${TARGET_USER}" == "root" ]]; then
  TARGET_HOME="/root"
else
  TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
  [[ -z "${TARGET_HOME}" ]] && TARGET_HOME="/home/${TARGET_USER}"
fi
echo "Installing for user: ${TARGET_USER} (home: ${TARGET_HOME})"

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
mkdir -p "${TARGET_HOME}"
cd "${TARGET_HOME}" || { echo "Error: ${TARGET_HOME} not available" >&2; exit 1; }

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
find "${TARGET_HOME}/libfranka-0.16.1/build" -name "*_example" -type f -executable -exec cp {} "${TARGET_HOME}/libfranka-0.16.1/" \; 2>/dev/null || true
find "${TARGET_HOME}/libfranka-0.16.1/build" -name "*_test" -type f -executable -exec cp {} "${TARGET_HOME}/libfranka-0.16.1/" \; 2>/dev/null || true

# Setup realtime group and limits
echo "Setting up realtime group and limits..."
if ! getent group realtime >/dev/null; then
  groupadd realtime
fi

# Add target user to realtime group
usermod -a -G realtime "${TARGET_USER}"

# Add realtime limits if not already present
if ! grep -q "@realtime soft rtprio" /etc/security/limits.conf; then
  sed -i '/# End of file/i @realtime soft rtprio 99\n@realtime soft priority 99\n@realtime soft memlock 102400\n@realtime hard rtprio 99\n@realtime hard priority 99\n@realtime hard memlock 102400' /etc/security/limits.conf
fi

# Create a README with usage instructions
cat > "${TARGET_HOME}/libfranka-0.16.1/README.md" << EOF
# libfranka-fr3 Examples and Tests

This directory contains libfranka 0.16.1 example executables and source code for FR3 robot control.

## Example Executables

- \`communication_test\` - Test communication with FR3 robot
- \`motion_generator_example\` - Example motion generation
- \`cartesian_impedance_control_example\` - Cartesian impedance control
- \`joint_impedance_control_example\` - Joint impedance control
- \`force_control_example\` - Force control example
- \`gripper_example\` - Gripper control example

## Usage

1. Connect to your FR3 robot via Ethernet
2. Set robot IP: \`export FRANKA_IP=192.168.1.100\`
3. Run examples: \`./communication_test\`

## Notes

- Your user must be in the 'realtime' group for real-time performance
EOF

# Set proper ownership
if [[ "${TARGET_USER}" != "root" ]]; then
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/libfranka-0.16.1"
  chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.bashrc" 2>/dev/null || true
fi
chmod +x "${TARGET_HOME}/libfranka-0.16.1"/*_example "${TARGET_HOME}/libfranka-0.16.1"/*_test 2>/dev/null || true

echo "libfranka 0.16.1 installation completed!"
echo "libfranka is now available for FR3 robot control"
echo "Examples and tests are available in: ${TARGET_HOME}/libfranka-0.16.1"

