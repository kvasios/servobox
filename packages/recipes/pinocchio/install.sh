#!/usr/bin/env bash
set -euo pipefail

# Pinocchio installation script (from source)

echo "Installing Pinocchio from source..."

export DEBIAN_FRONTEND=noninteractive

# Dependencies (required + useful optional)
apt-get update
apt-get install -y \
  build-essential \
  cmake \
  git \
  pkg-config \
  libeigen3-dev \
  libboost-all-dev \
  libassimp-dev \
  liburdfdom-dev \
  liburdfdom-headers-dev \
  liboctomap-dev \
  libfcl-dev

# Prepare user home for sources
mkdir -p /home/servobox-usr
cd /home/servobox-usr || { echo "Error: /home/servobox-usr not available" >&2; exit 1; }

# Clone (default to stable v2.7.1; allow PINOCCHIO_BRANCH override)
PINOCCHIO_BRANCH=${PINOCCHIO_BRANCH:-v2.7.1}
if [[ -d pinocchio ]]; then
  echo "pinocchio directory exists; checking git status..."
  if git -C pinocchio rev-parse --git-dir >/dev/null 2>&1; then
    echo "Updating existing repository..."
    git -C pinocchio fetch --all --tags
  else
    echo "Invalid/corrupted repo; removing and recloning..."
    rm -rf pinocchio
  fi
fi

if [[ ! -d pinocchio ]]; then
  git clone --recursive https://github.com/stack-of-tasks/pinocchio pinocchio
fi

git -C pinocchio checkout ${PINOCCHIO_BRANCH}
git -C pinocchio submodule update --init --recursive || true

# Build
cd pinocchio
rm -rf build
mkdir -p build
cd build

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DBUILD_PYTHON_INTERFACE=OFF \
  -DBUILD_TESTING=OFF

make -j"$(nproc)"
make install
ldconfig

# Persist environment variables
cat >> /home/servobox-usr/.bashrc << 'EOF'

# Pinocchio from source
export PATH=/usr/local/bin:${PATH:-}
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}
export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}
export CMAKE_PREFIX_PATH=/usr/local:${CMAKE_PREFIX_PATH:-}
EOF

echo "Pinocchio installation (from source) completed."

