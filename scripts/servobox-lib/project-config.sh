#!/usr/bin/env bash
# Project-local ServoBox configuration helpers.

servobox_project_find_dir() {
  local start_dir="${1:-${PWD}}"
  local dir

  dir="$(cd "${start_dir}" 2>/dev/null && pwd)" || return 1
  while [[ "${dir}" != "/" ]]; do
    if [[ -d "${dir}/.servobox" ]]; then
      echo "${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done

  if [[ -d "/.servobox" ]]; then
    echo "/"
    return 0
  fi
  return 1
}

servobox_project_config_load() {
  SERVOBOX_PROJECT_DIR=""
  SERVOBOX_PROJECT_CONFIG_DIR=""
  SERVOBOX_PROJECT_CONFIG=""
  SERVOBOX_PROJECT_CONFIG_LOADED=0

  if ! SERVOBOX_PROJECT_DIR="$(servobox_project_find_dir "${PWD}")"; then
    return 0
  fi

  SERVOBOX_PROJECT_CONFIG_DIR="${SERVOBOX_PROJECT_DIR}/.servobox"
  SERVOBOX_PROJECT_CONFIG="${SERVOBOX_PROJECT_CONFIG_DIR}/config"

  if [[ ! -e "${SERVOBOX_PROJECT_CONFIG}" ]]; then
    return 0
  fi
  if [[ ! -f "${SERVOBOX_PROJECT_CONFIG}" ]]; then
    echo "Error: ${SERVOBOX_PROJECT_CONFIG} is not a regular file." >&2
    exit 1
  fi

  # This is an explicit project-local Bash config file, similar to .envrc.
  # Users should only source ServoBox configs from repositories they trust.
  # shellcheck source=/dev/null
  source "${SERVOBOX_PROJECT_CONFIG}"
  SERVOBOX_PROJECT_CONFIG_LOADED=1
}

servobox_project_config_resolve_path() {
  local path="$1"

  if [[ -z "${path}" || "${path}" == /* || -z "${SERVOBOX_PROJECT_DIR:-}" ]]; then
    echo "${path}"
  else
    echo "${SERVOBOX_PROJECT_DIR}/${path}"
  fi
}

servobox_project_configured_pkg_custom() {
  if [[ -n "${SERVOBOX_PKG_CUSTOM:-}" ]]; then
    servobox_project_config_resolve_path "${SERVOBOX_PKG_CUSTOM}"
  fi
}

servobox_project_configured_pkg_install() {
  if [[ -n "${SERVOBOX_PKG_INSTALL:-}" ]]; then
    if [[ "${SERVOBOX_PKG_INSTALL}" == */* ]]; then
      servobox_project_config_resolve_path "${SERVOBOX_PKG_INSTALL}"
    else
      echo "${SERVOBOX_PKG_INSTALL}"
    fi
  fi
}

servobox_project_run_script() {
  local run_script

  if [[ -n "${SERVOBOX_RUN_SCRIPT:-}" ]]; then
    run_script="$(servobox_project_config_resolve_path "${SERVOBOX_RUN_SCRIPT}")"
  elif [[ -n "${SERVOBOX_PROJECT_CONFIG_DIR:-}" ]]; then
    run_script="${SERVOBOX_PROJECT_CONFIG_DIR}/run.sh"
  else
    return 1
  fi

  if [[ -f "${run_script}" ]]; then
    echo "${run_script}"
    return 0
  fi
  return 1
}

servobox_refresh_vm_paths() {
  VM_DIR="${LIBVIRT_IMAGES_BASE}/servobox/${NAME}"
  SEED_ISO="${VM_DIR}/seed.iso"
  DISK_QCOW="${VM_DIR}/${NAME}.qcow2"
}

servobox_project_config_apply_defaults() {
  local configured_memory=""
  local configured_disk=""

  [[ -n "${SERVOBOX_NAME:-}" ]] && NAME="${SERVOBOX_NAME}"
  [[ -n "${SERVOBOX_VCPUS:-}" ]] && VCPUS="${SERVOBOX_VCPUS}"

  configured_memory="${SERVOBOX_MEMORY:-${SERVOBOX_MEM:-}}"
  [[ -n "${configured_memory}" ]] && MEMORY="${configured_memory}"

  configured_disk="${SERVOBOX_DISK_GB:-${SERVOBOX_DISK:-}}"
  [[ -n "${configured_disk}" ]] && DISK_GB="${configured_disk}"

  [[ -n "${SERVOBOX_BRIDGE:-}" ]] && BRIDGE="${SERVOBOX_BRIDGE}"
  [[ -n "${SERVOBOX_IP:-}" ]] && STATIC_IP_CIDR="${SERVOBOX_IP}"
  [[ -n "${SERVOBOX_RT_MODE:-}" ]] && RT_MODE="${SERVOBOX_RT_MODE}"
  [[ -n "${SERVOBOX_IMAGE:-}" ]] && BASE_OVERRIDE="$(servobox_project_config_resolve_path "${SERVOBOX_IMAGE}")"
  [[ -n "${SERVOBOX_SSH_PUBKEY:-}" ]] && SSH_PUBKEY_PATH="$(servobox_project_config_resolve_path "${SERVOBOX_SSH_PUBKEY}")"
  [[ -n "${SERVOBOX_SSH_KEY:-}" ]] && SSH_PRIVKEY_PATH="$(servobox_project_config_resolve_path "${SERVOBOX_SSH_KEY}")"

  if declare -p SERVOBOX_HOST_NICS >/dev/null 2>&1; then
    local host_nics_decl
    host_nics_decl="$(declare -p SERVOBOX_HOST_NICS)"
    if [[ "${host_nics_decl}" == declare\ -a* || "${host_nics_decl}" == declare\ -x\ -a* ]]; then
      local -n configured_host_nics=SERVOBOX_HOST_NICS
      HOST_NICS=("${configured_host_nics[@]}")
    elif [[ -n "${SERVOBOX_HOST_NICS:-}" ]]; then
      read -r -a HOST_NICS <<< "${SERVOBOX_HOST_NICS}"
    fi
  elif [[ -n "${SERVOBOX_HOST_NIC:-}" ]]; then
    HOST_NICS=("${SERVOBOX_HOST_NIC}")
  fi

  [[ "${SERVOBOX_CHOOSE_NIC:-0}" == "1" ]] && ASK_NIC=1

  servobox_refresh_vm_paths
}

servobox_project_defaults_template() {
  local candidate
  for candidate in \
    "${REPO_ROOT:-}/data/servobox-defaults.config" \
    "${REPO_ROOT:-}/servobox-defaults.config" \
    "/usr/share/servobox/servobox-defaults.config"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

cmd_config() {
  local action="${2:-help}"
  local target_dir="${PWD}"
  local force=0

  case "${action}" in
    init)
      shift 2 || true
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --dir)
            target_dir="$2"; shift 2 ;;
          -f|--force)
            force=1; shift ;;
          -h|--help)
            echo "Usage: servobox config init [--dir DIR] [--force]"
            return 0 ;;
          --*)
            echo "Unknown option: $1" >&2
            echo "Usage: servobox config init [--dir DIR] [--force]" >&2
            return 1 ;;
          *)
            echo "Unexpected argument: $1" >&2
            echo "Usage: servobox config init [--dir DIR] [--force]" >&2
            return 1 ;;
        esac
      done

      local template
      local config_dir
      local config_file
      template="$(servobox_project_defaults_template)" || {
        echo "Error: servobox-defaults.config template not found." >&2
        return 1
      }
      config_dir="${target_dir}/.servobox"
      config_file="${config_dir}/config"

      if [[ -e "${config_file}" && ${force} -ne 1 ]]; then
        echo "Error: ${config_file} already exists." >&2
        echo "Use 'servobox config init --force' to overwrite it." >&2
        return 1
      fi

      mkdir -p "${config_dir}"
      cp "${template}" "${config_file}"
      chmod 0644 "${config_file}"
      echo "Created ${config_file}"
      echo "Edit it to set project VM, package, and run defaults."
      ;;
    path)
      if [[ -n "${SERVOBOX_PROJECT_CONFIG:-}" && -f "${SERVOBOX_PROJECT_CONFIG}" ]]; then
        echo "${SERVOBOX_PROJECT_CONFIG}"
      else
        echo "No .servobox/config found from ${PWD}" >&2
        return 1
      fi
      ;;
    -h|--help|help|"")
      cat <<EOF
Usage:
  servobox config init [--dir DIR] [--force]  Create .servobox/config from defaults
  servobox config path                        Print the active project config path
EOF
      ;;
    *)
      echo "Unknown config command: ${action}" >&2
      echo "Usage: servobox config init [--dir DIR] [--force]" >&2
      return 1 ;;
  esac
}
