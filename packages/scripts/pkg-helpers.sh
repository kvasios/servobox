#!/usr/bin/env bash
set -euo pipefail

# Common APT helper functions for ServoBox recipes

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

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
	apt-get update
}

apt_install() {
	# Usage: apt_install pkg1 pkg2 ...
	apt-get install -y --no-install-recommends "$@"
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


