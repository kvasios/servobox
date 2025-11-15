#!/usr/bin/env bash
# Package installation functions

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

cmd_pkg_install() {
  # Custom arg parsing for pkg-install (avoid global parse_args which treats
  # positional package names as unknown args)
  local target=""
  local verbose_flag=""
  local force_flag=""
  local list_only=0
  local custom_path=""
  local custom_is_dir=0
  local custom_is_config=0
  
  # Drop leading subcommand if present
  if [[ "${1:-}" == "pkg-install" ]]; then
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        NAME="$2"; shift 2 ;;
      -v|--verbose)
        verbose_flag="--verbose"; shift ;;
      --force)
        force_flag="--force"; shift ;;
      -l|--list)
        list_only=1; shift ;;
      --custom)
        custom_path="$2"
        if [[ -d "${custom_path}" ]]; then
          custom_is_dir=1
        elif [[ -f "${custom_path}" ]]; then
          custom_is_config=1
        else
          echo "Error: --custom path not found: ${custom_path}" >&2
          exit 1
        fi
        shift 2 ;;
      --recipe-dir)
        # Legacy support: --recipe-dir is now an alias for --custom
        custom_path="$2"
        if [[ -d "${custom_path}" ]]; then
          custom_is_dir=1
        else
          echo "Error: --recipe-dir must be a directory: ${custom_path}" >&2
          exit 1
        fi
        shift 2 ;;
      -h|--help)
        echo "Usage: servobox pkg-install <package|config> [--name NAME] [--verbose] [--force] [--list] [--custom PATH]"
        echo ""
        echo "  --custom PATH    Path to custom recipe directory OR config file"
        echo "  --force          Force reinstallation even if package is already installed"
        exit 0 ;;
      --*)
        echo "Unknown option: $1" >&2
        echo "Usage: servobox pkg-install <package|config> [--name NAME] [--verbose] [--force] [--list] [--custom PATH]" >&2
        exit 1 ;;
      *)
        if [[ -z "${target}" ]]; then
          target="$1"; shift
        else
          echo "Unexpected argument: $1" >&2
          echo "Usage: servobox pkg-install <package|config> [--name NAME] [--verbose] [--force] [--list] [--custom PATH]" >&2
          exit 1
        fi ;;
    esac
  done
  # If --list was requested, show available configs and packages and exit
  if [[ ${list_only} -eq 1 ]]; then
    local config_dir="${REPO_ROOT}/packages/config"
    local recipes_dir="${REPO_ROOT}/packages/recipes"
    
    # If custom directory specified, use it for recipes
    if [[ ${custom_is_dir} -eq 1 ]]; then
      recipes_dir="${custom_path}"
    fi
    
    # List config files (always from system location for --list)
    if [[ -d "${config_dir}" ]]; then
      local any_conf=0
      while IFS= read -r -d '' f; do
        if [[ ${any_conf} -eq 0 ]]; then
          echo "Package configs:"
        fi
        any_conf=1
        printf "  %s\n" "$(basename "${f}")"
      done < <(find "${config_dir}" -maxdepth 1 -type f -name '*.conf' -print0 | sort -z)
      if [[ ${any_conf} -eq 1 ]]; then
        echo
      fi
    fi
    
    # List recipe packages
    echo "Available packages:"
    if [[ -x "${PACKAGES_PM}" ]]; then
      # Delegate to package manager 'list' for rich output
      if [[ ${custom_is_dir} -eq 1 ]]; then
        "${PACKAGES_PM}" list --recipe-dir "${custom_path}" || true
      else
        "${PACKAGES_PM}" list || true
      fi
    else
      if [[ -d "${recipes_dir}" ]]; then
        local any_pkg=0
        while IFS= read -r -d '' d; do
          any_pkg=1
          printf "  %s\n" "$(basename "${d}")"
        done < <(find "${recipes_dir}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
        if [[ ${any_pkg} -eq 0 ]]; then
          echo "  (none)"
        fi
      else
        echo "  (not found)"
      fi
    fi
    exit 0
  fi
  # If --custom points to a config file directly, use it
  if [[ ${custom_is_config} -eq 1 ]]; then
    target="${custom_path}"
    # Don't need to look for it, we already have the full path
  elif [[ ${custom_is_dir} -eq 1 ]]; then
    # If --custom points to a recipe directory and no target specified,
    # try to extract package name from recipe.conf
    if [[ -z "${target}" && -f "${custom_path}/recipe.conf" ]]; then
      # Extract name from the recipe.conf line: name="pkg-name"
      if name=$(grep -E '^name=' "${custom_path}/recipe.conf" 2>/dev/null | cut -d'"' -f2); then
        name="$(echo "${name}" | xargs)"
        if [[ -n "${name}" ]]; then
          target="${name}"
        fi
      fi
    fi
  fi
  
  if [[ -z "${target}" ]]; then 
    echo "Usage: servobox pkg-install <package|config> [--name NAME] [--custom PATH]" >&2
    exit 1
  fi
  
  # Update DISK_QCOW path based on NAME (which may have been set via --name)
  DISK_QCOW="${LIBVIRT_IMAGES_BASE}/servobox/${NAME}/${NAME}.qcow2"
  
  ensure_vm_disk
  if [[ ! -x "${PACKAGES_PM}" ]]; then
    echo "Error: package manager not found: ${PACKAGES_PM}" >&2
    exit 1
  fi
  
  # Detect config file
  local config_file=""
  
  # Check if target is an absolute/relative path to a file
  if [[ -f "${target}" ]]; then
    config_file="${target}"
  # Check in custom recipe dir first (if specified and is a directory)
  elif [[ ${custom_is_dir} -eq 1 ]]; then
    if [[ "${target}" =~ \.conf(ig)?$ ]]; then
      if [[ -f "${custom_path}/${target}" ]]; then
        config_file="${custom_path}/${target}"
      fi
    elif [[ -f "${custom_path}/${target}.conf" ]]; then
      config_file="${custom_path}/${target}.conf"
    fi
  fi
  
  # Fall back to system config directory if not found in custom dir
  if [[ -z "${config_file}" ]]; then
    if [[ "${target}" =~ \.conf(ig)?$ ]]; then
      if [[ -f "${REPO_ROOT}/packages/config/${target}" ]]; then
        config_file="${REPO_ROOT}/packages/config/${target}"
      fi
    elif [[ -f "${REPO_ROOT}/packages/config/${target}.conf" ]]; then
      config_file="${REPO_ROOT}/packages/config/${target}.conf"
    fi
  fi
  # If we found a config file, process it
  if [[ -n "${config_file}" ]]; then
    if [[ ! -f "${config_file}" ]]; then
      echo "Error: config not found: ${config_file}" >&2
      exit 1
    fi
    
    echo "Installing packages from config: $(basename "${config_file}")"
    
    mapfile -t pkgs < <(grep -v '^#' "${config_file}" | grep -v '^$' || true)
    if [[ ${#pkgs[@]} -eq 0 ]]; then
      echo "No packages in config ${target}"
      exit 0
    fi
    
    for p in "${pkgs[@]}"; do
      echo ""
      echo "Installing package: $p"
      
      # Pass custom recipe dir to package manager if specified
      if [[ ${custom_is_dir} -eq 1 ]]; then
        if [[ -n "${verbose_flag}" && -n "${force_flag}" ]]; then
          "${PACKAGES_PM}" install --recipe-dir "${custom_path}" "${verbose_flag}" --force-package "$p" "$p" "${DISK_QCOW}"
        elif [[ -n "${verbose_flag}" ]]; then
          "${PACKAGES_PM}" install --recipe-dir "${custom_path}" "${verbose_flag}" "$p" "${DISK_QCOW}"
        elif [[ -n "${force_flag}" ]]; then
          "${PACKAGES_PM}" install --recipe-dir "${custom_path}" --force-package "$p" "$p" "${DISK_QCOW}"
        else
          "${PACKAGES_PM}" install --recipe-dir "${custom_path}" "$p" "${DISK_QCOW}"
        fi
      else
        if [[ -n "${verbose_flag}" && -n "${force_flag}" ]]; then
          "${PACKAGES_PM}" install "${verbose_flag}" --force-package "$p" "$p" "${DISK_QCOW}"
        elif [[ -n "${verbose_flag}" ]]; then
          "${PACKAGES_PM}" install "${verbose_flag}" "$p" "${DISK_QCOW}"
        elif [[ -n "${force_flag}" ]]; then
          "${PACKAGES_PM}" install --force-package "$p" "$p" "${DISK_QCOW}"
        else
          "${PACKAGES_PM}" install "$p" "${DISK_QCOW}"
        fi
      fi
    done
    exit 0
  fi
  # Treat as single package
  # Ensure the VM is shut down before offline customization
  if virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi running; then
    echo "VM ${NAME} is running; shutting it down for offline package install..."
    if ! virsh_cmd shutdown "${NAME}" >/dev/null 2>&1; then
      echo "Warning: Failed to initiate VM shutdown" >&2
    fi
    for i in {1..60}; do
      if virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi "shut off"; then break; fi
      sleep 1
    done
    if ! virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi "shut off"; then
      echo "Warning: VM did not shut down cleanly; forcing destroy..." >&2
      if ! virsh_cmd destroy "${NAME}" >/dev/null 2>&1; then
        echo "Error: Failed to force destroy VM ${NAME}" >&2
        exit 1
      fi
    fi
  fi
  
  # Install single package
  if [[ ${custom_is_dir} -eq 1 ]]; then
    if [[ -n "${verbose_flag}" && -n "${force_flag}" ]]; then
      "${PACKAGES_PM}" install --recipe-dir "${custom_path}" "${verbose_flag}" --force-package "${target}" "${target}" "${DISK_QCOW}"
    elif [[ -n "${verbose_flag}" ]]; then
      "${PACKAGES_PM}" install --recipe-dir "${custom_path}" "${verbose_flag}" "${target}" "${DISK_QCOW}"
    elif [[ -n "${force_flag}" ]]; then
      "${PACKAGES_PM}" install --recipe-dir "${custom_path}" --force-package "${target}" "${target}" "${DISK_QCOW}"
    else
      "${PACKAGES_PM}" install --recipe-dir "${custom_path}" "${target}" "${DISK_QCOW}"
    fi
  else
    if [[ -n "${verbose_flag}" && -n "${force_flag}" ]]; then
      "${PACKAGES_PM}" install "${verbose_flag}" --force-package "${target}" "${target}" "${DISK_QCOW}"
    elif [[ -n "${verbose_flag}" ]]; then
      "${PACKAGES_PM}" install "${verbose_flag}" "${target}" "${DISK_QCOW}"
    elif [[ -n "${force_flag}" ]]; then
      "${PACKAGES_PM}" install --force-package "${target}" "${target}" "${DISK_QCOW}"
    else
      "${PACKAGES_PM}" install "${target}" "${DISK_QCOW}"
    fi
  fi
}

# Show packages already installed in the VM
cmd_pkg_installed() {
  # Custom arg parsing for pkg-installed
  local verbose_flag=""
  
  # Drop leading subcommand if present
  if [[ "${1:-}" == "pkg-installed" ]]; then
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        NAME="$2"; shift 2 ;;
      -v|--verbose)
        verbose_flag="--verbose"; shift ;;
      -h|--help)
        echo "Usage: servobox pkg-installed [--name NAME] [--verbose]"
        echo ""
        echo "  --name NAME    VM/domain name (default: servobox-vm)"
        echo "  --verbose      Enable verbose output"
        exit 0 ;;
      --*)
        echo "Unknown option: $1" >&2
        echo "Usage: servobox pkg-installed [--name NAME] [--verbose]" >&2
        exit 1 ;;
      *)
        echo "Unexpected argument: $1" >&2
        echo "Usage: servobox pkg-installed [--name NAME] [--verbose]" >&2
        exit 1 ;;
    esac
  done
  
  # Get VM disk path
  local DISK_QCOW="/var/lib/libvirt/images/servobox/${NAME}/${NAME}.qcow2"
  
  if [[ ! -f "$DISK_QCOW" ]]; then
    echo "Error: VM disk not found: $DISK_QCOW" >&2
    echo "Make sure the VM '${NAME}' exists and has been initialized." >&2
    exit 1
  fi
  
  # Call package manager to list installed packages
  if [[ -n "${verbose_flag}" ]]; then
    "${PACKAGES_PM}" installed "${verbose_flag}" "$DISK_QCOW"
  else
    "${PACKAGES_PM}" installed "$DISK_QCOW"
  fi
}
