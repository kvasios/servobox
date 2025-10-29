#!/usr/bin/env bash
set -euo pipefail

# franka-ros2 installation script
# Clones and builds franka_ros2 and its dependencies

echo "Installing franka-ros2..."

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

# Verify libfranka is installed and find its CMake config
echo "Checking for system libfranka installation..."
FRANKA_DIR_CANDIDATES=(
  "/usr/local/lib/cmake/Franka"
  "/usr/lib/x86_64-linux-gnu/cmake/Franka"
  "/usr/lib/cmake/Franka"
  "/lib/x86_64-linux-gnu/cmake/Franka"
  "/lib/cmake/Franka"
)
FRANKA_FOUND=0
for cand in "${FRANKA_DIR_CANDIDATES[@]}"; do
  if [[ -f "${cand}/FrankaConfig.cmake" ]]; then
    export Franka_DIR="${cand}"
    FRANKA_FOUND=1
    echo "Found system libfranka at: ${Franka_DIR}"
    break
  fi
done

if [[ $FRANKA_FOUND -eq 0 ]]; then
  echo "ERROR: System libfranka not found!" >&2
  echo "       Install 'libfranka-fr3' recipe first: ./servobox pkg-install libfranka-fr3" >&2
  exit 1
fi

# Source ROS2 environment (temporarily disable nounset due to ROS2 setup script variables)
set +u
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
set -u

# Create Franka ROS2 workspace if it doesn't exist
FRANKA_ROS2_WS="/home/servobox-usr/franka_ros2_ws"
if [[ ! -d "${FRANKA_ROS2_WS}" ]]; then
  echo "Creating Franka ROS2 workspace at ${FRANKA_ROS2_WS}..."
  mkdir -p "${FRANKA_ROS2_WS}/src"
  chown -R servobox-usr:servobox-usr "${FRANKA_ROS2_WS}"
fi

# Navigate to the Franka ROS2 workspace
cd "${FRANKA_ROS2_WS}"

# Clone franka_ros2 into src directory (humble branch for ROS2 Humble compatibility)
echo "Cloning franka_ros2 (humble branch) from GitHub..."
rm -rf src/franka_ros2
git clone --depth 1 --branch humble https://github.com/frankarobotics/franka_ros2.git src/franka_ros2

# Clone franka_description directly (required dependency, don't use vcs to avoid cloning libfranka)
# We use system libfranka instead of building from source
echo "Cloning franka_description (v1.0.1) from GitHub..."
rm -rf src/franka_description
git clone --depth 1 --branch 1.0.1 https://github.com/frankarobotics/franka_description.git src/franka_description

# Verify that franka_description was cloned successfully
if [[ ! -d src/franka_description ]]; then
  echo "ERROR: franka_description was not cloned successfully!" >&2
  echo "       This is required for franka_ros2 to work properly." >&2
  exit 1
fi
echo "Successfully cloned franka_description"

# Patch franka_ros2 meta-package to remove gazebo dependencies
echo "Patching franka_ros2 meta-package to remove gazebo dependencies..."
# The franka_ros2 repo is a monorepo; the meta-package is in franka_ros2/franka_ros2/
METAPKG_XML="src/franka_ros2/franka_ros2/package.xml"
if [[ -f "${METAPKG_XML}" ]]; then
  sed -i '/<depend>franka_gazebo_bringup<\/depend>/d' "${METAPKG_XML}"
  sed -i '/<depend>franka_ign_ros2_control<\/depend>/d' "${METAPKG_XML}"
  echo "Patched franka_ros2 meta-package at ${METAPKG_XML}"
else
  echo "ERROR: Could not find ${METAPKG_XML} to patch" >&2
  echo "       Available package.xml files:" >&2
  find src/franka_ros2 -name "package.xml" -type f 2>/dev/null | head -10 >&2
  exit 1
fi

# Update rosdep
echo "Updating rosdep..."
rosdep update || true

# Install dependencies using rosdep
# Note: This will fail trying to install non-existent ros-humble-libfranka, but that's fine
# since we're using system libfranka. We ignore this specific error.
echo "Installing package dependencies via rosdep..."
echo "NOTE: rosdep may fail on 'ros-humble-libfranka' - this is expected, we use system libfranka"
rosdep install --from-paths src --ignore-src --rosdistro humble -y 2>&1 | grep -v "ros-humble-libfranka" || true

# Build the franka_ros2 packages using system libfranka
# Skip gazebo/ignition packages (incompatible protobuf versions, not needed for real robot control)
echo "Building franka_ros2 with colcon (using system libfranka from ${Franka_DIR})..."
colcon build \
  --packages-skip franka_gazebo franka_ign_ros2_control franka_gazebo_bringup \
  --cmake-args \
    -DCMAKE_BUILD_TYPE=Release \
    -DFranka_DIR="${Franka_DIR}"

# Source the workspace (temporarily disable nounset for ROS2 setup scripts)
set +u
# shellcheck disable=SC1091
source install/setup.bash || true
set -u

# Fix ownership
chown -R servobox-usr:servobox-usr "${FRANKA_ROS2_WS}" || true

# Cleanup apt caches if available via helpers
apt_cleanup || true

echo "franka-ros2 installation completed successfully!"

