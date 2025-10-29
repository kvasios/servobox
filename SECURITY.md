# Security Model & Audit

This document outlines ServoBox's security model, sudo requirements, and security considerations.

## Security Philosophy

ServoBox is designed with transparency and minimal privilege escalation:

1. **Open Source** - All code is reviewable
2. **Standard Tools Only** - Uses Ubuntu/Debian standard packages (libvirt, QEMU, cloud-init)
3. **Minimal Sudo** - Only used where absolutely necessary for RT configuration and VM management
4. **No Remote Execution** - No automatic downloads from untrusted sources
5. **User Control** - User explicitly initiates all operations

## Sudo Usage Audit

### When Sudo is Required

ServoBox requires sudo for these legitimate operations:

#### 1. **Real-Time Configuration** (during `servobox start`)
   - **Purpose**: Set RT priorities and CPU affinity for QEMU threads
   - **Commands**:
     - `sudo taskset -cp` - Pin QEMU vCPU threads to isolated cores
     - `sudo chrt -f -p` - Set SCHED_FIFO RT priority for threads
     - `sudo tee /sys/devices/system/cpu/.../scaling_governor` - Set CPU governor to performance
     - `sudo tee /proc/irq/.../smp_affinity*` - Route IRQs away from RT cores
   - **Why**: Linux requires root to set SCHED_FIFO priorities and modify system CPU/IRQ settings
   - **Security**: Only modifies scheduling/affinity, doesn't execute user code

#### 2. **Libvirt VM Management** (if user not in `libvirt` group)
   - **Purpose**: Access `/var/lib/libvirt/` directories
   - **Commands**:
     - `sudo mkdir -p /var/lib/libvirt/images/...` - Create VM storage directory
     - `sudo cloud-localds` - Generate cloud-init seed ISO
     - `sudo chown libvirt-qemu:kvm` - Set proper ownership for VM files
     - `sudo rm -rf` - Clean up VM directories during destroy
   - **Why**: `/var/lib/libvirt/` is owned by `libvirt-qemu:kvm`
   - **Mitigation**: Add user to `libvirt` group to avoid this (recommended in docs)

#### 3. **Image Customization** (during `servobox pkg-install`)
   - **Purpose**: Modify VM disk images via libguestfs
   - **Commands**:
     - `sudo virt-customize -a <image>` - Install packages into VM image
   - **Why**: libguestfs may need root to access `/dev/kvm` and mount images
   - **Mitigation**: Add user to `kvm` group (documented)
   - **Security**: Only modifies offline VM images, not live system

### What Sudo Does NOT Do

ServoBox **NEVER** uses sudo to:
- ❌ Download or execute remote scripts
- ❌ Modify host system configuration (except RT tuning as above)
- ❌ Install host packages
- ❌ Modify user's home directory
- ❌ Access user's private data
- ❌ Make persistent system changes (except VM files in `/var/lib/libvirt/`)

## Network Security

### Host Network Access

**Internet Access**:
- VMs connect to internet via libvirt's NAT bridge (`virbr0`)
- Same network access as user's account
- No special routing or firewall bypass

**Isolation**:
- VMs are isolated from host system by QEMU/KVM
- NAT provides network isolation (VMs on 192.168.122.0/24)
- No automatic port forwarding to host

### VM Downloads

**Base Image Download**:
- Downloads Ubuntu 22.04 cloud image from official Ubuntu servers
- URL is hardcoded in code: `https://cloud-images.ubuntu.com/...`
- Verifies SHA256 checksums (stored in `data/jammy-cloudimg.url`)
- User can override with `--image` flag for custom images

**GitHub Release Downloads** (optional):
- If configured, can download pre-built RT images from GitHub releases
- Requires user to set `GITHUB_TOKEN` environment variable
- Only downloads from repo owner's releases (configurable)
- User can audit URLs in `vm-image.sh`

**Package Installation in VM**:
- Recipe scripts may download software (e.g., ROS2, libfranka)
- Downloads happen **inside the VM**, not on host
- Uses standard `apt-get` or `git clone` from official sources
- User can audit recipe scripts in `/usr/share/servobox/recipes/`

## VM Security Model

### VM Isolation

**Hypervisor**:
- VMs run in QEMU/KVM (industry-standard, well-audited)
- Full hardware virtualization
- Memory isolation enforced by hardware

**User Account in VM**:
- Default user: `servobox-usr`
- Default password: `servobox-pwd` (for local VMs only)
- Has passwordless sudo: `sudo: ALL=(ALL) NOPASSWD:ALL`
- **Rationale**: VMs are development/testing environments, not production servers
- **Security Note**: Default credentials are intentional for local development
  - VMs are NAT-isolated by default (not exposed to internet)
  - Users can change password with `passwd` command inside VM
  - Cloud-init can override credentials during VM creation
- User should not store sensitive data in VMs

### SSH Access

**Key-Based Authentication**:
- Uses user's SSH public keys from `~/.ssh/`
- Keys injected via cloud-init at VM creation
- No password authentication by default (key-only)

**VM Network Access**:
- VM accessible only from host by default (NAT)
- No inbound connections from internet
- User can configure bridge networking for LAN access (optional)

## Threat Model

### What ServoBox Protects Against

✅ **Accidental System Damage**:
- VMs are isolated from host system
- Destructive operations require explicit commands (`destroy`)
- No automatic modifications to host

✅ **Privilege Escalation**:
- Sudo is used minimally and transparently
- No SUID binaries or setuid operations
- User can audit all sudo usage

✅ **Supply Chain Attacks**:
- Base images from official Ubuntu
- Checksums verified
- Recipe scripts are auditable
- No obfuscated code

### What ServoBox Does NOT Protect Against

⚠️ **Malicious Recipe Scripts**:
- Custom recipes can contain arbitrary code
- Runs inside VM, but VM has internet access
- User must audit custom recipes before use

⚠️ **Compromised VM Attacking Host**:
- If VM is compromised, it could attempt to attack host via network
- Standard hypervisor isolation applies
- Use firewall rules if concerned

⚠️ **Data Exfiltration from VM**:
- VMs have internet access
- Don't store sensitive data in VMs
- VMs are for development/testing, not production

## Security Best Practices

### For Users

1. **Add yourself to groups** (avoid sudo prompts):
   ```bash
   sudo usermod -aG libvirt,kvm $USER
   newgrp libvirt
   ```

2. **Audit custom recipes** before using them:
   ```bash
   cat /usr/share/servobox/recipes/<package>/install.sh
   ```

3. **Don't store sensitive data in VMs**:
   - VMs have internet access
   - VMs are ephemeral development environments

4. **Use firewall** if VMs need LAN access:
   ```bash
   sudo ufw enable
   sudo ufw allow from 192.168.122.0/24
   ```

5. **Keep host system updated**:
   ```bash
   sudo apt update && sudo apt upgrade
   ```

### For Developers (Contributing Recipes)

1. **Use official package sources** (Ubuntu, GitHub releases)
2. **Verify checksums** for downloads
3. **Avoid hardcoded credentials** in recipes
4. **Document what the recipe downloads**
5. **Use HTTPS** for all downloads
6. **Pin versions** when possible (reproducibility)

## Incident Response

If you discover a security issue:

1. **Do NOT open a public GitHub issue**
2. **Email**: konstantinos.vasios@gmail.com
3. **Include**:
   - Description of the issue
   - Steps to reproduce
   - Potential impact
   - Suggested fix (optional)

We will respond within 48 hours and work on a fix.

## Security Checklist for Going Public

Before making the repository public, we've verified:

- [x] No hardcoded credentials or secrets in code
- [x] No personal/sensitive information in git history
- [x] All sudo usage is documented and justified
- [x] Network operations use HTTPS and verify checksums
- [x] Recipe scripts are auditable and documented
- [x] Security model is clearly documented
- [x] Contact method for security issues provided

## Compliance & Standards

ServoBox follows these security principles:

- **Principle of Least Privilege**: Only requests necessary permissions
- **Defense in Depth**: Multiple layers of isolation (VM, NAT, user groups)
- **Transparency**: All operations are logged and auditable
- **Fail-Safe**: Errors don't leave system in insecure state
- **Separation of Concerns**: VM operations separate from host operations

## Audit Trail

All operations log to stdout/stderr. For detailed audit:

```bash
# ServoBox logs all operations to stdout/stderr
servobox init
servobox start

# Check libvirt logs for VM operations
sudo journalctl -u libvirtd -f

# Check VM console
virsh console <vm-name>

# Enable verbose output for package installation
servobox pkg-install <package> --verbose
```

## License & Liability

ServoBox is provided under the MIT License. See LICENSE file.

**No Warranty**: Software is provided "as is" without warranty.

**User Responsibility**: Users are responsible for securing their VMs and data.

---

**Last Updated**: 2025-10-27
**Audit Version**: 1.0

