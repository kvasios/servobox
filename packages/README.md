# ServoBox Package System

This directory contains software package recipes for building and installing software in ServoBox images, focused on headless real-time control systems and high-frequency communications.

## Structure

```
packages/
├── README.md                    # This file
├── recipes/                     # Individual package recipes
│   ├── ros2-humble/            # ROS 2 Humble (headless control)
│   ├── rt-control-tools/       # Real-time control tools
│   ├── build-essential/        # Build tools
│   └── ...
└── scripts/                     # Package management scripts
    ├── package-manager.sh      # Main package manager
    └── pkg-helpers.sh          # Helper functions for recipes
```

## Package Recipe Format

Each package recipe is a directory containing:

- `recipe.conf` - Package metadata, build configuration, and dependencies
- `install.sh` - Installation script
- `patches/` - Optional patches to apply (if needed)

### Dependencies

Dependencies are declared in `recipe.conf` using the `dependencies` field:

```bash
dependencies="package1 package2"  # space or comma-separated
```

The package manager automatically resolves and installs dependencies in the correct order using topological sorting.

## Usage

### Building with packages

```bash
# Build image with specific packages (comma-separated)
./scripts/build-image.sh --packages "build-essential,ros2-humble"
./scripts/build-image.sh --packages "libfranka-gen1,deoxys-control"

# Note: For build-time installs, list packages in dependency order
# For runtime installs, dependencies are automatically resolved
```

### Managing packages

```bash
# List available packages
./packages/scripts/package-manager.sh list

# Show dependency tree for a package
./packages/scripts/package-manager.sh deps serl-franka-controllers

# Build a specific package
./packages/scripts/package-manager.sh build ros2-humble

# Install a package (with automatic dependency resolution)
./packages/scripts/package-manager.sh install ros2-humble image.qcow2

# List packages already installed in an image (instant, no VM mount needed)
./packages/scripts/package-manager.sh installed image.qcow2

# Sync tracking file from VM (if tracking file is lost/corrupted)
./packages/scripts/package-manager.sh sync-tracking image.qcow2

# Validate package recipes
./packages/scripts/package-manager.sh validate
```

## Creating New Packages

1. Create a new directory under `packages/recipes/`
2. Add `recipe.conf` with package metadata and dependencies
3. Create `install.sh` with build/install steps
4. Test with `servobox pkg-install <package-name> --verbose`

See `packages/recipes/example-custom/` for a comprehensive template.

### Important Notes

- **Dependencies are automatic**: Declare dependencies in `recipe.conf`, don't handle them manually in `install.sh`
- **No manual checks needed**: The package manager validates dependencies before installation
- **Topological sorting**: Dependencies are always installed in the correct order
- **Circular dependency detection**: The system will error if circular dependencies are detected
- **Smart installation tracking**: Packages are automatically tracked using a host-side file (`.servobox-packages`) to avoid re-installing already installed dependencies
  - **Instant checks**: No VM mounting needed - checks are instant (~0.01s vs ~2s)
  - **Reliable**: Tracking file stored next to VM image, survives VM reboots
  - **Recovery**: Use `sync-tracking` command if tracking file gets out of sync
- **Force reinstall**: Use `--force` flag to reinstall packages even if they're already installed
