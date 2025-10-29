# Commands Reference

Complete reference for all ServoBox commands.

## Overview

ServoBox provides a simple command-line interface for managing RT VMs:

```console
servobox <command> [options]
```

## Commands

### `init`

Create and configure a new RT VM (without starting it).

**Usage:**
```console
servobox init [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--name NAME` | VM domain name | `servobox-vm` |
| `--vcpus N` | Number of virtual CPUs | `4` |
| `--mem MiB` | Memory size in MiB | `8192` |
| `--disk GB` | Disk size in GB | `40` |
| `--bridge NAME` | Use host bridge instead of NAT | (NAT) |
| `--host-nic DEV` | Add direct NIC (macvtap), max 2, repeatable | none |
| `--choose-nic` | Interactively select host NICs (max 2) | no prompt |
| `--image PATH` | Use local base image | (download) |
| `--ip CIDR` | Static IP for NAT NIC | `192.168.122.100/24` |
| `--ssh-pubkey PATH` | Use specific SSH public key | (auto-detect) |
| `--ssh-key PATH` | Use specific SSH private key for connection | (auto-detect) |

**Examples:**

```console
# Default configuration
servobox init

# Custom specifications
servobox init --vcpus 6 --mem 16384 --disk 80

# Named VM for specific project
servobox init --name franka-dev --vcpus 4

# Use local base image
servobox init --image ./base.qcow2

# Bridge networking
servobox init --bridge br0

# Add direct NIC for robot (single device)
servobox init --host-nic eth0

# Dual robot setup
servobox init --host-nic eth0 --host-nic eth1

# Interactive NIC selection
servobox init --choose-nic

# Custom static IP
servobox init --ip 192.168.122.50/24

# Use specific SSH key
servobox init --ssh-pubkey ~/.ssh/my-key.pub
```

**What it does:**

1. Downloads or locates base RT image
2. Creates VM storage directory
3. Creates VM disk from base image
4. Generates cloud-init seed ISO
5. Defines libvirt domain with RT configuration
6. Applies CPU pinning and IRQ affinity

---

### `start`

Start a VM and apply RT configuration.

**Usage:**
```console
servobox start [--name NAME]
```

**Examples:**

```console
# Start default VM
servobox start

# Start named VM
servobox start --name franka-dev
```

**What it does:**

1. Starts the libvirt domain
2. Applies CPU pinning to isolated cores
3. Configures IRQ affinity
4. Waits for VM to boot

---

### `stop`

Gracefully shutdown a VM.

**Usage:**
```console
servobox stop [--name NAME]
```

**Examples:**

```console
servobox stop
servobox stop --name franka-dev
```

**Note:** This performs a graceful shutdown (ACPI). For force power-off, use `virsh destroy <name>`.

---

### `status`

Show VM status and configuration information.

**Usage:**
```console
servobox status [--name NAME]
```

**Examples:**

```console
servobox status
```

**Output includes:**

- VM state (running, shut off, etc.)
- vCPU count and pinning
- Memory allocation
- Network interfaces and IP addresses
- Disk paths

---

### `ip`

Print the VM's IPv4 address.

**Usage:**
```console
servobox ip [--name NAME]
```

**Examples:**

```console
servobox ip

# Use in scripts
VM_IP=$(servobox ip --name my-vm)
ssh servobox-usr@$VM_IP
```

---

### `ssh`

SSH into the VM as user `servobox-usr`.

**Usage:**
```console
servobox ssh [--name NAME]
```

**Examples:**

```console
# Interactive SSH
servobox ssh

# Specific VM
servobox ssh --name my-vm
```

**Note:** Uses your local SSH keys (automatically added via cloud-init).

---

### `network-setup`

Interactive wizard to configure network interfaces after VM creation.

**Usage:**
```console
servobox network-setup [--name NAME]
```

**Examples:**

```console
# Configure network for default VM
servobox network-setup

# Configure named VM
servobox network-setup --name franka-dev
```

**What it does:**

1. Checks if VM exists and stops it if running
2. Launches interactive wizard to select host NICs (up to 2)
3. Reconfigures VM network interfaces
4. Injects persistent netplan configuration
5. Redefines VM with new network setup

**Use cases:**

- Add direct NICs after initial VM creation
- Change network configuration for new devices
- Set up dual robot communication
- Switch NICs when hardware changes

---

### `destroy`

Power off and remove the VM and all associated storage.

**Usage:**
```console
servobox destroy [--name NAME] [-f|--force]
```

**Examples:**

```console
servobox destroy
servobox destroy --name old-vm --force
```

**⚠️ Warning:** This permanently deletes the VM disk! There is no undo.

**What it does:**

1. Powers off the VM (if running)
2. Undefines the libvirt domain
3. Deletes VM storage directory (`/var/lib/libvirt/images/servobox/<name>/`)

---

### `test`

Run cyclictest to measure RT latency.

**Usage:**
```console
servobox test [--name NAME] [--duration SECONDS] [--stress-ng]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--duration SEC` | Test duration in seconds | `60` |
| `--stress-ng` | Enable host stress testing | disabled |

**Examples:**

```console
# Basic test (60 seconds)
servobox test

# Quick test
servobox test --duration 30

# Stress test (recommended for validation)
servobox test --duration 60 --stress-ng

# Named VM
servobox test --name franka-dev --duration 120
```

**Interpreting output:** Use `servobox rt-verify` and the Troubleshooting guide.

---

### `rt-verify`

Verify RT configuration (CPU pinning, IRQ affinity, XML settings, governors, guest kernel params).

**Usage:**
```console
servobox rt-verify [--name NAME]
```

**Notes:** Requires the VM to be running.


---

### `pkg-install`

Install packages or package configurations into the VM.

**Usage:**
```console
servobox pkg-install <package|config.conf> [--name NAME] [--verbose|-v] [--list|-l] [--force] [--custom PATH]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--list`, `-l` | List available packages and configs |
| `--verbose`, `-v` | Show detailed installation output |
| `--force` | Reinstall even if already installed |
| `--custom PATH` | Path to custom recipe directory OR config file |

**Examples:**

```console
# List available packages
servobox pkg-install --list

# Install a package
servobox pkg-install libfranka-gen1

# Install from config file
servobox pkg-install --custom ./my-suite.conf

# Use custom recipe directory
servobox pkg-install --custom ~/my-recipes my-package

# Force reinstall with verbose
servobox pkg-install libfranka-gen1 --force --verbose

# Named VM
servobox pkg-install libfranka-gen1 --name franka-dev
```

See [Package Management](package-management.md) for details.

---

### `pkg-installed`

Show packages already installed in the VM.

**Usage:**
```console
servobox pkg-installed [--name NAME] [--verbose|-v]
```

---

### `run`

Execute a package's run script in the VM, or run an arbitrary command.

**Usages:**
```console
# Run a recipe's run.sh
servobox run <recipe-name> [--name NAME]

# Run an arbitrary command in the VM
servobox run "<command>" [--name NAME]
```

**Examples:**

```console
# Run polymetis server
servobox run polymetis

# Run with specific VM
servobox run polymetis --name franka-dev

# Run arbitrary command
servobox run "sudo pkill -9 run_server" --name franka-dev
```

**What it does (recipe mode):**

1. Ensures the VM is running
2. Executes the recipe's `run.sh` inside the VM
3. Keeps terminal open for monitoring

**Recipes with run.sh include:** `polymetis`, `deoxys-control`, `libfranka-gen1`, `serl-franka-controllers`, `franka-ros`, `libfranka-fr3`.

---

### `help`

Show help message.

**Usage:**
```console
servobox --help
servobox -h
```

---

### Check VM Status

```console
servobox status
servobox ip
virsh list --all  # See all VMs
```

### Clean Up

```console
# Stop VM
servobox stop

# Or completely remove
servobox destroy
```

## See Also

- [Package Management](package-management.md) - Installing software packages
- [Network Configuration](networking.md) - VM networking setup
- [Troubleshooting](../reference/troubleshooting.md) - Common issues

