# Package Management

ServoBox packages are recipe-driven install workflows for common robotics stacks, libraries, and utility toolchains.

## Overview

The package system provides:

- prebuilt recipes for common robotics software
- dependency resolution between ServoBox packages
- a unified install workflow for local VMs and remote RT targets
- optional custom recipe directories for your own stacks

## Default Install Mode In 0.3.0

Starting with `0.3.0`, `servobox pkg-install` installs over SSH by default and shows live progress output. For local VMs, ServoBox starts the VM automatically if needed and restores the previous state afterward.

The older image-mutation workflow still exists behind `--offline`.

## Quick Start

```console
# See what is available
servobox pkg-install --list

# Install into the default VM
servobox pkg-install docker

# Install a robotics stack
servobox pkg-install deoxys-control

# Show detailed logs
servobox pkg-install ros2-humble --verbose

# See what is already installed
servobox pkg-installed
```

## Common Commands

### Install a package

```console
servobox pkg-install <package|config> [--name NAME] [--verbose|-v] [--offline] [--list] [--custom PATH]
```

Key options:

- `--name NAME`: target a specific VM
- `--verbose` or `-v`: show more detailed installation output
- `--offline`: use the legacy image-based install flow
- `--list`: show available packages and configs
- `--custom PATH`: point to a custom recipe directory or config file

### Show installed packages

```console
servobox pkg-installed [--name NAME] [--verbose|-v]
```

### Preview dependencies from the repo

```console
packages/scripts/package-manager.sh deps <package>
```

## Remote Target Mode

The same package workflow can target an existing RT machine over SSH:

```console
export SERVOBOX_TARGET_IP=192.168.1.50
servobox pkg-install docker
servobox pkg-installed
```

Optional environment variables:

- `SERVOBOX_TARGET_USER`: SSH user, defaults to `$USER`
- `SERVOBOX_TARGET_PORT`: SSH port, defaults to `22`

This is useful for Jetson, NUC, and similar RT-capable systems where you want ServoBox recipes without creating a local VM.

## Install Modes

### Live install over SSH

This is the default in `0.3.0`.

- works with local VMs and remote RT targets
- shows live installation progress
- is the recommended mode for most users

### Offline image install

Use this only if you specifically want the older image-based flow:

```console
servobox pkg-install --offline docker
```

This mode is local-VM only.

## Available Packages

### Complete suites

| Package | Description | Dependencies |
|---------|-------------|--------------|
| `polymetis` | Polymetis server stack for Franka-based workflows | None |
| `deoxys-control` | `deoxys_control` for research and agent development | `libfranka-gen1` or `libfranka-fr3` depending on target |
| `serl-franka-controllers` | SERL Franka compliant Cartesian impedance controllers | `franka-ros` |
| `crisp-controllers` | CRISP ROS2 controllers for real-time robotic control | `franka-ros2` |

### Frameworks and libraries

| Package | Description | Dependencies |
|---------|-------------|--------------|
| `ros2-humble` | ROS 2 Humble headless environment and development tools | `build-essential` |
| `ros-noetic` | ROS Noetic via RoboStack/micromamba | `robostack` |
| `franka-ros` | Franka ROS integration | `ros-noetic` |
| `franka-ros2` | Franka ROS2 packages | `ros2-humble`, `libfranka-fr3` |
| `franky-fr3` | Franky for Franka Research 3 | None |
| `franky-gen1` | Franky for Franka Panda Gen1 | None |
| `franky-remote-fr3` | Franky remote control for FR3 | `franky-fr3` |
| `franky-remote-gen1` | Franky remote control for Panda Gen1 | `franky-gen1` |
| `ur_rtde` | Universal Robots RTDE interface | None |
| `pinocchio` | Pinocchio rigid body dynamics library | None |
| `robostack` | RoboStack with micromamba | None |

### Utilities

| Package | Description | Dependencies |
|---------|-------------|--------------|
| `build-essential` | Essential build tools and development packages | None |
| `docker` | Docker Engine, CLI, and Compose | None |
| `libfranka-gen1` | `libfranka` 0.9.2 for Panda Gen1 | None |
| `libfranka-fr3` | `libfranka` 0.16.1 for FR3 | `pinocchio` |
| `rt-control-tools` | Real-time testing and control utilities | None |
| `example-custom` | Example custom recipe | None |

### Testing status

- **Runtime tested:** `libfranka-gen1`, `polymetis`, `franka-ros` on Franka gen1 hardware
- **Build tested only:** `libfranka-fr3`, `franka-ros2`, and several other recipes that still need runtime validation

## Dependency Resolution

ServoBox resolves ServoBox package dependencies automatically:

```console
servobox pkg-install deoxys-control
servobox pkg-install serl-franka-controllers
```

## Creating Custom Recipes

Custom recipes let you keep private packages outside the main ServoBox repository while still using the same install workflow.

### Recipe structure

```text
my-recipes/my-package/
├── recipe.conf
├── install.sh
└── run.sh
```

- `recipe.conf` is required
- `install.sh` is required
- `run.sh` is optional

### Minimal example

Create a custom recipe directory:

```console
mkdir -p ~/my-recipes/my-package
cd ~/my-recipes/my-package
```

`recipe.conf`:

```bash
name="my-package"
version="1.0.0"
description="My custom package"
dependencies="build-essential"
```

`install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y cmake git

cd /home/servobox-usr
git clone https://github.com/user/my-package.git
cd my-package
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j"$(nproc)"
sudo make install
```

Test it:

```console
chmod +x install.sh
servobox pkg-install --custom ~/my-recipes my-package --verbose
```

### Tips

- declare dependencies in `recipe.conf`
- make install scripts idempotent when possible
- use `set -euo pipefail`
- print useful progress messages
- test on a fresh VM before sharing recipes with others

## Troubleshooting

If installation fails:

```console
servobox status
servobox pkg-install <package> --verbose
```

If a recipe or dependency cannot be found:

```console
servobox pkg-install --list
packages/scripts/package-manager.sh deps <package>
```

## See Also

- [Commands Reference](commands.md)
- [FAQ](../reference/faq.md)

