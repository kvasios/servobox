#!/bin/bash
# ============================================================================
# Dependency Checker for Franka ROS on RoboStack
# ============================================================================
# This script checks if all required dependencies are properly installed
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_item() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
        return 0
    else
        echo -e "${RED}✗${NC} $2"
        return 1
    fi
}

echo "================================================"
echo "Franka ROS Dependency Check"
echo "================================================"
echo ""

MISSING=0

# Check conda environment
echo "Environment:"
if [ -n "$CONDA_PREFIX" ]; then
    echo -e "${GREEN}✓${NC} Conda environment: $CONDA_DEFAULT_ENV"
else
    echo -e "${RED}✗${NC} Not in conda environment"
    MISSING=$((MISSING+1))
fi

# Check ROS
echo ""
echo "ROS Setup:"
if [ -f "$CONDA_PREFIX/setup.bash" ]; then
    echo -e "${GREEN}✓${NC} ROS Noetic found in conda"
else
    echo -e "${RED}✗${NC} ROS setup.bash not found"
    MISSING=$((MISSING+1))
fi

# Check key ROS packages
echo ""
echo "ROS Packages (checking conda environment):"
PACKAGES=(
    "controller_interface"
    "hardware_interface"
    "realtime_tools"
    "gazebo_ros"
    "joint_state_publisher"
)

for pkg in "${PACKAGES[@]}"; do
    if [ -d "$CONDA_PREFIX/share/ros-noetic-${pkg//_/-}" ] || \
       [ -d "$CONDA_PREFIX/share/$pkg" ] || \
       micromamba list | grep -q "ros-noetic-${pkg//_/-}"; then
        echo -e "${GREEN}✓${NC} $pkg"
    else
        echo -e "${RED}✗${NC} $pkg"
        MISSING=$((MISSING+1))
    fi
done

# Check libfranka
echo ""
echo "Franka Libraries:"
if [ -f "$CONDA_PREFIX/lib/libfranka.so" ] || ldconfig -p | grep -q libfranka; then
    echo -e "${GREEN}✓${NC} libfranka"
    if [ -f "$CONDA_PREFIX/lib/libfranka.so" ]; then
        VERSION=$(strings "$CONDA_PREFIX/lib/libfranka.so" | grep -oP '^\d+\.\d+\.\d+$' | head -1)
        if [ -n "$VERSION" ]; then
            echo "    Version: $VERSION"
        fi
    fi
else
    echo -e "${RED}✗${NC} libfranka not found"
    echo "    Run: ./setup_franka_robostack.sh"
    MISSING=$((MISSING+1))
fi

# Check boost-sml
if [ -f "$CONDA_PREFIX/include/boost/sml.hpp" ]; then
    echo -e "${GREEN}✓${NC} boost-sml"
elif micromamba list | grep -q boost-sml; then
    echo -e "${GREEN}✓${NC} boost-sml (from conda)"
else
    echo -e "${YELLOW}⚠${NC} boost-sml (may be missing)"
fi

# Check build tools
echo ""
echo "Build Tools:"
command -v cmake >/dev/null 2>&1
check_item $? "cmake"

command -v catkin_make >/dev/null 2>&1 || command -v catkin >/dev/null 2>&1
check_item $? "catkin build tools"

command -v gcc >/dev/null 2>&1
check_item $? "gcc compiler"

# Check workspace
echo ""
echo "Workspace:"
WORKSPACE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -f "$WORKSPACE_DIR/devel/setup.bash" ]; then
    echo -e "${GREEN}✓${NC} Workspace built at $WORKSPACE_DIR"
    source "$WORKSPACE_DIR/devel/setup.bash"
    
    # Check if franka packages are findable
    echo ""
    echo "Franka Packages:"
    for pkg in franka_control franka_hw franka_msgs franka_gripper franka_gazebo; do
        if rospack find $pkg >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} $pkg"
        else
            echo -e "${RED}✗${NC} $pkg"
            MISSING=$((MISSING+1))
        fi
    done
else
    echo -e "${YELLOW}⚠${NC} Workspace not built yet"
    echo "    Run: ./setup_franka_robostack.sh"
fi

# Summary
echo ""
echo "================================================"
if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}All checks passed! ✓${NC}"
    echo ""
    echo "To use franka_ros, run:"
    echo "  source setup_env.sh"
    exit 0
else
    echo -e "${YELLOW}Found $MISSING missing dependencies${NC}"
    echo ""
    echo "To install dependencies, run:"
    echo "  ./setup_franka_robostack.sh"
    exit 1
fi

