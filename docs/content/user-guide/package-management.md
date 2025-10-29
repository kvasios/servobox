# Package Management

ServoBox includes a package manager for installing pre-configured robotics software stacks into VM images.

## Overview

The ServoBox package manager provides:

- **Pre-built installation recipes** for common robotics software
- **Automatic internal dependency resolution** - installs prerequisites in the correct order
- **Offline installation** - packages are installed into VM images without booting

## Quick Start

```console
# List available packages
servobox pkg-install --list

# Install a package (dependencies are automatically installed)
servobox pkg-install libfranka-gen1 #or libfranka-fr3

# Install with verbose output
servobox pkg-install ros2-humble --verbose

# Use custom recipe directory
servobox pkg-install --custom ~/my-recipes my-package

# Force reinstall a package
servobox pkg-install libfranka-gen1 --force
```

## Commands

### Install Packages

```console
servobox pkg-install <package> [--name NAME] [--verbose] [--force] [--custom PATH]
```

- `--name NAME`: Target VM name (default: servobox-vm)
- `--verbose`: Show detailed installation output
- `--force`: Force reinstall even if already installed
- `--custom PATH`: Use custom recipe directory

### List Installed Packages

```console
servobox pkg-installed [--name NAME] [--verbose]
```

### Preview Dependencies

```console
# Show dependency tree and installation order
packages/scripts/package-manager.sh deps <package>
```

## Available Packages

### Complete Suites

These packages provide complete robotics software stacks:

| Package | Description | Dependencies |
|---------|-------------|--------------|
| **polymetis** | Polymetis - Facebook's robot learning framework with Franka support (via micromamba) | None |
| **deoxys-control** | deoxys_control for AI robot agent dev/research | libfranka-gen1/fr3 |
| **serl-franka-controllers** | SERL Franka compliant Cartesian impedance controllers for RL (via RoboStack/micromamba) | franka-ros |
| **crisp-controllers** | CRISP ROS2 controllers from utiasDSL for real-time robotic control | franka-ros2 |

### Main Frameworks

Core robotics frameworks and libraries:

| Package | Description | Dependencies |
|---------|-------------|--------------|
| **ros2-humble** | ROS 2 Humble - Headless control system with ros-base and dev tools | build-essential |
| **ros-noetic** | ROS Noetic installed through RoboStack/micromamba with desktop tools and development environment | robostack |
| **franka-ros** | Franka Emika ROS integration for control (via RoboStack/micromamba) | ros-noetic |
| **franka-ros2** | Franka Robotics ROS2 packages for Franka Emika Panda robot integration | ros2-humble, libfranka-fr3 |
| **pinocchio** | Pinocchio rigid body dynamics library (built from source) | None |
| **robostack** | RoboStack with micromamba - Conda-based ROS environment manager | None |

### Utilities

Essential tools and libraries:

| Package | Description | Dependencies |
|---------|-------------|--------------|
| **build-essential** | Essential build tools and development environment (gcc, g++, make, cmake, python3-dev, etc.) | None |
| **libfranka-gen1** | libfranka 0.9.2 for Panda robot control | None |
| **libfranka-fr3** | libfranka 0.16.1 for FR3 robot control | pinocchio |
| **rt-control-tools** | Real-time control and communication software tools (monitoring, testing, analysis) | None |
| **example-custom** | Example custom package showing how to create recipes | None |

### Testing Status

**✅ Runtime Tested:** libfranka-gen1, polymetis, franka-ros (on Franka gen1 hardware)  
**⚠️ Build Tested Only:** libfranka-fr3, franka-ros2, and others (need hardware validation)

### Package Locations

After installation, software is typically located in:
- `~/libfranka/` - libfranka libraries
- `/opt/ros/humble/` - ROS2 installation
- `~/deoxys/` - Deoxys control stack
- Custom packages usually install to `~/`

## Dependency Resolution

The package manager automatically resolves and installs dependencies in the correct order:

```console
# Install deoxys-control (automatically installs build-essential, libfranka-gen1)
servobox pkg-install deoxys-control

# Install serl-franka-controllers (automatically installs ros-noetic, franka-ros)
servobox pkg-install serl-franka-controllers
```

## Creating Custom Recipes

Learn how to create custom package recipes for ServoBox.

### Recipe Structure

A recipe consists of two files in `packages/recipes/<package-name>/`:

```
packages/recipes/my-package/
├── recipe.conf        # Metadata (required)
├── install.sh         # Installation script (required)
└── run.sh            # Optional: Execution script
```

### Quick Start

#### 1. Create Recipe Directory

**Option A: In ServoBox repository (for contributing)**
```console
cd /path/to/servobox
mkdir -p packages/recipes/my-package
cd packages/recipes/my-package
```

**Option B: In your home directory (for testing/private recipes)**
```console
mkdir -p ~/my-recipes/my-package
cd ~/my-recipes/my-package
```

#### 2. Write recipe.conf

```bash
name="my-package"
version="1.0.0"
description="My custom robotics package"
dependencies=""  # Optional: e.g., "build-essential ros2-humble"
```

#### 3. Write install.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Installing my-package..."

# Install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y build-essential cmake libeigen3-dev

# Clone repository
cd /home/servobox-usr
git clone https://github.com/user/my-package.git
cd my-package

# Build
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install

# Set ownership
chown -R servobox-usr:servobox-usr /home/servobox-usr/my-package

echo "✅ my-package installed successfully!"
```

#### 4. Make Executable and Test

```console
chmod +x install.sh

# Test installation
servobox pkg-install my-package --verbose
# Or for custom directory:
servobox pkg-install --custom ~/my-recipes my-package --verbose
```

### Recipe Files Explained

#### recipe.conf

Required fields:
```bash
name="package-name"              # Package identifier (must match directory name)
version="1.0.0"                  # Package version
description="Short description"  # One-line description
```

Optional fields:
```bash
dependencies="pkg1 pkg2"         # Space-separated ServoBox packages
```

#### install.sh

**Requirements:**
- Must be executable (`chmod +x`)
- Must use bash (`#!/usr/bin/env bash`)
- Should use `set -euo pipefail` for safety
- Should print status messages

**Best practices:**
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Installing my-package..."
export DEBIAN_FRONTEND=noninteractive

# Install apt dependencies
apt-get update
apt-get install -y cmake git libeigen3-dev

# Work in user home directory
cd /home/servobox-usr

# Clone, build, install
git clone https://github.com/user/my-package.git
cd my-package
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install
sudo ldconfig

echo "✅ my-package installed successfully!"
```

#### run.sh (Optional)

For packages with executable components:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Starting my-package..."
cd /home/servobox-usr/my-package
./my-executable --config config.yaml
```

### Custom Recipe Development

Use `--custom` to test recipes from your home directory without modifying system directories:

```console
mkdir -p ~/my-recipes/my-package
# Edit recipe files...
servobox pkg-install --custom ~/my-recipes my-package
```

This approach lets you:
- ✅ Develop without sudo access
- ✅ Test privately before sharing
- ✅ Iterate quickly
- ✅ Keep recipes in separate Git repos

### Sharing Your Recipes

#### Contribute to ServoBox

We welcome contributions! If you've created a useful robotics software stack recipe, consider contributing it to the main ServoBox repository:

1. **Fork** the ServoBox repository
2. **Add** your recipe to `packages/recipes/`
3. **Test** thoroughly
4. **Submit** a pull request

#### Keep Private

For company-specific or proprietary recipes, you can:
- Keep them in private Git repositories
- Share internally with your team
- Use the `--custom` flag to install from your own recipe directories

## Troubleshooting

### Common Issues

**Package installation fails:**
```console
# Check VM exists and is shut down
servobox status

# Try with verbose output
servobox pkg-install <package> --verbose
```

**Dependency not found:**
- Dependencies must be declared in `recipe.conf`
- Use `packages/scripts/package-manager.sh deps <package>` to check dependency tree

**Recipe not found:**
```console
# List available packages
servobox pkg-install --list

# Check recipe exists
ls packages/recipes/
```

## Best Practices

1. **Declare dependencies** in `recipe.conf` - let the package manager handle installation order
2. **Preview dependencies** with `package-manager.sh deps <package>`
3. **Keep install scripts idempotent** - safe to run multiple times
4. **Test recipes** on a fresh VM before sharing
5. **Use custom recipe directories** for development/testing
6. **Error handling**: Use `set -euo pipefail` in scripts
7. **Progress feedback**: Print status messages during installation
8. **Version pinning**: Use specific versions/tags in recipes
9. **Cleanup**: Remove temporary files after installation

## See Also

- [Commands Reference](commands.md) - Command details
- [FAQ](../reference/faq.md) - Common questions and troubleshooting

