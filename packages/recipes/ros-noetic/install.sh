#!/usr/bin/env bash
set -euo pipefail

# ROS Noetic via RoboStack installation script
echo "Installing ROS Noetic via RoboStack..."

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

# Ensure micromamba is installed (dependency)
if [[ ! -f /home/servobox-usr/.local/bin/micromamba ]]; then
    echo "Error: micromamba is not installed. Please install the 'robostack' package first."
    exit 1
fi

# Clean cache proactively to prevent timeout issues
echo "Cleaning micromamba cache to prevent download timeouts..."
su - servobox-usr -c "
    export MAMBA_EXE='/home/servobox-usr/.local/bin/micromamba'
    export MAMBA_ROOT_PREFIX='/home/servobox-usr/micromamba'
    eval \"\$(\${MAMBA_EXE} shell hook --shell bash)\"
    \${MAMBA_EXE} clean -a -y
"

# Create or update ROS Noetic environment
echo "Setting up ROS Noetic environment (ros_noetic)..."
su - servobox-usr -c "
    export MAMBA_EXE='/home/servobox-usr/.local/bin/micromamba'
    export MAMBA_ROOT_PREFIX='/home/servobox-usr/micromamba'
    eval \"\$(\${MAMBA_EXE} shell hook --shell bash)\"
    
    # Clean up any conflicting directory that might exist
    if [[ -d \${MAMBA_ROOT_PREFIX}/envs/ros_noetic ]] && [[ ! -f \${MAMBA_ROOT_PREFIX}/envs/ros_noetic/conda-meta ]]; then
        echo 'Removing conflicting non-conda directory...'
        rm -rf \${MAMBA_ROOT_PREFIX}/envs/ros_noetic
    fi
    
    # Create the environment (will work now that conflicting dir is gone)
    \${MAMBA_EXE} create -n ros_noetic -c conda-forge -c robostack-noetic ros-noetic-desktop -y
"

# Install development tools
echo "Installing development tools..."
su - servobox-usr -c "
    export MAMBA_EXE='/home/servobox-usr/.local/bin/micromamba'
    export MAMBA_ROOT_PREFIX='/home/servobox-usr/micromamba'
    eval \"\$(\${MAMBA_EXE} shell hook --shell bash)\"
    \${MAMBA_EXE} install -n ros_noetic -c conda-forge -c robostack-noetic \
        compilers cmake pkg-config make ninja \
        colcon-common-extensions catkin_tools rosdep -y
"

echo ""
echo "ROS Noetic installation completed!"
echo ""
echo "To use ROS Noetic:"
echo "  micromamba activate ros_noetic"
echo ""
echo "Available development tools:"
echo "  • compilers (GCC, G++)"
echo "  • cmake, pkg-config, make, ninja"
echo "  • colcon-common-extensions, catkin_tools, catkin_make"
echo "  • rosdep (for dependency management)"
echo ""
echo "To test:"
echo "  micromamba activate ros_noetic && roscore"
echo ""

apt_cleanup

