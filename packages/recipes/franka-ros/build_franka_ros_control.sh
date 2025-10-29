#!/bin/bash
# ============================================================================
# ONE SCRIPT TO BUILD FRANKA ROS CONTROL
# ============================================================================
# Builds only the control packages needed for headless robot control:
# - franka_control, franka_hw, franka_example_controllers
# - Skips gazebo simulation and rviz visualization
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

WORKSPACE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$WORKSPACE_DIR"

# ============================================================================
# 1. Prerequisites
# ============================================================================
print_header "Step 1: Checking Prerequisites"

if [ -z "$CONDA_PREFIX" ]; then
    print_error "Not in a conda environment! Run: micromamba activate ros_env"
    exit 1
fi
print_success "Conda environment: $CONDA_DEFAULT_ENV"

if ! command -v micromamba &> /dev/null && [ ! -f /home/servobox-usr/.local/bin/micromamba ]; then
    print_error "micromamba not found!"
    exit 1
fi
if command -v micromamba &> /dev/null; then
    print_success "micromamba: $(which micromamba)"
else
    print_success "micromamba: /home/servobox-usr/.local/bin/micromamba"
fi

# ============================================================================
# 2. Install Dependencies
# ============================================================================
print_header "Step 2: Installing Dependencies"

echo "Using conda environment for all dependencies (libfranka, Poco, ROS)..."

echo "Installing ROS Noetic control packages..."
/home/servobox-usr/.local/bin/micromamba install -y -c robostack-staging -c conda-forge \
    ros-noetic-controller-interface \
    ros-noetic-controller-manager \
    ros-noetic-hardware-interface \
    ros-noetic-joint-limits-interface \
    ros-noetic-combined-robot-hw \
    ros-noetic-realtime-tools \
    ros-noetic-ros-controllers \
    ros-noetic-effort-controllers \
    ros-noetic-joint-trajectory-controller \
    ros-noetic-position-controllers \
    ros-noetic-velocity-controllers \
    ros-noetic-pluginlib \
    ros-noetic-urdf \
    ros-noetic-xacro \
    ros-noetic-tf \
    ros-noetic-tf-conversions \
    ros-noetic-tf2 \
    ros-noetic-tf2-ros \
    ros-noetic-tf2-msgs \
    ros-noetic-tf2-geometry-msgs \
    ros-noetic-control-msgs \
    ros-noetic-actionlib \
    ros-noetic-joint-state-publisher \
    ros-noetic-robot-state-publisher \
    ros-noetic-kdl-parser \
    ros-noetic-eigen-conversions \
    ros-noetic-dynamic-reconfigure \
    ros-noetic-geometry-msgs \
    ros-noetic-sensor-msgs \
    ros-noetic-std-msgs \
    ros-noetic-visualization-msgs \
    ros-noetic-message-generation \
    ros-noetic-roscpp \
    &> /dev/null || print_warning "Some ROS packages may have issues"

print_success "Dependencies installed"

# ============================================================================
# 3. Build libfranka in conda environment
# ============================================================================
print_header "Step 3: Building libfranka 0.9.2 in conda environment"

# Check if libfranka is already built in conda
if [ -f "$CONDA_PREFIX/lib/libfranka.so" ]; then
    print_success "libfranka already exists in conda environment"
else
    echo "Building libfranka 0.9.2 from source..."
    
    # Install build dependencies in conda
    /home/servobox-usr/.local/bin/micromamba install -y -c conda-forge \
        cmake eigen poco-cpp &> /dev/null || print_warning "Some dependencies may have issues"
    
    # Clone and build libfranka
    cd /tmp
    rm -rf libfranka-build
    git clone --recursive https://github.com/frankaemika/libfranka libfranka-build
    cd libfranka-build
    git checkout 0.9.2
    git submodule update --init --recursive
    
    # Patch CMake minimum version for libfranka and submodules
    find . -name "CMakeLists.txt" -type f -exec sed -i 's/cmake_minimum_required(VERSION [23]\.[0-9][^)]*)/cmake_minimum_required(VERSION 3.5)/' {} \;
    
    # Patch C++ standard to C++17 for Poco 1.12.4 compatibility
    sed -i 's/set(CMAKE_CXX_STANDARD 14)/set(CMAKE_CXX_STANDARD 17)/' CMakeLists.txt
    
    mkdir -p build && cd build
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
          -DBUILD_TESTS=OFF \
          -DBUILD_EXAMPLES=OFF \
          -DCMAKE_CXX_STANDARD=17 \
          ..
    
    cmake --build . -j$(nproc)
    cmake --install .
    
    cd /tmp && rm -rf libfranka-build
    
    print_success "libfranka 0.9.2 built and installed to conda environment"
fi

# ============================================================================
# 4. Patch CMake Files and Source Code
# ============================================================================
print_header "Step 4: Patching CMake Files and Source Code"

cd "$WORKSPACE_DIR"

echo "Patching all CMakeLists.txt for CMake 3.5+..."
find src/franka_ros -name "CMakeLists.txt" -type f -exec sed -i 's/cmake_minimum_required(VERSION [23]\.[0-9][^)]*)/cmake_minimum_required(VERSION 3.5)/' {} \; 2>/dev/null
[ -f "src/CMakeLists.txt" ] && sed -i 's/cmake_minimum_required(VERSION [23]\.[0-9][^)]*)/cmake_minimum_required(VERSION 3.5)/' src/CMakeLists.txt

echo "Patching franka_hw source files for C++17 compatibility..."
# Add missing cstdint include for uint8_t
if [ -f "src/franka_ros/franka_hw/include/franka_hw/resource_helpers.h" ]; then
    sed -i '/#include <franka_hw\/control_mode.h>/a #include <cstdint>' src/franka_ros/franka_hw/include/franka_hw/resource_helpers.h
fi

print_success "Source files patched"

# ============================================================================
# 4. Configure Build
# ============================================================================
print_header "Step 4: Configuring Build"

# Source ROS setup files
echo "Sourcing ROS environment..."
if [ -f "$CONDA_PREFIX/setup.bash" ]; then
    echo "Sourcing conda ROS setup: $CONDA_PREFIX/setup.bash"
    source "$CONDA_PREFIX/setup.bash"
else
    echo "Warning: ROS setup.bash not found at $CONDA_PREFIX/setup.bash"
fi

# Use conda compilers for consistent builds
export PATH="$CONDA_PREFIX/bin:$PATH"
export CC="$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-gcc"
export CXX="$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-g++"

# CRITICAL: Clear conda include paths to prevent header conflicts
# The catkin build needs ROS headers from conda, but NOT system headers from conda
unset CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH

# Ensure conda libraries are prioritized (everything built in conda)
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$CONDA_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

# Verify ROS environment
echo "Verifying ROS environment..."
echo "ROS_PACKAGE_PATH: $ROS_PACKAGE_PATH"
echo "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"

# Clean if requested
if [ "$1" == "--clean" ]; then
    print_warning "Cleaning build space..."
    rm -rf build devel .catkin_workspace .catkin_tools logs
fi

# Detect and clean conflicting build systems
if [ -f "build/CMakeCache.txt" ] && ! [ -d ".catkin_tools" ]; then
    print_warning "Cleaning old catkin_make build..."
    rm -rf build devel .catkin_workspace
fi

# Configure catkin - SKIP gazebo and visualization packages
echo "Configuring catkin (control packages only)..."
catkin config --extend "$CONDA_PREFIX" \
              --blacklist franka_gazebo franka_visualization franka_ros \
              --cmake-args -DCMAKE_BUILD_TYPE=Release \
                           -DCATKIN_ENABLE_TESTING=OFF \
                           -DCMAKE_CXX_COMPILER="$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-g++" \
                           -DCMAKE_C_COMPILER="$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-gcc"

print_success "Build configured"

# ============================================================================
# 5. Build
# ============================================================================
print_header "Step 5: Building Franka Control Packages"

echo "Building franka_ros control packages using catkin_tools..."
echo "Dependencies resolved automatically via rosdep"
echo ""
echo "Building packages:"
echo "  • franka_description (URDF/meshes)"
echo "  • franka_msgs (messages)"
echo "  • franka_gripper (gripper control)"
echo "  • franka_hw (hardware interface)"
echo "  • franka_control (control node)"
echo "  • franka_example_controllers (example controllers)"
echo ""
echo "Skipping: franka_gazebo, franka_visualization, franka_ros"
echo ""

catkin build

print_success "Build complete!"

# ============================================================================
# 6. Create Environment Setup
# ============================================================================
cat > "$WORKSPACE_DIR/setup_env.sh" << 'EOF'
#!/bin/bash
# Source this to use franka_ros control

# Ensure we're in a conda environment
if [ -z "$CONDA_PREFIX" ]; then
    echo "Error: Not in a conda environment. Run: micromamba activate ros_noetic"
    return 1 2>/dev/null || exit 1
fi

if [ -f "$CONDA_PREFIX/setup.bash" ]; then
    source "$CONDA_PREFIX/setup.bash"
fi

WORKSPACE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -f "$WORKSPACE_DIR/devel/setup.bash" ]; then
    source "$WORKSPACE_DIR/devel/setup.bash"
fi

# Ensure conda environment is properly configured
export CMAKE_PREFIX_PATH="$CONDA_PREFIX:$CMAKE_PREFIX_PATH"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$CONDA_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

echo "Franka Control environment ready!"
echo "Conda environment: $CONDA_DEFAULT_ENV"
echo "Workspace: $WORKSPACE_DIR"
EOF

chmod +x "$WORKSPACE_DIR/setup_env.sh"

# ============================================================================
# Summary
# ============================================================================
print_header "✓ Setup Complete!"

echo -e "${GREEN}Franka ROS Control is ready!${NC}"

