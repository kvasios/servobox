#!/usr/bin/env bash
set -euo pipefail

# crisp-controllers installation script
# Clones and builds crisp_controllers ROS2 package

echo "Installing crisp-controllers..."

export DEBIAN_FRONTEND=noninteractive

# Ensure helpers are available when running inside image via package manager
if [[ -n "${PACKAGE_HELPERS:-}" && -f "${PACKAGE_HELPERS}" ]]; then
  # shellcheck source=/dev/null
  . "${PACKAGE_HELPERS}"
else
  # Fallback to local helpers when running directly
  if [[ -f "$(cd "$(dirname "$0")/.." && pwd)/scripts/pkg-helpers.sh" ]]; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "$0")/.." && pwd)/scripts/pkg-helpers.sh"
  fi
fi

# Verify expected home directory exists
if [[ ! -d /home/servobox-usr ]]; then
  echo "Error: /home/servobox-usr does not exist" >&2
  exit 1
fi

# Verify ROS2 is installed
if [[ ! -f /opt/ros/humble/setup.bash ]]; then
  echo "Error: ROS2 Humble not found. Please install ros2-humble package first." >&2
  exit 1
fi

# Source ROS2 environment (temporarily disable nounset due to ROS2 setup script variables)
set +u
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
set -u

# Create CRISP workspace if it doesn't exist
CRISP_WS="/home/servobox-usr/crisp_ws"
if [[ ! -d "${CRISP_WS}" ]]; then
  echo "Creating CRISP workspace at ${CRISP_WS}..."
  mkdir -p "${CRISP_WS}/src"
  chown -R servobox-usr:servobox-usr "${CRISP_WS}"
fi

# Navigate to the CRISP workspace
cd "${CRISP_WS}"

# Clone crisp_controllers into src directory
echo "Cloning crisp_controllers from GitHub..."
rm -rf src/crisp_controllers
git clone --depth 1 https://github.com/utiasDSL/crisp_controllers.git src/crisp_controllers

# Update rosdep
echo "Updating rosdep..."
rosdep update || true

# Install dependencies using rosdep
echo "Installing package dependencies via rosdep..."
rosdep install -q --from-paths src --ignore-src -y || true

# Build the crisp_controllers package
echo "Building crisp_controllers with colcon..."
colcon build --packages-select crisp_controllers --cmake-args -DCMAKE_BUILD_TYPE=Release

# Source the workspace (temporarily disable nounset for ROS2 setup scripts)
set +u
# shellcheck disable=SC1091
source install/setup.bash || true
set -u

# Fix ownership
chown -R servobox-usr:servobox-usr "${CRISP_WS}" || true

# Cleanup apt caches if available via helpers
apt_cleanup || true

echo "crisp-controllers installation completed successfully!"

