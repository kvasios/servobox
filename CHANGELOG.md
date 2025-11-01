# Changelog

## 0.1.1 (2025-11-01)

### Fixed
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

## 0.1.0 (2025-10-20)

### Added
- Initial release
- One-command RT VM launcher with Ubuntu 22.04 PREEMPT_RT
- Automatic CPU pinning and IRQ isolation
- Package management system for robot control software
- Support for libfranka, franka-ros, polymetis, and more
- APT repository for easy installation