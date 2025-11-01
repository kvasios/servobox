# ServoBox Run Guide

Get up and running with a real-time VM, verify performance, set up networking, and install control stacks. For in-depth options, follow the links to the User Guide.

## 1) Create your first RT VM

```console
servobox init
```

- Defaults: name `servobox-vm`, 4 vCPUs, 8GB RAM, 40GB disk, NAT `192.168.122.100`.
- First run downloads the base image (cached afterwards).

!!! note "First Time Setup"
    If this is your first time running `servobox init`, you'll be added to the `libvirt` group.
    Activate the group membership in your current shell:
    ```console
    exec sg libvirt newgrp
    ```
    Or simply log out and log back in (permanent solution).

Start it:

```console
servobox start
```

- VM lifecycle details: [Commands Reference](../user-guide/commands.md)

## 2) Verify RT configuration and latency

```console
servobox rt-verify          # Check pinning, IRQs, kernel params
servobox test --duration 30 # Quick cyclictest
```

## 3) Networking

Configure or change networking after creation:

```console
servobox network-setup --name my-vm  # Interactive NIC wizard
```

- Network configuration: [Networking](../user-guide/networking.md)

## 4) Install packages and run stacks

The package installer adds pre-configured robotics stacks into your VM image and resolves dependencies automatically.

Basics:

```console
# Discover packages
servobox pkg-install --list

# Install a stack (deps auto-installed)
servobox pkg-install serl-franka-controllers

# Run a stack's launch helper
servobox run serl-franka-controllers

# Target a specific VM
servobox pkg-install --name my-vm libfranka-gen1

# Use custom/local recipes
servobox pkg-install --custom ~/my-recipes my-package

# Show detailed progress
servobox pkg-install ros2-humble --verbose
```

- Details: [Package Management](../user-guide/package-management.md)
- Catalog: [Available Packages](../user-guide/package-management.md#available-packages)

## 5) SSH access

```console
servobox ssh --name my-vm
```

SSH details are covered in the [Network Configuration](../user-guide/networking.md) guide.

## Troubleshooting

- Quick diagnostics and common fixes: [Troubleshooting](../reference/troubleshooting.md)
