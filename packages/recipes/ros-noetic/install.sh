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

# Ensure micromamba is installed (dependency)
if [[ ! -f "${TARGET_HOME}/.local/bin/micromamba" ]]; then
    echo "Error: micromamba is not installed. Please install the 'robostack' package first."
    exit 1
fi

# Clean cache proactively to prevent timeout issues
echo "Cleaning micromamba cache to prevent download timeouts..."
su - ${TARGET_USER} -c "
    export MAMBA_EXE='${TARGET_HOME}/.local/bin/micromamba'
    export MAMBA_ROOT_PREFIX='${TARGET_HOME}/micromamba'
    eval \"\$(\${MAMBA_EXE} shell hook --shell bash)\"
    \${MAMBA_EXE} clean -a -y
"

# Create or update ROS Noetic environment
echo "Setting up ROS Noetic environment (ros_noetic)..."
su - ${TARGET_USER} -c "
    export MAMBA_EXE='${TARGET_HOME}/.local/bin/micromamba'
    export MAMBA_ROOT_PREFIX='${TARGET_HOME}/micromamba'
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
su - ${TARGET_USER} -c "
    export MAMBA_EXE='${TARGET_HOME}/.local/bin/micromamba'
    export MAMBA_ROOT_PREFIX='${TARGET_HOME}/micromamba'
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

