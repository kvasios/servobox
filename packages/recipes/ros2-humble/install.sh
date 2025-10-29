#!/usr/bin/env bash
set -euo pipefail

# ROS 2 Humble installation script
# This script installs ROS 2 Humble from the official Ubuntu packages

echo "Installing ROS 2 Humble..."

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

# Clean up any previous broken states
echo "Cleaning up any previous installation remnants..."
apt-get clean || true
rm -rf /var/lib/apt/lists/* || true
apt-get autoremove -y || true
apt-get autoclean || true

# Fix any broken packages
echo "Fixing any broken package states..."
dpkg --configure -a || true
apt-get --fix-broken install -y || true

# Set up the repository with robust error handling
echo "Setting up ROS 2 repository..."
apt_update || apt-get update || true

# Install repository setup tools with fallbacks
apt_install software-properties-common || apt-get install -y software-properties-common || true
apt_install curl || apt-get install -y curl || true
apt_install gnupg || apt-get install -y gnupg || true
apt_install ca-certificates || apt-get install -y ca-certificates || true

# Add universe repository
add-apt-repository -y universe || true

# Download and setup ROS key with error handling
echo "Downloading ROS repository key..."
if ! curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg; then
    echo "Warning: Failed to download ROS key, trying alternative method..."
    wget -qO- https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | apt-key add - || true
fi

# Add ROS repository
echo "Adding ROS 2 repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null || true

# Install ROS 2 Humble with robust error handling
echo "Installing ROS 2 Humble base packages..."
apt_update || apt-get update || true

# Install ros-base first
if ! apt_install ros-humble-ros-base; then
    echo "Warning: Failed to install ros-humble-ros-base with helper, trying direct apt..."
    apt-get install -y ros-humble-ros-base || {
        echo "Error: Failed to install ros-humble-ros-base"
        echo "This might be due to missing dependencies or broken package states"
        exit 1
    }
fi

# Install additional useful packages for headless control systems with fallbacks
echo "Installing additional ROS 2 packages..."
PACKAGES=(
    "python3-rosdep"
    "python3-colcon-common-extensions" 
    "python3-argcomplete"
    "ros-humble-ament-cmake"
    "ros-humble-rclcpp"
    "ros-humble-rclpy"
    "ros-humble-ros2-control"
    "ros-humble-ros2-controllers"
)

for pkg in "${PACKAGES[@]}"; do
    echo "Installing $pkg..."
    if ! apt_install "$pkg"; then
        echo "Warning: Failed to install $pkg with helper, trying direct apt..."
        if ! apt-get install -y "$pkg"; then
            echo "Warning: Failed to install $pkg - continuing with other packages..."
        fi
    fi
done

# Initialize rosdep
rosdep init || true
rosdep update

# Set up environment
# Wrap ROS2 setup.bash with set +u/-u to avoid "unbound variable" errors from COLCON_TRACE
echo "# Source ROS2 Humble" >> /home/servobox-usr/.bashrc
echo "if [ -f /opt/ros/humble/setup.bash ]; then" >> /home/servobox-usr/.bashrc
echo "  set +u  # Temporarily disable nounset for ROS2 setup scripts" >> /home/servobox-usr/.bashrc
echo "  source /opt/ros/humble/setup.bash" >> /home/servobox-usr/.bashrc
echo "  set -u  # Re-enable nounset" >> /home/servobox-usr/.bashrc
echo "fi" >> /home/servobox-usr/.bashrc

echo "# Source ROS2 Humble" >> /root/.bashrc
echo "if [ -f /opt/ros/humble/setup.bash ]; then" >> /root/.bashrc
echo "  set +u  # Temporarily disable nounset for ROS2 setup scripts" >> /root/.bashrc
echo "  source /opt/ros/humble/setup.bash" >> /root/.bashrc
echo "  set -u  # Re-enable nounset" >> /root/.bashrc
echo "fi" >> /root/.bashrc

# Create workspace directory for control system development
mkdir -p /home/servobox-usr/ros2_ws/src
chown -R servobox-usr:servobox-usr /home/servobox-usr/ros2_ws

# Create a high-frequency control example workspace
mkdir -p /home/servobox-usr/control_ws/src
chown -R servobox-usr:servobox-usr /home/servobox-usr/control_ws

# Set up ROS 2 environment
echo "export ROS_DOMAIN_ID=0" >> /home/servobox-usr/.bashrc
echo "export RCUTILS_LOGGING_USE_STDOUT=1" >> /home/servobox-usr/.bashrc

# Verify ROS 2 installation
echo "Verifying ROS 2 Humble installation..."
if [[ -f /opt/ros/humble/setup.bash ]]; then
    echo "✓ ROS 2 Humble setup.bash found"
    
    # Test sourcing the setup script
    if bash -c "source /opt/ros/humble/setup.bash && echo 'ROS_DISTRO: $ROS_DISTRO'"; then
        echo "✓ ROS 2 Humble environment can be sourced"
    else
        echo "⚠ Warning: ROS 2 Humble environment has issues"
    fi
else
    echo "✗ Error: ROS 2 Humble setup.bash not found - installation may have failed"
    exit 1
fi

# Check for key ROS 2 tools
for tool in ros2 colcon; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✓ $tool is available"
    else
        echo "⚠ Warning: $tool not found in PATH"
    fi
done

echo "ROS 2 Humble (headless control) installation completed!"

apt_cleanup
