# Experimental Host Tuning

!!! warning "Experimental Content"
    The settings on this page are **untested with ServoBox** and provided as potential future directions for users who want to experiment.

---

## Purpose

ServoBox's balanced mode already achieves excellent RT performance (~4μs avg, ~100-120μs max). The settings below are for:

- **Experimentation** - Understanding latency sources in your system
- **99.99% guarantees** - Reducing spike frequency from ~1 per 10k to ~1 per 100k cycles
- **Future research** - Community testing of advanced tuning approaches

**If you try these and have interesting results, please [share them on GitHub](https://github.com/kvasios/servobox/discussions)!**

---

## BIOS/UEFI Settings

Access your system BIOS (usually F2, Del, or F12 during boot). Settings vary by manufacturer:

### 1. Disable C-States

- `C-States` → **Disabled** or **C0/C1 Only**
- `Package C-State Limit` → **C0/C1**

**Impact:** System idles at 40-60W instead of 5-10W

### 2. Disable Turbo Boost

- Intel: `Intel Turbo Boost Technology` → **Disabled**
- AMD: `Core Performance Boost` → **Disabled**

**Impact:** CPU runs at base frequency (e.g., 3.4GHz instead of 5.0GHz boost)

### 3. Disable Hyper-Threading / SMT

- Intel: `Hyper-Threading Technology` → **Disabled**
- AMD: `SMT Mode` → **Disabled**

**Impact:** Available threads cut in half (16-core → 8 threads)

### 4. Disable Power Management

- `Intel SpeedStep` / `AMD Cool'n'Quiet` → **Disabled**
- `EIST` → **Disabled**

### 5. Reduce SMI Sources

- `PCIe ASPM` → **Disabled**
- `USB Legacy Support` → **Disabled** (⚠️ USB keyboard won't work until OS loads)

---

## Runtime Configuration

If BIOS access isn't available:

**Disable Turbo Boost:**

```bash
# Intel
echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo

# AMD
echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost
```

**Limit C-States (add to `/etc/default/grub`):**

```text
intel_idle.max_cstate=1 processor.max_cstate=1
```

Most aggressive (prevents any idle):

```text
idle=poll
```

Then:

```bash
sudo update-grub
sudo reboot
```

**Disable SMT:**

```bash
echo off | sudo tee /sys/devices/system/cpu/smt/control
```

---

## Monitor Power and Temperature

```bash
# Install tools
sudo apt install lm-sensors

# Check temperatures
watch -n 1 sensors

# Check CPU package power (if supported)
sensors | grep Package
```

**Expected power increase:**

- Turbo OFF: +5-10W
- C-States OFF: +30-50W idle
- `idle=poll`: +60-100W idle

---

## Expected Results

**In VMs (ServoBox):**

- Max latency: Still ~100-120μs
- Spike frequency: May improve slightly
- Average: Minimal change

**On Bare-Metal RT Linux:**

These settings can achieve <50μs max latency on bare-metal RT Linux systems.

---

## Alternative: Bare-Metal RT

If you need <50μs consistently, consider bare-metal RT Linux instead of ServoBox:

- [Ubuntu Pro Real-Time Kernel](https://ubuntu.com/security/livepatch)
- [PREEMPT_RT Kernel Patch](https://wiki.linuxfoundation.org/realtime/start)

**Trade-offs:** Lose GPU compatibility (NVIDIA), lose VM isolation, reduce host throughput

---

## Share Your Results

Tried these settings? We'd love to hear about it!

- **Found improvements?** Share your configuration and test results
- **Hit issues?** Help others avoid pitfalls
- **Different hardware?** AMD results especially welcome

[Open a discussion on GitHub →](https://github.com/kvasios/servobox/discussions)

