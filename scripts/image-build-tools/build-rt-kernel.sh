#!/usr/bin/env bash
set -Eeuo pipefail

# build-rt-kernel.sh
# Builds a PREEMPT_RT Linux kernel as Debian packages, following the Franka Robotics guide.
# References: https://frankarobotics.github.io/docs/installation_linux.html#setting-up-the-real-time-kernel
#
# Scope: stops after building packages. Does NOT install the kernel or adjust system limits.
#
# Usage examples:
#   scripts/build-rt-kernel.sh --kernel 6.8 --rt 8
#   scripts/build-rt-kernel.sh --kernel 5.4.19 --rt 10 --verify-signatures
#   scripts/build-rt-kernel.sh --kernel 6.8 --rt 8 --jobs 16 --no-deps
#
# Outputs are organized under build/rt-kernel/<kernel>-rt<rt>/

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
# Compute a safe default for parallel jobs: prefer (nproc - 4) but never below 1
DEFAULT_JOBS=$(nproc)
if [[ "${DEFAULT_JOBS}" -gt 4 ]]; then
  DEFAULT_JOBS=$(( DEFAULT_JOBS - 4 ))
else
  DEFAULT_JOBS=1
fi

# Configurable flags
# Defaults can be overridden by CLI flags
KERNEL_VER="6.8"
RT_VER="8"
JOBS="${DEFAULT_JOBS}"
VERIFY=false
INSTALL_DEPS=true
FORCE=false
KEEP_WORK=false
ASSUME_YES=false
PKG_TARGET="bindeb-pkg"

# Colors for UX
if [[ -t 1 ]]; then
  COLOR_GREEN='\033[0;32m'
  COLOR_YELLOW='\033[1;33m'
  COLOR_RED='\033[0;31m'
  COLOR_BLUE='\033[0;34m'
  COLOR_RESET='\033[0m'
else
  COLOR_GREEN=''
  COLOR_YELLOW=''
  COLOR_RED=''
  COLOR_BLUE=''
  COLOR_RESET=''
fi

log_info() { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; }
log_warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
log_success() { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
log_error() { echo -e "${COLOR_RED}[ERR]${COLOR_RESET} $*" 1>&2; }

usage() {
  cat <<EOF
Build a PREEMPT_RT Linux kernel into Debian packages.

Optional (when no args are given, defaults to --kernel 6.8 --rt 8):
  --kernel <X.Y[.Z]>   Linux kernel version (e.g., 6.8 or 5.4.19)
  --rt <N>             RT patch level (e.g., 8 for -rt8)

Optional:
  --jobs <N>           Parallel jobs for make (default: max(1, nproc-4))
  --verify-signatures  Verify downloaded .tar.sign and .patch.sign (requires gpg)
  --no-deps            Skip apt dependency installation
  --force              Overwrite existing build directory if present
  --keep-work          Keep unpacked source tree after build
  --yes                Assume yes to prompts (overwrite deb artifacts if present)
  --pkg-target <t>     Kernel packaging target: bindeb-pkg (default) or deb-pkg
  -h, --help           Show this help

Examples:
  scripts/build-rt-kernel.sh                 # uses defaults: --kernel 6.8 --rt 8
  scripts/build-rt-kernel.sh --kernel 6.8 --rt 8
  scripts/build-rt-kernel.sh --kernel 5.4.19 --rt 10 --verify-signatures
EOF
}

abort() {
  log_error "$*"
  exit 1
}

trap 'abort "An unexpected error occurred. Check logs for details."' ERR

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kernel)
        KERNEL_VER=${2:-}; shift 2 ;;
      --rt)
        RT_VER=${2:-}; shift 2 ;;
      --jobs)
        JOBS=${2:-}; shift 2 ;;
      --verify-signatures)
        VERIFY=true; shift ;;
      --no-deps)
        INSTALL_DEPS=false; shift ;;
      --force)
        FORCE=true; shift ;;
      --keep-work)
        KEEP_WORK=true; shift ;;
      --yes)
        ASSUME_YES=true; shift ;;
      --pkg-target)
        PKG_TARGET=${2:-}; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        abort "Unknown argument: $1" ;;
    esac
  done

  [[ -n "${KERNEL_VER}" ]] || abort "--kernel is required"
  [[ -n "${RT_VER}" ]] || abort "--rt is required"
  if ! [[ "${JOBS}" =~ ^[0-9]+$ ]] || [[ "${JOBS}" -lt 1 ]]; then
    abort "--jobs must be a positive integer"
  fi
  case "${PKG_TARGET}" in
    bindeb-pkg|deb-pkg) ;;
    *) abort "--pkg-target must be 'bindeb-pkg' or 'deb-pkg'" ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || abort "Missing required command: $1"
}

install_deps() {
  if ! ${INSTALL_DEPS}; then
    log_info "Skipping dependency installation (--no-deps)."
    return
  fi
  require_cmd sudo
  log_info "Installing build dependencies via apt..."
  sudo apt-get update -y
  sudo apt-get install -y \
    build-essential bc curl debhelper dpkg-dev devscripts fakeroot \
    libssl-dev libelf-dev bison flex cpio kmod rsync libncurses-dev \
    xz-utils tar patch gpg
  log_success "Dependencies installed."
}

# Construct kernel.org URLs based on version
# Sets global:
#   TAR_VER           -> version string used for kernel tar/sign filenames (e.g., 6.8 or 5.4.19)
#   RT_BASE_VER       -> version string used in RT patch filenames (6.8 if patchlevel is 0, else full like 5.4.19)
#   KERNEL_TAR_URL, KERNEL_TAR_SIGN_URL, RT_PATCH_URL, RT_PATCH_SIGN_URL
compute_urls() {
  # Determine major stream e.g., 6.x or 5.x
  local major minor patch
  IFS='.' read -r major minor patch <<<"${KERNEL_VER}"
  if [[ -z "${major}" || -z "${minor}" ]]; then
    abort "--kernel must be like X.Y or X.Y.Z (got: ${KERNEL_VER})"
  fi

  local kernel_major_dir="v${major}.x"
  local base_kernel="https://www.kernel.org/pub/linux/kernel/${kernel_major_dir}"
  # Normalize tar version: if patchlevel missing or 0 -> use X.Y, else X.Y.Z
  if [[ -z "${patch}" || "${patch}" == "0" ]]; then
    TAR_VER="${major}.${minor}"
  else
    TAR_VER="${major}.${minor}.${patch}"
  fi
  KERNEL_TAR_URL="${base_kernel}/linux-${TAR_VER}.tar.xz"
  KERNEL_TAR_SIGN_URL="${base_kernel}/linux-${TAR_VER}.tar.sign"

  # RT patch series directory usually <major>.<minor>, with some versions keeping patches under .../older/
  local rt_series="${major}.${minor}"
  local base_rt="https://www.kernel.org/pub/linux/kernel/projects/rt/${rt_series}"
  # Normalize RT patch base: if patchlevel missing or 0 -> use X.Y, else X.Y.Z
  if [[ -z "${patch}" || "${patch}" == "0" ]]; then
    RT_BASE_VER="${major}.${minor}"
  else
    RT_BASE_VER="${major}.${minor}.${patch}"
  fi
  RT_PATCH_URL="${base_rt}/patch-${RT_BASE_VER}-rt${RT_VER}.patch.xz"
  RT_PATCH_SIGN_URL="${base_rt}/patch-${RT_BASE_VER}-rt${RT_VER}.patch.sign"
}

# Try a fallback URL placing patch under an older/ subdir
try_rt_fallback_url() {
  local rt_series
  IFS='.' read -r rt_series _ <<<"${KERNEL_VER}"
  local major minor rest
  IFS='.' read -r major minor rest <<<"${KERNEL_VER}"
  local base_rt_older="https://www.kernel.org/pub/linux/kernel/projects/rt/${major}.${minor}/older"
  # Use normalized RT_BASE_VER for fallback
  if [[ -z "${RT_BASE_VER:-}" ]]; then
    # compute RT_BASE_VER if not already set
    local patch
    IFS='.' read -r _ _ patch <<<"${KERNEL_VER}"
    if [[ -z "${patch}" || "${patch}" == "0" ]]; then
      RT_BASE_VER="${major}.${minor}"
    else
      RT_BASE_VER="${KERNEL_VER}"
    fi
  fi
  RT_PATCH_URL="${base_rt_older}/patch-${RT_BASE_VER}-rt${RT_VER}.patch.xz"
  RT_PATCH_SIGN_URL="${base_rt_older}/patch-${RT_BASE_VER}-rt${RT_VER}.patch.sign"
}

http_head_ok() {
  curl -fsIL "$1" >/dev/null 2>&1
}

download_if_missing() {
  local url="$1"
  local outfile="$2"
  if [[ -f "${outfile}" ]]; then
    log_info "Found existing $(basename -- "${outfile}"); skipping download."
    return 0
  fi
  log_info "Downloading $(basename -- "${outfile}")"
  curl -fL --retry 3 -o "${outfile}" "${url}"
}

download_sources() {
  log_info "Preparing source downloads..."
  mkdir -p "${BUILD_DIR}/sources"
  pushd "${BUILD_DIR}/sources" >/dev/null

  log_info "Checking RT patch URL..."
  if ! http_head_ok "${RT_PATCH_URL}"; then
    log_warn "RT patch not found at primary location; trying older/ fallback..."
    try_rt_fallback_url
    http_head_ok "${RT_PATCH_URL}" || abort "RT patch not found at: ${RT_PATCH_URL}"
  fi

  log_info "Ensuring kernel ${TAR_VER} and RT patch -rt${RT_VER} sources are present"
  download_if_missing "${KERNEL_TAR_URL}" "linux-${TAR_VER}.tar.xz"
  download_if_missing "${KERNEL_TAR_SIGN_URL}" "linux-${TAR_VER}.tar.sign"
  download_if_missing "${RT_PATCH_URL}" "patch-${RT_BASE_VER}-rt${RT_VER}.patch.xz"
  download_if_missing "${RT_PATCH_SIGN_URL}" "patch-${RT_BASE_VER}-rt${RT_VER}.patch.sign"

  log_success "Sources downloaded."
  popd >/dev/null
}

verify_signatures() {
  ${VERIFY} || return 0
  log_info "Verifying signatures..."
  pushd "${BUILD_DIR}/sources" >/dev/null
  local verify_log="${BUILD_DIR}/logs/verify.log"
  : > "${verify_log}"

  if ! command -v gpg >/dev/null 2>&1; then
    abort "gpg not installed but --verify-signatures was requested"
  fi

  set +e
  gpg --verify "linux-${TAR_VER}.tar.sign" "linux-${TAR_VER}.tar" >>"${verify_log}" 2>&1
  local rc_tar=$?
  gpg --verify "patch-${RT_BASE_VER}-rt${RT_VER}.patch.sign" "patch-${RT_BASE_VER}-rt${RT_VER}.patch" >>"${verify_log}" 2>&1
  local rc_patch=$?
  set -e

  if [[ ${rc_tar} -ne 0 || ${rc_patch} -ne 0 ]]; then
    log_error "Signature verification failed. See logs/verify.log"
    exit 1
  fi
  log_success "Signatures verified."
  popd >/dev/null
}

unpack_and_patch() {
  log_info "Unpacking sources and applying RT patch..."
  pushd "${BUILD_DIR}/sources" >/dev/null
  xz -df "linux-${TAR_VER}.tar.xz"
  xz -df "patch-${RT_BASE_VER}-rt${RT_VER}.patch.xz"
  tar xf "linux-${TAR_VER}.tar"
  popd >/dev/null

  SRC_DIR="${BUILD_DIR}/sources/linux-${TAR_VER}"
  pushd "${SRC_DIR}" >/dev/null
  patch -p1 < "${BUILD_DIR}/sources/patch-${RT_BASE_VER}-rt${RT_VER}.patch"
  log_success "RT patch applied."
  popd >/dev/null
}

configure_kernel() {
  log_info "Configuring kernel for PREEMPT_RT..."
  pushd "${SRC_DIR}" >/dev/null
  cp -v "/boot/config-$(uname -r)" .config

  # Use scripts/config to adjust options as per guide
  # Disable debug info and debug kernel
  scripts/config --disable DEBUG_INFO || true
  scripts/config --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT || true
  scripts/config --disable DEBUG_KERNEL || true
  # Disable trusted keyring
  scripts/config --disable SYSTEM_TRUSTED_KEYS || true
  scripts/config --disable SYSTEM_REVOCATION_LIST || true
  # Activate Fully Preemptible RT
  scripts/config --disable PREEMPT_NONE || true
  scripts/config --disable PREEMPT_VOLUNTARY || true
  scripts/config --disable PREEMPT || true
  scripts/config --enable PREEMPT_RT || true

  make olddefconfig
  log_success "Kernel configured."
  popd >/dev/null
}

build_kernel() {
  log_info "Building Debian packages (this may take a while)..."
  pushd "${SRC_DIR}" >/dev/null
  local build_log="${BUILD_DIR}/logs/build.log"
  : > "${build_log}"
  make -j"${JOBS}" "${PKG_TARGET}" >>"${build_log}" 2>&1
  popd >/dev/null
  log_success "Build completed. Collecting artifacts..."
}

collect_artifacts() {
  mkdir -p "${BUILD_DIR}/debs"
  # Collect debs from parent of source dir
  local parent_dir
  parent_dir=$(dirname -- "${SRC_DIR}")
  shopt -s nullglob
  local debs=("${parent_dir}"/linux-image-*.deb "${parent_dir}"/linux-headers-*.deb "${parent_dir}"/linux-libc-dev_*.deb)
  local copied=0
  # If destination has existing debs, prompt before overwriting
  local existing=("${BUILD_DIR}/debs"/*.deb)
  if [[ ${#existing[@]} -gt 0 && -e "${existing[0]}" ]]; then
    if ! ${ASSUME_YES}; then
      echo -n "Deb artifacts already exist in ${BUILD_DIR}/debs. Overwrite them? [y/N]: "
      read -r ans
      case "${ans}" in
        y|Y|yes|YES) ;;
        *) abort "User declined to overwrite existing artifacts." ;;
      esac
    fi
    rm -f "${BUILD_DIR}/debs"/*.deb
  fi
  for f in "${debs[@]}"; do
    # skip dbg packages
    if [[ "$f" == *-dbg_* ]]; then
      continue
    fi
    cp -v "$f" "${BUILD_DIR}/debs/"
    copied=$((copied+1))
  done
  shopt -u nullglob
  [[ ${copied} -gt 0 ]] || abort "No deb artifacts were produced. Check logs/build.log"
  log_success "Artifacts collected in ${BUILD_DIR}/debs"
}

write_checksums_and_manifest() {
  log_info "Writing checksums and manifest..."
  pushd "${BUILD_DIR}" >/dev/null
  # checksums
  local checksum_file="checksums.txt"
  : > "${checksum_file}"
  (cd sources && sha256sum linux-${TAR_VER}.tar patch-${RT_BASE_VER}-rt${RT_VER}.patch >> "../${checksum_file}")
  if compgen -G "debs/*.deb" > /dev/null; then
    (cd debs && sha256sum *.deb >> "../${checksum_file}")
  fi

  # manifest.json
  local manifest="manifest.json"
  local distro="$(. /etc/os-release; echo "${NAME} ${VERSION}")"
  local host_kernel="$(uname -r)"
  local ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    echo "{"
    echo "  \"kernel\": \"${KERNEL_VER}\"," 
    echo "  \"rt_patch\": \"rt${RT_VER}\"," 
    echo "  \"build_time_utc\": \"${ts}\"," 
    echo "  \"host_kernel\": \"${host_kernel}\"," 
    echo "  \"distro\": \"${distro}\"," 
    echo "  \"jobs\": ${JOBS}," 
    echo "  \"artifacts\": ["
    local first=true
    for f in debs/*.deb; do
      if ${first}; then first=false; else echo ","; fi
      local base="$(basename "$f")"
      local sum="$(grep "  ${base}$" checksums.txt | awk '{print $1}')"
      echo "    {\"file\": \"${base}\", \"sha256\": \"${sum}\"}"
    done
    echo "  ]"
    echo "}"
  } > "${manifest}"
  popd >/dev/null
  log_success "Manifest and checksums created."
}

cleanup_worktree() {
  ${KEEP_WORK} && { log_info "Keeping work tree (--keep-work)."; return; }
  log_info "Cleaning up unpacked source tree..."
  rm -rf "${SRC_DIR}"
  log_success "Cleaned up."
}

main() {
  parse_args "$@"

  # Pre-flight checks
  require_cmd curl
  require_cmd xz
  require_cmd tar
  require_cmd patch
  require_cmd sha256sum

  install_deps
  compute_urls

  BUILD_DIR="${REPO_ROOT}/build/rt-kernel/${KERNEL_VER}-rt${RT_VER}"
  # Reuse existing build directory; only prompt when about to overwrite final artifacts
  mkdir -p "${BUILD_DIR}/logs" "${BUILD_DIR}/sources" "${BUILD_DIR}/debs"

  log_info "Build directory: ${BUILD_DIR}"

  download_sources

  # Optional signature verification
  if ${VERIFY}; then
    verify_signatures
  fi

  unpack_and_patch
  configure_kernel
  build_kernel
  collect_artifacts
  write_checksums_and_manifest
  cleanup_worktree

  log_success "Done. Artifacts are in: ${BUILD_DIR}/debs"
  log_info "Next steps: reboot into the new kernel after installing the debs manually."
}

main "$@"
