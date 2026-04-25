# Package Management

ServoBox packages are recipe-driven install workflows for common robotics stacks, libraries, and utility toolchains.

## Overview

The package system provides:

- prebuilt recipes for common robotics software
- dependency resolution between ServoBox packages
- a unified install workflow for local VMs and remote RT targets
- optional custom recipe directories for your own stacks

Default recipes are served by the external `servobox-recipes` channel. ServoBox downloads the latest channel release into a user-writable cache on first use, then installs recipes from that cache.

## Default Install Mode In 0.3.0

Starting with `0.3.0`, `servobox pkg-install` installs over SSH by default and shows live progress output. For local VMs, ServoBox starts the VM automatically if needed and restores the previous state afterward.

The older image-mutation workflow still exists behind `--offline`.

## Quick Start

```console
# See what is available
servobox pkg-install --list

# Create project-local defaults when you want a one-command install later
servobox config init

# Inspect or refresh the recipe channel cache
servobox recipes status
servobox recipes update

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
servobox pkg-install [package|config] [--name NAME] [--verbose|-v] [--offline] [--list] [--custom PATH]
```

Key options:

- `--name NAME`: target a specific VM
- `--verbose` or `-v`: show more detailed installation output
- `--offline`: use the legacy image-based install flow
- `--list`: show available packages and configs
- `--custom PATH`: point to a custom recipe directory or config file

If the current project has `.servobox/config`, `servobox pkg-install` can use:

- `SERVOBOX_PKG_INSTALL`: the default package, channel config, or config-file path
- `SERVOBOX_PKG_CUSTOM`: a custom recipe directory or config file, often `.servobox/recipes`

### Manage the recipe channel

```console
servobox recipes status
servobox recipes update
```

By default ServoBox fetches:

```text
https://github.com/kvasios/servobox-recipes/releases/latest/download/servobox-recipes.tar.gz
```

Useful overrides:

- `SERVOBOX_RECIPE_CHANNEL_URL`: use a different recipe release archive or `git+https://...` channel
- `SERVOBOX_RECIPE_CACHE_DIR`: use a different local cache directory

### Show installed packages

```console
servobox pkg-installed [--name NAME] [--verbose|-v]
```

### Preview dependencies from the repo

```console
scripts/servobox-tools/package-manager.sh --recipe-dir "$(servobox recipes status | awk -F': ' '/Cache:/{print $2}')/recipes" deps <package>
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

The package list comes from the active recipe channel:

```console
servobox pkg-install --list
```

Recipe source, cache path, and update time are visible with:

```console
servobox recipes status
```

Recipe-specific testing status now lives with each recipe in the external `servobox-recipes` repository.

## Dependency Resolution

ServoBox resolves ServoBox package dependencies automatically:

```console
servobox pkg-install deoxys-control
servobox pkg-install serl-franka-controllers
```

## Creating Custom Recipes

Custom recipes let you keep private packages outside the public ServoBox recipe channel while still using the same install workflow.

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

For a client project, keep private recipes under `.servobox/recipes` and put this in `.servobox/config`:

```bash
SERVOBOX_PKG_INSTALL="my-package"
SERVOBOX_PKG_CUSTOM=".servobox/recipes"
```

Then the project install is simply:

```console
servobox pkg-install
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
scripts/servobox-tools/package-manager.sh --recipe-dir "$(servobox recipes status | awk -F': ' '/Cache:/{print $2}')/recipes" deps <package>
```

## See Also

- [Commands Reference](commands.md)
- [FAQ](../reference/faq.md)

