#!/usr/bin/env bash
set -euo pipefail

# SERL Franka Controllers installation script
echo "Installing SERL Franka Controllers..."

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

# Ensure franka_ros workspace exists (dependency)
if [[ ! -d /home/servobox-usr/ws_franka_ros ]]; then
    echo "Error: franka_ros workspace not found. Please install the 'franka-ros' package first."
    exit 1
fi

# Ensure ros-noetic environment exists
if [[ ! -d /home/servobox-usr/micromamba/envs/ros_noetic ]]; then
    echo "Error: ros_noetic environment not found. Please install the 'ros-noetic' package first."
    exit 1
fi

# Install build dependencies
apt_update
apt_install git

# Clone serl_franka_controllers repository into the existing workspace
echo "Cloning serl_franka_controllers repository..."
su - servobox-usr -c "
    cd ~/ws_franka_ros/src
    if [ ! -d serl_franka_controllers ]; then
        git clone https://github.com/rail-berkeley/serl_franka_controllers.git
    fi
"

# Patch CMakeLists.txt for CMake 3.5+
echo "Patching CMakeLists.txt for CMake 3.5+..."
sed -i 's/cmake_minimum_required(VERSION [23]\.[0-9][^)]*)/cmake_minimum_required(VERSION 3.5)/' /home/servobox-usr/ws_franka_ros/src/serl_franka_controllers/CMakeLists.txt

# Build serl_franka_controllers
echo "Building serl_franka_controllers..."
su - servobox-usr -c "
    cd ~/ws_franka_ros
    /home/servobox-usr/.local/bin/micromamba run -n ros_noetic catkin build serl_franka_controllers
"

echo ""
echo "SERL Franka Controllers installation completed!"
echo ""
echo "Workspace: ~/ws_franka_ros"
echo ""
echo "To use:"
echo "  micromamba activate ros_noetic"
echo "  cd ~/ws_franka_ros && source setup_env.sh"
echo "  roslaunch serl_franka_controllers impedance.launch robot_ip:=<robot_ip> load_gripper:=true"
echo ""
echo "Available controllers:"
echo "  - Cartesian Impedance Controller (impedance.launch)"
echo "  - Joint Position Controller (joint.launch)"
echo ""

apt_cleanup

