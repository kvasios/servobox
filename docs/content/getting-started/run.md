# First Run

This is the canonical first-use workflow for ServoBox after installation and host RT setup.

## Create Your First VM

```console
servobox init
```

Defaults:

- VM name: `servobox-vm`
- vCPUs: `4`
- memory: `8192` MiB
- disk: `16` GB
- primary NAT IP: `192.168.122.100/24`

The first run downloads the base RT image if it is not already cached.

If you want to customize the VM from the start:

```console
servobox init --name my-vm --vcpus 6 --mem 16384 --disk 80
```

## Start And Verify

Start the VM in the default balanced mode:

```console
servobox start
```

Verify the RT configuration and latency behavior:

```console
servobox rt-verify
servobox test --duration 30 --stress-ng
```

If you need tighter spike behavior, you can use:

```console
servobox start --performance
```

`--performance` and `--extreme` reduce spike frequency, but the practical VM latency ceiling is still around the same order of magnitude. See [RT Tuning](../reference/rt-tuning.md) for the full details.

## Install Your First Stack

`pkg-install` now installs into a running target over SSH by default in `0.3.0`, so you get live progress output.

```console
servobox pkg-install --list
servobox pkg-install deoxys-control
servobox run deoxys-control
```

Useful variations:

```console
# Install on a specific VM
servobox pkg-install --name my-vm docker

# Keep the legacy image-based installation mode
servobox pkg-install --offline docker

# Show detailed progress
servobox pkg-install ros2-humble --verbose
```

For the full package workflow, see [Package Management](../user-guide/package-management.md).

## Networking

If your VM needs direct access to a robot or another device NIC, use the interactive wizard:

```console
servobox network-setup
```

You can also attach NICs during VM creation:

```console
servobox init --host-nic eth0
servobox init --host-nic eth0 --host-nic eth1
```

More details: [Networking](../user-guide/networking.md)

## SSH Access

```console
servobox ssh
servobox ssh --name my-vm
```

## Remote Target Mode

ServoBox `0.3.0` can also operate on an existing RT machine over SSH instead of a local VM.

```console
export SERVOBOX_TARGET_IP=192.168.1.50
servobox status
servobox rt-verify
servobox pkg-install docker
```

Remote mode is useful for Jetson, NUC, or similar RT-capable systems where you want the same ServoBox package and verification workflow without creating a local VM.

## Next Step

- Browse the full [Commands Reference](../user-guide/commands.md)
- Review [Package Management](../user-guide/package-management.md)
- Use [Troubleshooting](../reference/troubleshooting.md) if verification fails
