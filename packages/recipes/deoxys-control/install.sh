#!/usr/bin/env bash
set -euo pipefail

# deoxys-control installation script

echo "Installing deoxys-control dependencies and cloning sources..."

export DEBIAN_FRONTEND=noninteractive

# Ensure helpers are available when running inside image via package manager
if [[ -n "${PACKAGE_HELPERS:-}" && -f "${PACKAGE_HELPERS}" ]]; then
  # shellcheck source=/dev/null
  . "${PACKAGE_HELPERS}"
else
  # Fallback to local helpers when running directly
  if [[ -f "$(cd "$(dirname "$0")/.." && pwd)/scripts/pkg-helpers.sh" ]]; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "$0")/.." && pwd)/scripts/pkg-helpers.sh"
  fi
fi

# Verify expected home directory exists (do not create it here)
if [[ ! -d /home/servobox-usr ]]; then
  echo "Error: /home/servobox-usr does not exist" >&2
  exit 1
fi

# Refresh shared library cache (important when installing via virt-customize after libfranka)
ldconfig || true

# Base build prerequisites via apt
apt_update || apt-get update || true
apt_install build-essential cmake git libpoco-dev libeigen3-dev || apt-get install -y build-essential cmake git libpoco-dev libeigen3-dev

# For protoc (protobuf toolchain)
apt_install autoconf automake libtool curl make g++ unzip || apt-get install -y autoconf automake libtool curl make g++ unzip
apt_install protobuf-compiler libprotobuf-dev libprotoc-dev || apt-get install -y protobuf-compiler libprotobuf-dev libprotoc-dev

# For ZeroMQ
apt_install libzmq3-dev || apt-get install -y libzmq3-dev

# Build tooling helpers
apt_install pkg-config || apt-get install -y pkg-config

# Additional apt packages
apt_install libyaml-cpp-dev libspdlog-dev || apt-get install -y libyaml-cpp-dev libspdlog-dev
apt_install libreadline-dev bzip2 libmotif-dev libglfw3 || apt-get install -y libreadline-dev bzip2 libmotif-dev libglfw3

# Clone deoxys_control dev branch into user home (shallow)
cd /home/servobox-usr
rm -rf deoxys_control
echo "Cloning deoxys_control (shallow) into /home/servobox-usr/deoxys_control..."
git clone --depth 1 --single-branch --branch dev https://github.com/kvasios/deoxys_control.git deoxys_control

# Initialize and update submodules
echo "Initializing and updating submodules..."
cd deoxys_control
git submodule update --init --recursive
cd ..

chown -R servobox-usr:servobox-usr /home/servobox-usr/deoxys_control || true

PROTOV_REQUIRED_MINOR=13

# Prepare a temporary workspace for optional source fallbacks
BUILD_DIR="/tmp/deoxys-deps"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Prefer distro protobuf; fallback to source if version < 3.13
if command -v protoc >/dev/null 2>&1; then
  PROTOC_VER=$(protoc --version | awk '{print $2}')
  PROTOC_MAJOR=$(echo "$PROTOC_VER" | cut -d. -f1)
  PROTOC_MINOR=$(echo "$PROTOC_VER" | cut -d. -f2)
else
  PROTOC_MAJOR=0
  PROTOC_MINOR=0
fi

if [[ "${PROTOC_MAJOR}" -lt 3 || "${PROTOC_MINOR}" -lt ${PROTOV_REQUIRED_MINOR} ]]; then
  echo "System protobuf too old ($PROTOC_MAJOR.$PROTOC_MINOR); building v3.13.0 from source..."
  cd "$BUILD_DIR"
  rm -rf protobuf-3.13.0
  echo "Downloading protobuf v3.13.0 C++ release tarball..."
  curl -sSL -o protobuf-3.13.0.tar.gz https://github.com/protocolbuffers/protobuf/releases/download/v3.13.0/protobuf-cpp-3.13.0.tar.gz
  tar -xzf protobuf-3.13.0.tar.gz
  cd protobuf-3.13.0
  echo "Building protobuf v3.13.0 via configure/make (skip tests)..."
  ./configure --prefix=/usr/local
  make -j"$(nproc)"
  make install
  # Ensure /usr/local/lib has priority in dynamic linker search path
  echo "/usr/local/lib" > /etc/ld.so.conf.d/usr-local-protobuf.conf
  ldconfig
  cd "$BUILD_DIR"
else
  echo "Using distro protobuf (protoc $PROTOC_MAJOR.$PROTOC_MINOR)"
fi

# Ensure we prefer /usr/local binaries (protoc 3.13) over system ones
if [[ -x /usr/local/bin/protoc ]]; then
  export PATH="/usr/local/bin:${PATH}"
fi

# Show effective protoc being used
if command -v protoc >/dev/null 2>&1; then
  echo "Using protoc from: $(command -v protoc) ($(protoc --version))"
else
  echo "Warning: protoc not found on PATH after setup" >&2
fi

# Build and install libzmqpp from submodule
echo "Building and installing libzmqpp from submodule..."
cd /home/servobox-usr/deoxys_control/zmqpp || { echo "Error: zmqpp submodule not found" >&2; exit 1; }
make -j"$(nproc)"
make install
ldconfig

# Ensure pkg-config finds the new protobuf first
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Clear any previous CMake cache so Protobuf detection re-runs with the right protoc
# Also clear any pkg-config or CMake module cache that might incorrectly detect zmqpp
if [[ -d /home/servobox-usr/deoxys_control/deoxys/build ]]; then
  echo "Removing old build directory to ensure clean CMake configuration..."
  rm -rf /home/servobox-usr/deoxys_control/deoxys/build || true
fi

# Build deoxys_control
echo "Building deoxys_control with cmake (Release, BUILD_FRANKA=1)..."
cd /home/servobox-usr/deoxys_control/deoxys || { echo "Error: deoxys directory not found" >&2; exit 1; }

# Create build directory
mkdir -p build
cd build

# Configure with cmake (set CMAKE_PREFIX_PATH to help find libfranka in virt-customize environment)
# Also set RPATH to ensure runtime picks up /usr/local/lib libraries (protobuf 3.13)
# Set SKIP_BUILD_RPATH=FALSE and enable RPATH for build tree executables
# Force Protobuf_ROOT to ensure CMake finds the right protobuf
# Set LDFLAGS to prioritize /usr/local/lib during linking
export LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
CMAKE_PREFIX_PATH="/usr/local:/usr" \
Protobuf_ROOT="/usr/local" \
cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_FRANKA=1 \
  -DCMAKE_SKIP_BUILD_RPATH=FALSE \
  -DCMAKE_BUILD_RPATH="/usr/local/lib" \
  -DCMAKE_INSTALL_RPATH="/usr/local/lib" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=TRUE \
  -DProtobuf_INCLUDE_DIR=/usr/local/include \
  -DProtobuf_LIBRARY=/usr/local/lib/libprotobuf.so \
  -DProtobuf_PROTOC_EXECUTABLE=/usr/local/bin/protoc \
  ..

# Build with make (use -j2 to avoid OOM in virt-customize with limited memory)
make -j2

cd /home/servobox-usr/deoxys_control
chown -R servobox-usr:servobox-usr /home/servobox-usr/deoxys_control || true

# Cleanup apt caches if available via helpers
apt_cleanup || true

echo "deoxys-control built and dependencies installed."


