# Jetson: Flash Ubuntu to NVMe (APX recovery + initrd flash)

Scope: Jetson devkits. Example commands target **Orin Nano / JetPack 6 (L4T R36.4.3) / Ubuntu 22.04**.

This page uses the **NVIDIA BSP + sample rootfs** workflow. It does **not** use generic Ubuntu installer images.

---

## Requirements

- Use a supported Ubuntu host (20.04/22.04). Prefer bare metal.
- Use a **data-capable** USB cable. Avoid hubs.
- Keep all NVIDIA tarballs on the **same release** (e.g. all **R36.4.3**).
- Flash only when the board is in **APX recovery**.
- Do not point anything at the host’s `nvme0n1`.

---

## Files you need (example: R36.4.3)

- `Jetson_Linux_R36.4.3_aarch64.tbz2`
- `Tegra_Linux_Sample-Root-Filesystem_R36.4.3_aarch64.tbz2`

---

## Procedure

### 1) Extract BSP

```bash
mkdir -p ~/jetson/r36.4.3
cd ~/jetson/r36.4.3
tar xf Jetson_Linux_R36.4.3_aarch64.tbz2
```

### 2) Populate rootfs (required)

```bash
cd Linux_for_Tegra
sudo tar xf ../Tegra_Linux_Sample-Root-Filesystem_R36.4.3_aarch64.tbz2 -C rootfs
sudo ./apply_binaries.sh
```

Quick sanity checks:

```bash
test -f rootfs/etc/passwd
test -x rootfs/bin/cpio
test -x rootfs/usr/bin/lsblk
```

If any check fails: stop and fix rootfs first.

### 3) Put the Jetson in APX recovery

Power off the Jetson. Then:

- Hold **RECOVERY**
- Tap **RESET** (or power on)
- Release **RECOVERY** after ~1–2 seconds

Host check:

```bash
lsusb | grep -i nvidia
```

You want **APX** (good):

```
0955:75xx NVIDIA Corp. APX
```

If you see a running system (bad), do not flash:

```
0955:7020 L4T running on Tegra
```

### 4) Stop services that interfere with initrd flash

```bash
sudo systemctl stop rpcbind rpcbind.socket nfs-kernel-server || true
sudo pkill rpcbind || true
```

### 5) Flash QSPI boot firmware (once per board)

Example for Orin Nano devkit:

```bash
sudo ./flash.sh p3768-0000-p3767-0000-a0-qspi internal
```

Wait until it reports success.

### 6) Flash NVMe (install OS to NVMe)

```bash
sudo ./tools/kernel_flash/l4t_initrd_flash.sh \
  --external-device nvme0n1p1 \
  -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
  -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" \
  --showlogs --network usb0 \
  jetson-orin-nano-devkit internal
```

Notes:

- `nvme0n1p1` refers to the **Jetson NVMe** exposed during flashing, not the host.
- If board ID / SKU is empty, you are not in APX.

### 7) Boot

- Power off fully
- Power on normally
- First boot can take 1–2 minutes

If UEFI shows a boot menu: select NVMe and set it as default.

---

## Post-boot checks (on Jetson)

```bash
lsblk
```

Root filesystem should be on `nvme0n1*`.

```bash
cat /etc/os-release
uname -a
```

Expect Ubuntu 22.04 and a `*-tegra` kernel.

---

## Failure signatures (fast triage)

- `Board ID() sku() empty` / `Unrecognized module SKU` → not in APX recovery
- `cp: cannot stat rootfs/...` → rootfs not populated
- `dpkg: Exec format error` → host binfmt/qemu setup broken
- GRUB prompt / “installer” behavior → wrong workflow (you tried to treat it like a PC)

---

## Real-time kernel (RT)

For installing the real-time kernel follow the instructions:

- [Installing Real-Time Kernel — NVIDIA Jetson Linux Developer Guide (R36.4.4)](https://docs.nvidia.com/jetson/archives/r36.4.4/DeveloperGuide/SD/Kernel/RealTimeKernel.html)

!!! warning "RT kernel + NVMe boot pitfall (initrd mismatch)"
    On Jetson (e.g. Orin Nano, JetPack 6 / L4T R36.x), a **PREEMPT_RT kernel can reboot immediately** if it shares the stock initrd. The default `/boot/initrd` is built for the **generic tegra** kernel. When you select an RT kernel, early NVMe/Tegra modules may not load, rootfs mount fails, and the watchdog resets with no useful error.

    Fix: generate a **kernel-matched initrd** for the RT kernel (e.g. `update-initramfs -c -k <rt-kernel>`) and point the RT entry in `/boot/extlinux/extlinux.conf` to that **RT-specific initrd**. Do not share initrd images between generic and RT kernels.

!!! note "Allow real-time permissions (after RT kernel is running)"
    Create a realtime group and add the user that runs the robot:

    ```bash
    sudo addgroup realtime
    sudo usermod -a -G realtime "$(whoami)"
    ```

    Add limits to `/etc/security/limits.conf`:

    ```
    @realtime soft rtprio 99
    @realtime soft priority 99
    @realtime soft memlock 102400
    @realtime hard rtprio 99
    @realtime hard priority 99
    @realtime hard memlock 102400
    ```

    Log out and log back in to apply the limits.

---

## ServoBox Remote Target Mode

Once your Jetson has the RT kernel running, you can use **ServoBox** to manage it remotely from your development machine. This gives you the same workflow for Jetson as you have for local VMs.

### Setup

Set the environment variable to point to your Jetson:

```bash
export SERVOBOX_TARGET_IP=192.168.1.50    # Your Jetson's IP
```

The SSH user defaults to your current username (`$USER`). If your Jetson uses a different username, set it:

```bash
export SERVOBOX_TARGET_USER=nvidia        # Only if different from your local username
```

Optionally add to your `~/.bashrc` for persistence:

```bash
echo 'export SERVOBOX_TARGET_IP=192.168.1.50' >> ~/.bashrc
```

### Available Commands

With `SERVOBOX_TARGET_IP` set, these commands operate on your Jetson:

```bash
# Check status and RT configuration
servobox status          # System info, kernel version, RT check
servobox rt-verify       # Detailed RT configuration verification

# Run RT latency test
servobox test --duration 60

# Install packages
servobox pkg-install libfranka-gen1
servobox pkg-install robotics.conf    # Install from config file

# Run recipes or commands
servobox run polymetis                # Run recipe's run.sh
servobox run "sudo systemctl status"  # Run arbitrary command

# Connect via SSH
servobox ssh
```

### Example Workflow

```bash
# 1. Set target (user defaults to $USER)
export SERVOBOX_TARGET_IP=192.168.1.50

# 2. Verify connection and RT setup
servobox status
servobox rt-verify

# 3. Install control software (will prompt for sudo password)
servobox pkg-install libfranka-gen1

# 4. Run latency test (will prompt for sudo password)
servobox test --duration 120

# 5. Start the robot control application
servobox run polymetis
```

!!! tip "Passwordless sudo for convenience"
    To avoid repeated sudo password prompts, configure passwordless sudo on your Jetson:
    
    ```bash
    # On the Jetson:
    echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER
    ```

### Switching Between Local VM and Remote Jetson

To switch back to local VM mode, unset the environment variable:

```bash
unset SERVOBOX_TARGET_IP
servobox status  # Now shows local VM status
```

Or use different terminal sessions with different exports for managing multiple targets.
