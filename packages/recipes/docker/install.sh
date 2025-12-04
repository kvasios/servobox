#!/usr/bin/env bash
set -euo pipefail

# Docker installation script
echo "Installing Docker..."

export DEBIAN_FRONTEND=noninteractive

# Prefer helper injected by the package manager when customizing images
if [[ -n "${PACKAGE_HELPERS:-}" && -f "${PACKAGE_HELPERS}" ]]; then
  # shellcheck source=/dev/null
  . "${PACKAGE_HELPERS}"
else
  # Fallback to repo-relative helper for local execution
  if [[ -f "$(cd "$(dirname "$0")/../.." && pwd)/scripts/pkg-helpers.sh" ]]; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "$0")/../.." && pwd)/scripts/pkg-helpers.sh"
  fi
fi

# Check if already installed
if is_package_installed "${PACKAGE_NAME:-docker}"; then
    echo "Package ${PACKAGE_NAME:-docker} is already installed, skipping..."
    exit 0
fi

# Install prerequisites
apt_update
apt_install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
mkdir -m 0755 -p /etc/apt/keyrings
if [[ -f /etc/apt/keyrings/docker.gpg ]]; then
    rm -f /etc/apt/keyrings/docker.gpg
fi
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt_update

# Install Docker Engine
apt_install \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Configure permissions for servobox-usr
if id "servobox-usr" &>/dev/null; then
    echo "Adding servobox-usr to docker group..."
    usermod -aG docker servobox-usr
else
    echo "Warning: servobox-usr user not found, skipping group assignment."
fi

apt_cleanup

mark_package_installed "${PACKAGE_NAME:-docker}"

echo "Docker installation completed!"

