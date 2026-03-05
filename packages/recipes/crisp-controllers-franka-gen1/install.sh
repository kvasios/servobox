#!/usr/bin/env bash
set -euo pipefail

echo "Installing crisp-controllers-franka-gen1 (Pixi + pixi_panda_ros2)..."

export DEBIAN_FRONTEND=noninteractive

# Load helper functions if available
if [[ -n "${PACKAGE_HELPERS:-}" && -f "${PACKAGE_HELPERS}" ]]; then
  # shellcheck source=/dev/null
  . "${PACKAGE_HELPERS}"
else
  if [[ -f "$(cd "$(dirname "$0")/../.." && pwd)/scripts/pkg-helpers.sh" ]]; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "$0")/../.." && pwd)/scripts/pkg-helpers.sh"
  fi
fi

# Determine target user and home directory
if [[ -n "${SERVOBOX_INSTALL_USER:-}" ]]; then
  TARGET_USER="${SERVOBOX_INSTALL_USER}"
elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="${SUDO_USER}"
elif id "servobox-usr" &>/dev/null; then
  TARGET_USER="servobox-usr"
else
  TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home/ {print $1; exit}')
  [[ -z "${TARGET_USER}" ]] && TARGET_USER="root"
fi
[[ "${TARGET_USER}" == "root" ]] && TARGET_HOME="/root" || TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
[[ -z "${TARGET_HOME}" ]] && TARGET_HOME="/home/${TARGET_USER}"
echo "Installing for user: ${TARGET_USER} (home: ${TARGET_HOME})"
mkdir -p "${TARGET_HOME}"

echo "Installing system dependencies..."
apt_update || true
apt_install curl git ca-certificates build-essential pkg-config || true

PIXI_DEFAULT="${TARGET_HOME}/.pixi/bin/pixi"

if [[ ! -x "${PIXI_DEFAULT}" ]]; then
  echo "Pixi not found. Installing Pixi for ${TARGET_USER}..."
  su - "${TARGET_USER}" -c 'curl -fsSL https://pixi.sh/install.sh | bash' </dev/null
fi

PIXI="${PIXI_DEFAULT}"
if [[ ! -x "${PIXI}" ]]; then
  PIXI="$(su - "${TARGET_USER}" -c 'command -v pixi || true' </dev/null)"
fi
if [[ -z "${PIXI}" || ! -x "${PIXI}" ]]; then
  echo "Error: pixi executable not found after installation." >&2
  exit 1
fi
echo "Using pixi at: ${PIXI}"

REPO_DIR="${TARGET_HOME}/pixi_panda_ros2"
REPO_URL="https://github.com/kvasios/pixi_panda_ros2.git"

echo "Fetching pixi_panda_ros2..."
if [[ -d "${REPO_DIR}/.git" ]]; then
  su - "${TARGET_USER}" -c "
    set -e
    cd '${REPO_DIR}'
    git fetch --all --prune
    git pull --ff-only || true
    git submodule sync --recursive
    git submodule update --init --recursive
  " </dev/null
else
  su - "${TARGET_USER}" -c "
    set -e
    cd '${TARGET_HOME}'
    rm -rf '${REPO_DIR}'
    git clone --recurse-submodules '${REPO_URL}' '${REPO_DIR}'
  " </dev/null
fi

# Limit parallel make jobs to avoid OOM when compiling heavy packages (crisp_controllers, Pinocchio, etc.)
# Default -j1 for VMs with limited RAM; set MAKEFLAGS=-j2 or higher if the target has plenty of memory.
export MAKEFLAGS="${MAKEFLAGS:--j2}"

echo "Running setup (pixi run -e jazzy setup)..."
su - "${TARGET_USER}" -c "
  set -e
  export MAKEFLAGS=\"${MAKEFLAGS}\"
  cd '${REPO_DIR}'
  '${PIXI}' run -e jazzy setup
" </dev/null

chown -R "${TARGET_USER}:${TARGET_USER}" "${REPO_DIR}" "${TARGET_HOME}/.pixi" 2>/dev/null || true

apt_cleanup || true

echo "crisp-controllers-franka-gen1 installation completed successfully."

