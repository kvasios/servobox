#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this installer as root, for example:"
  echo "  curl -fsSL https://www.servobox.dev/install.sh | sudo bash"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: ServoBox currently supports APT-based Ubuntu hosts."
  exit 1
fi

keyring_path="/usr/share/keyrings/servobox-archive-keyring.gpg"
source_path="/etc/apt/sources.list.d/servobox.list"
repo_url="https://www.servobox.dev/apt-repo"
key_url="${repo_url}/servobox-archive-keyring.gpg"

tmp_key="$(mktemp)"
trap 'rm -f "${tmp_key}"' EXIT

echo "Installing ServoBox APT signing key..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${key_url}" -o "${tmp_key}"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${tmp_key}" "${key_url}"
else
  echo "ERROR: install curl or wget, then run this installer again."
  exit 1
fi

install -d -m 0755 /usr/share/keyrings
install -m 0644 "${tmp_key}" "${keyring_path}"

echo "Configuring ServoBox APT repository..."
cat > "${source_path}" <<EOF
deb [signed-by=${keyring_path}] ${repo_url}/ stable main
EOF
chmod 0644 "${source_path}"

echo "Updating package metadata..."
apt-get update

echo "Installing ServoBox..."
DEBIAN_FRONTEND=noninteractive apt-get install -y servobox

echo "ServoBox installed successfully."
