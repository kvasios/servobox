#!/usr/bin/env bash
# Package installation functions

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

get_vm_tracking_file() {
  echo "${HOME}/.local/share/servobox/tracking/${NAME}.servobox-packages"
}

is_package_tracked_for_vm() {
  local package="$1"
  local tracking_file
  tracking_file=$(get_vm_tracking_file)
  [[ -f "${tracking_file}" ]] && grep -q "^${package}$" "${tracking_file}" 2>/dev/null
}

mark_package_tracked_for_vm() {
  local package="$1"
  local tracking_file
  tracking_file=$(get_vm_tracking_file)
  mkdir -p "$(dirname "${tracking_file}")"
  if ! grep -q "^${package}$" "${tracking_file}" 2>/dev/null; then
    echo "${package}" >> "${tracking_file}"
  fi
}

ensure_vm_shutdown_for_offline_install() {
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
}

ensure_vm_running_for_online_install() {
  if ! virsh_cmd dominfo "${NAME}" >/dev/null 2>&1; then
    echo "Error: VM '${NAME}' does not exist." >&2
    echo "Use 'servobox init --name ${NAME}' to create the VM first." >&2
    exit 1
  fi

  PKG_INSTALL_STARTED_VM=0
  local vm_state
  vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")

  case "${vm_state}" in
    "shut off")
      echo "VM '${NAME}' is not running. Starting it for package installation..."
      if ! virsh_cmd start "${NAME}" >/dev/null 2>&1; then
        echo "Error: Failed to start VM '${NAME}'" >&2
        exit 1
      fi
      PKG_INSTALL_STARTED_VM=1
      ;;
    "in shutdown")
      echo "VM '${NAME}' is currently shutting down. Waiting..."
      for i in {1..60}; do
        vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
        if [[ "${vm_state}" == "shut off" ]]; then
          break
        fi
        sleep 1
      done
      vm_state=$(virsh_cmd domstate "${NAME}" 2>/dev/null || echo "unknown")
      if [[ "${vm_state}" != "shut off" ]]; then
        echo "Error: VM '${NAME}' did not finish shutting down in time" >&2
        exit 1
      fi
      echo "Starting VM '${NAME}' for package installation..."
      if ! virsh_cmd start "${NAME}" >/dev/null 2>&1; then
        echo "Error: Failed to start VM '${NAME}'" >&2
        exit 1
      fi
      PKG_INSTALL_STARTED_VM=1
      ;;
    "paused")
      echo "Error: VM '${NAME}' is paused." >&2
      echo "Use 'virsh -c qemu:///system resume ${NAME}' or restart the VM." >&2
      exit 1
      ;;
    "running")
      ;;
    *)
      echo "Error: VM '${NAME}' is in unknown state: ${vm_state}" >&2
      exit 1
      ;;
  esac

  echo "Waiting for VM networking..."
  PKG_INSTALL_VM_IP=""
  for i in {1..60}; do
    PKG_INSTALL_VM_IP=$(vm_ip || true)
    if [[ -n "${PKG_INSTALL_VM_IP}" ]]; then
      break
    fi
    sleep 2
  done
  if [[ -z "${PKG_INSTALL_VM_IP}" ]]; then
    echo "Error: VM '${NAME}' is running but has no IP address assigned." >&2
    exit 1
  fi

  echo "VM IP: ${PKG_INSTALL_VM_IP}"
  wait_for_sshd "${PKG_INSTALL_VM_IP}" 60 || true
}

restore_vm_state_after_online_install() {
  if [[ "${PKG_INSTALL_STARTED_VM:-0}" -ne 1 ]]; then
    return 0
  fi
  if ! virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi running; then
    return 0
  fi

  echo ""
  echo "Stopping VM '${NAME}' (restoring previous state)..."
  if ! virsh_cmd shutdown "${NAME}" >/dev/null 2>&1; then
    echo "Warning: Failed to initiate VM shutdown after installation" >&2
    return 1
  fi
  for i in {1..60}; do
    if virsh_cmd domstate "${NAME}" 2>/dev/null | grep -qi "shut off"; then
      echo "✓ VM '${NAME}' stopped"
      return 0
    fi
    sleep 1
  done
  echo "Warning: VM '${NAME}' is still running after waiting for shutdown" >&2
  return 1
}

cmd_pkg_install() {
  # Custom arg parsing for pkg-install (avoid global parse_args which treats
  # positional package names as unknown args)
  local target=""
  local verbose_flag=""
  local force_flag=""
  local list_only=0
  local offline_install=0
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
      --offline)
        offline_install=1; shift ;;
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
        echo "Usage: servobox pkg-install <package|config> [--name NAME] [--verbose] [--force] [--offline] [--list] [--custom PATH]"
        echo ""
        echo "  --custom PATH    Path to custom recipe directory OR config file"
        echo "  --force          Force reinstallation even if package is already installed"
        echo "  --offline        Use offline image customization (legacy mode)"
        exit 0 ;;
      --*)
        echo "Unknown option: $1" >&2
        echo "Usage: servobox pkg-install <package|config> [--name NAME] [--verbose] [--force] [--offline] [--list] [--custom PATH]" >&2
        exit 1 ;;
      *)
        if [[ -z "${target}" ]]; then
          target="$1"; shift
        else
          echo "Unexpected argument: $1" >&2
          echo "Usage: servobox pkg-install <package|config> [--name NAME] [--verbose] [--force] [--offline] [--list] [--custom PATH]" >&2
          exit 1
        fi ;;
    esac
  done
  local recipes_dir=""
  local config_dir=""

  if [[ -z "${target}" ]] && declare -f servobox_project_configured_pkg_install >/dev/null 2>&1; then
    target="$(servobox_project_configured_pkg_install)"
  fi

  if [[ -z "${custom_path}" ]] && declare -f servobox_project_configured_pkg_custom >/dev/null 2>&1; then
    custom_path="$(servobox_project_configured_pkg_custom)"
    if [[ -n "${custom_path}" ]]; then
      if [[ -d "${custom_path}" ]]; then
        custom_is_dir=1
      elif [[ -f "${custom_path}" ]]; then
        custom_is_config=1
      else
        echo "Error: SERVOBOX_PKG_CUSTOM path not found: ${custom_path}" >&2
        exit 1
      fi
    fi
  fi

  # If --list was requested, show available configs and packages and exit
  if [[ ${list_only} -eq 1 ]]; then
    if [[ ${custom_is_dir} -eq 1 ]]; then
      recipes_dir="${custom_path}"
    else
      recipes_dir="$(recipe_source_recipes_dir)" || exit 1
    fi
    config_dir="$(recipe_source_configs_dir "${recipes_dir}" || true)"

    # List config files from the active recipe source when available.
    if [[ -n "${config_dir}" && -d "${config_dir}" ]]; then
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
      "${PACKAGES_PM}" list --recipe-dir "${recipes_dir}" || true
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

  if [[ ${custom_is_dir} -eq 1 ]]; then
    recipes_dir="${custom_path}"
  else
    recipes_dir="$(recipe_source_recipes_dir)" || exit 1
  fi
  config_dir="$(recipe_source_configs_dir "${recipes_dir}" || true)"
  
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
  
  # Fall back to the active channel/config directory if not found in custom dir.
  if [[ -z "${config_file}" && -n "${config_dir}" ]]; then
    if [[ "${target}" =~ \.conf(ig)?$ ]]; then
      if [[ -f "${config_dir}/${target}" ]]; then
        config_file="${config_dir}/${target}"
      fi
    elif [[ -f "${config_dir}/${target}.conf" ]]; then
      config_file="${config_dir}/${target}.conf"
    fi
  fi

  # Online mode (default): install over SSH into a running VM.
  if [[ ${offline_install} -eq 0 ]]; then
    local requested_packages=()
    if [[ -n "${config_file}" ]]; then
      echo "Installing packages from config: $(basename "${config_file}")"
      mapfile -t requested_packages < <(grep -v '^#' "${config_file}" | grep -v '^$' || true)
      if [[ ${#requested_packages[@]} -eq 0 ]]; then
        echo "No packages in config ${target}"
        exit 0
      fi
    else
      # Single package: resolve dependency order the same way as remote install.
      local install_order=()
      local pm_args=(--recipe-dir "${recipes_dir}")
      while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] && install_order+=("${pkg}")
      done < <("${PACKAGES_PM}" "${pm_args[@]}" install-order "${target}" 2>/dev/null) || true
      if [[ ${#install_order[@]} -eq 0 ]]; then
        install_order=("${target}")
      fi
      requested_packages=("${install_order[@]}")
      if [[ ${#requested_packages[@]} -gt 1 ]]; then
        echo "Resolving dependencies for ${target}..."
        echo "Will install ${#requested_packages[@]} packages in order: ${requested_packages[*]}"
      fi
    fi

    ensure_vm_running_for_online_install

    local old_target_ip="${SERVOBOX_TARGET_IP:-}"
    local old_target_user="${SERVOBOX_TARGET_USER:-}"
    local old_target_port="${SERVOBOX_TARGET_PORT:-}"
    SERVOBOX_TARGET_IP="${PKG_INSTALL_VM_IP}"
    SERVOBOX_TARGET_USER="servobox-usr"
    SERVOBOX_TARGET_PORT="22"

    local install_failed=0
    for p in "${requested_packages[@]}"; do
      echo ""
      if [[ -z "${force_flag}" ]] && is_package_tracked_for_vm "${p}"; then
        echo "Package ${p} is already installed, skipping (use --force to reinstall)"
        continue
      fi
      echo "Installing package: ${p}"
      if ! install_package_remote "${p}" "${recipes_dir}" "${verbose_flag}" "${force_flag}"; then
        install_failed=1
        break
      fi
      mark_package_tracked_for_vm "${p}"
    done

    if [[ -n "${old_target_ip}" ]]; then
      SERVOBOX_TARGET_IP="${old_target_ip}"
    else
      unset SERVOBOX_TARGET_IP
    fi
    if [[ -n "${old_target_user}" ]]; then
      SERVOBOX_TARGET_USER="${old_target_user}"
    else
      unset SERVOBOX_TARGET_USER
    fi
    if [[ -n "${old_target_port}" ]]; then
      SERVOBOX_TARGET_PORT="${old_target_port}"
    else
      unset SERVOBOX_TARGET_PORT
    fi

    if [[ ${install_failed} -eq 1 ]]; then
      echo ""
      echo "Package installation failed. VM '${NAME}' remains running for troubleshooting." >&2
      exit 1
    fi

    restore_vm_state_after_online_install || true
    exit 0
  fi

  # If we found a config file, process it (offline mode)
  if [[ -n "${config_file}" ]]; then
    if [[ ! -f "${config_file}" ]]; then
      echo "Error: config not found: ${config_file}" >&2
      exit 1
    fi
    
    ensure_vm_shutdown_for_offline_install

    echo "Installing packages from config: $(basename "${config_file}")"
    
    mapfile -t pkgs < <(grep -v '^#' "${config_file}" | grep -v '^$' || true)
    if [[ ${#pkgs[@]} -eq 0 ]]; then
      echo "No packages in config ${target}"
      exit 0
    fi
    
    for p in "${pkgs[@]}"; do
      echo ""
      echo "Installing package: $p"

      if [[ -n "${verbose_flag}" && -n "${force_flag}" ]]; then
        "${PACKAGES_PM}" install --recipe-dir "${recipes_dir}" "${verbose_flag}" --force-package "$p" "$p" "${DISK_QCOW}"
      elif [[ -n "${verbose_flag}" ]]; then
        "${PACKAGES_PM}" install --recipe-dir "${recipes_dir}" "${verbose_flag}" "$p" "${DISK_QCOW}"
      elif [[ -n "${force_flag}" ]]; then
        "${PACKAGES_PM}" install --recipe-dir "${recipes_dir}" --force-package "$p" "$p" "${DISK_QCOW}"
      else
        "${PACKAGES_PM}" install --recipe-dir "${recipes_dir}" "$p" "${DISK_QCOW}"
      fi
    done
    exit 0
  fi
  # Treat as single package (offline mode)
  ensure_vm_shutdown_for_offline_install
  
  # Install single package
  if [[ -n "${verbose_flag}" && -n "${force_flag}" ]]; then
    "${PACKAGES_PM}" install --recipe-dir "${recipes_dir}" "${verbose_flag}" --force-package "${target}" "${target}" "${DISK_QCOW}"
  elif [[ -n "${verbose_flag}" ]]; then
    "${PACKAGES_PM}" install --recipe-dir "${recipes_dir}" "${verbose_flag}" "${target}" "${DISK_QCOW}"
  elif [[ -n "${force_flag}" ]]; then
    "${PACKAGES_PM}" install --recipe-dir "${recipes_dir}" --force-package "${target}" "${target}" "${DISK_QCOW}"
  else
    "${PACKAGES_PM}" install --recipe-dir "${recipes_dir}" "${target}" "${DISK_QCOW}"
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
