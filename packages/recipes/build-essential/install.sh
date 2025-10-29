#!/usr/bin/env bash
set -euo pipefail

# Build essential tools installation script
echo "Installing build essential tools..."

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

# Check if already installed (optional - package manager handles this, but good for local testing)
if is_package_installed "${PACKAGE_NAME:-build-essential}"; then
    echo "Package ${PACKAGE_NAME:-build-essential} is already installed, skipping..."
    exit 0
fi

apt_update
apt_install \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    python3-pip \
    python3-dev \
    python3-venv

apt_cleanup

# Mark package as installed (package manager will also do this, but good for consistency)
mark_package_installed "${PACKAGE_NAME:-build-essential}"

echo "Build essential tools installation completed!"
