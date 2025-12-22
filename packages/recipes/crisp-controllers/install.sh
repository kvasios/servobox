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
mkdir -p "${TARGET_HOME}"

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
CRISP_WS="${TARGET_HOME}/crisp_ws"
if [[ ! -d "${CRISP_WS}" ]]; then
  echo "Creating CRISP workspace at ${CRISP_WS}..."
  mkdir -p "${CRISP_WS}/src"
  chown -R ${TARGET_USER}:${TARGET_USER} "${CRISP_WS}"
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
chown -R ${TARGET_USER}:${TARGET_USER} "${CRISP_WS}" || true

# Cleanup apt caches if available via helpers
apt_cleanup || true

echo "crisp-controllers installation completed successfully!"

