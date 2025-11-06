# Changelog

## 0.1.3 (2025-11-06)

### Fixed
- **Network Setup Boot Delays**: Fixed critical issue where VMs booted after `servobox network-setup` experienced 30-60 second delays before SSH became available. Root causes and fixes:
  - Added `optional: true` to macvtap NIC netplan configs to prevent systemd-networkd from blocking boot waiting for interfaces
  - Implemented first-boot flag (`/var/lib/servobox-first-boot-done`) to skip expensive cloud-init operations (DNS tests, apt-get installs) on subsequent boots, reducing boot time from 30-60s to 5-10s
  - Fixed hanging operations: added timeouts to virsh commands, use `mv -f` to avoid file overwrite prompts, prefer non-interactive sudo with clear error messages
  - Regenerate cloud-init seed during `network-setup` to ensure VMs get updated fast-boot configuration
  - Improved error handling: gracefully handle non-existent VMs, check VM existence before querying, provide clear error messages

## 0.1.2 (2025-11-02)

### Fixed
- **Package Tracking Cleanup**: Fixed critical issue where `servobox destroy` did not clear the package tracking file (`~/.local/share/servobox/tracking/<vm-name>.servobox-packages`). This caused newly created VMs to incorrectly show packages as already installed even though they were not present in the fresh VM. Now properly removes tracking file during VM destruction.
- **Package Install Silent Failure**: Fixed issue where `servobox pkg-install` would fail silently on fresh Ubuntu installations due to libguestfs permission errors (cannot read `/boot/vmlinuz-*`). Now detects kernel readability upfront and prompts for sudo credentials before starting installation, providing clear feedback instead of failing silently. This resolves the mystery of why installations only worked with `-v` (verbose) flag.

## 0.1.1 (2025-11-01)

### Fixed
- **Fresh Install Support**: Fixed critical issue where `servobox init` failed on fresh Ubuntu installations due to group membership not being active in current shell. Now uses sudo for network operations and provides clear instructions to activate group membership with `exec sg libvirt newgrp`
- **Dependencies**: Added `stress-ng` as a required dependency in `debian/control` - it will now be automatically installed with the package
- **Package Management**: Fixed permission issues with `servobox pkg-install` by moving tracking files from `/var/lib/libvirt/images/` to `~/.local/share/servobox/tracking/` (no sudo needed)
- **Network Setup**: Ensure libvirt's default network is automatically created, started, and enabled for autostart. Fixes "network not found" errors after fresh install or reboot
- **VM Persistence**: Fixed issue where VMs created with `servobox init` were not found after PC reboot by:
  - Automatically adding user to `libvirt` and `kvm` groups during init
  - Enabling `libvirtd` to start automatically on boot
  - Checking and starting `libvirtd` in both `init` and `start` commands
  - Providing helpful error messages with troubleshooting steps

### Changed
- Improved user experience on fresh installations with automatic group membership and service configuration
- Updated all documentation (README, docs) with correct first-time setup workflow including group activation step

## 0.1.0 (2025-10-20)

### Added
- Initial release
- One-command RT VM launcher with Ubuntu 22.04 PREEMPT_RT
- Automatic CPU pinning and IRQ isolation
- Package management system for robot control software
- Support for libfranka, franka-ros, polymetis, and more
- APT repository for easy installation
