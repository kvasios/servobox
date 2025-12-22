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
