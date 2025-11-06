#!/usr/bin/env bash
set -euo pipefail

# Common APT helper functions for ServoBox recipes

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

# Ensure DNS is configured (critical for virt-customize environment)
# This prevents network operations from hanging indefinitely
ensure_dns() {
    if [[ ! -f /etc/resolv.conf ]] || ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
        echo "Configuring DNS for network operations..."
        mkdir -p /etc
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    fi
}

# Initialize DNS on script load (runs automatically when sourced)
ensure_dns

# Installation tracking directory
SERVOBOX_INSTALL_DIR="/var/lib/servobox"
SERVOBOX_INSTALLED_PACKAGES="${SERVOBOX_INSTALL_DIR}/installed-packages"

# Ensure installation tracking directory exists
ensure_install_tracking() {
    mkdir -p "${SERVOBOX_INSTALL_DIR}"
    touch "${SERVOBOX_INSTALLED_PACKAGES}"
}

# Check if a package is already installed
is_package_installed() {
    local package="$1"
    ensure_install_tracking
    grep -q "^${package}$" "${SERVOBOX_INSTALLED_PACKAGES}" 2>/dev/null
}

# Mark a package as installed
mark_package_installed() {
    local package="$1"
    ensure_install_tracking
    if ! is_package_installed "$package"; then
        echo "$package" >> "${SERVOBOX_INSTALLED_PACKAGES}"
    fi
}

# List all installed packages
list_installed_packages() {
    ensure_install_tracking
    cat "${SERVOBOX_INSTALLED_PACKAGES}" 2>/dev/null || true
}

# Remove a package from installed list (for uninstall scenarios)
unmark_package_installed() {
    local package="$1"
    ensure_install_tracking
    if [[ -f "${SERVOBOX_INSTALLED_PACKAGES}" ]]; then
        grep -v "^${package}$" "${SERVOBOX_INSTALLED_PACKAGES}" > "${SERVOBOX_INSTALLED_PACKAGES}.tmp" || true
        mv "${SERVOBOX_INSTALLED_PACKAGES}.tmp" "${SERVOBOX_INSTALLED_PACKAGES}"
    fi
}

apt_update() {
	# Ensure DNS is configured before network operations
	ensure_dns
	# Add timeout to prevent indefinite hangs (5 minutes)
	timeout 300 apt-get update || { echo "Error: apt-get update timed out or failed" >&2; exit 1; }
}

apt_install() {
	# Usage: apt_install pkg1 pkg2 ...
	# Ensure DNS is configured before network operations
	ensure_dns
	# Add timeout to prevent indefinite hangs (10 minutes)
	timeout 600 apt-get install -y --no-install-recommends "$@" || { echo "Error: apt-get install failed or timed out" >&2; exit 1; }
}

apt_purge_autoremove() {
	# Usage: apt_purge_autoremove pkg1 pkg2 ...
	# Purge optional build-time deps when appropriate
	apt-get purge -y --auto-remove "$@" || true
}

apt_cleanup() {
	apt-get clean
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
}


