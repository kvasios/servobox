#!/usr/bin/env bash
set -euo pipefail

# Franka ROS installation script
echo "Installing Franka ROS..."

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

# Ensure ros-noetic environment exists (dependency)
if [[ ! -d /home/servobox-usr/micromamba/envs/ros_noetic ]]; then
    echo "Error: ros_noetic environment not found. Please install the 'ros-noetic' package first."
    exit 1
fi

# Clean up any previous broken states
echo "Ensuring clean package state..."
apt-get clean || true
rm -rf /var/lib/apt/lists/* || true

# Install build dependencies
echo "Installing build dependencies..."
apt_update || apt-get update || true
apt_install git || apt-get install -y git || true
# Note: libfranka and Poco will be built in conda environment during build

# Create workspace directory
echo "Creating workspace: ~/ws_franka_ros"
mkdir -p /home/servobox-usr/ws_franka_ros/src
chown -R servobox-usr:servobox-usr /home/servobox-usr/ws_franka_ros

# Clone franka_ros repository
echo "Cloning franka_ros repository..."
su - servobox-usr -c "
    cd ~/ws_franka_ros/src
    if [ ! -d franka_ros ]; then
        git clone --recursive https://github.com/frankarobotics/franka_ros.git
    fi
"

# Copy build script to workspace
# RECIPE_DIR is set by the package manager
if [[ -z "${RECIPE_DIR:-}" ]]; then
    RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

cp "${RECIPE_DIR}/build_franka_ros_control.sh" /home/servobox-usr/ws_franka_ros/
chown servobox-usr:servobox-usr /home/servobox-usr/ws_franka_ros/build_franka_ros_control.sh
chmod +x /home/servobox-usr/ws_franka_ros/build_franka_ros_control.sh

# Clean up any previous failed builds
echo "Cleaning up any previous build artifacts..."
su - servobox-usr -c "
    cd ~/ws_franka_ros
    rm -rf build devel .catkin_workspace .catkin_tools logs external/libfranka/build || true
" || true

# Build franka_ros using the build script with error handling
echo "Building franka_ros (this may take several minutes)..."
if ! su - servobox-usr -c "
    cd ~/ws_franka_ros
    # Clear any conda environment pollution before running
    unset CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH
    /home/servobox-usr/.local/bin/micromamba run -n ros_noetic ./build_franka_ros_control.sh
"; then
    echo "Error: franka_ros build failed"
    echo "This might be due to:"
    echo "  - Environment pollution from previous installations"
    echo "  - Missing dependencies"
    echo "  - Compiler issues"
    echo ""
    echo "Try cleaning the workspace and rebuilding:"
    echo "  cd ~/ws_franka_ros"
    echo "  rm -rf build devel .catkin_workspace .catkin_tools logs external"
    echo "  micromamba activate ros_noetic"
    echo "  ./build_franka_ros_control.sh --clean"
    exit 1
fi

# Verify installation
echo "Verifying Franka ROS installation..."
if [[ -f /home/servobox-usr/ws_franka_ros/devel/setup.bash ]]; then
    echo "✓ Workspace built successfully"
else
    echo "✗ Error: Workspace setup.bash not found"
    exit 1
fi

if [[ -f /home/servobox-usr/ws_franka_ros/setup_env.sh ]]; then
    echo "✓ Environment setup script created"
else
    echo "⚠ Warning: setup_env.sh not found"
fi

# Check for key packages
EXPECTED_PACKAGES=("franka_hw" "franka_control" "franka_gripper" "franka_msgs")
for pkg in "${EXPECTED_PACKAGES[@]}"; do
    if [[ -d /home/servobox-usr/ws_franka_ros/devel/lib/$pkg ]] || \
       [[ -d /home/servobox-usr/ws_franka_ros/devel/share/$pkg ]]; then
        echo "✓ Package $pkg built"
    else
        echo "⚠ Warning: Package $pkg may not be built correctly"
    fi
done

echo ""
echo "Franka ROS installation completed!"
echo ""
echo "Workspace: ~/ws_franka_ros"
echo ""
echo "To use:"
echo "  micromamba activate ros_noetic"
echo "  cd ~/ws_franka_ros && source setup_env.sh"
echo "  roslaunch franka_control franka_control.launch robot_ip:=<robot_ip>"
echo ""

apt_cleanup

