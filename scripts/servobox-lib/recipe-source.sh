#!/usr/bin/env bash
# Recipe channel helpers for ServoBox.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

DEFAULT_RECIPE_CHANNEL_URL="https://github.com/kvasios/servobox-recipes/releases/latest/download/servobox-recipes.tar.gz"

recipe_channel_url() {
  echo "${SERVOBOX_RECIPE_CHANNEL_URL:-${DEFAULT_RECIPE_CHANNEL_URL}}"
}

recipe_cache_dir() {
  if [[ -n "${SERVOBOX_RECIPE_CACHE_DIR:-}" ]]; then
    echo "${SERVOBOX_RECIPE_CACHE_DIR}"
  else
    echo "${XDG_CACHE_HOME:-${HOME}/.cache}/servobox/recipes/default"
  fi
}

recipe_channel_metadata_file() {
  echo "$(recipe_cache_dir)/.servobox-channel"
}

recipe_source_has_recipes() {
  [[ -d "$1/recipes" ]] || [[ -d "$1" && -n "$(recipe_source_first_recipe "$1")" ]]
}

recipe_source_first_recipe() {
  local recipes_dir="$1"
  local recipe_dir
  for recipe_dir in "${recipes_dir}"/*; do
    if [[ -d "${recipe_dir}" && -f "${recipe_dir}/recipe.conf" ]]; then
      basename "${recipe_dir}"
      return 0
    fi
  done
  return 1
}

recipe_source_download() {
  local url="$1"
  local output="$2"

  if [[ -f "${url}" ]]; then
    cp "${url}" "${output}"
    return 0
  fi

  if [[ "${url}" == file://* && -f "${url#file://}" ]]; then
    cp "${url#file://}" "${output}"
    return 0
  fi

  if have curl; then
    curl -fsSL "${url}" -o "${output}"
  elif have wget; then
    wget -q "${url}" -O "${output}"
  else
    echo "Error: installing recipes requires curl or wget." >&2
    return 1
  fi
}

recipe_source_checksum_url() {
  local url="$1"
  if [[ "${url}" == *.tar.gz ]]; then
    echo "${url%.tar.gz}.sha256"
  elif [[ "${url}" == *.tgz ]]; then
    echo "${url%.tgz}.sha256"
  else
    echo "${url}.sha256"
  fi
}

recipe_source_write_metadata() {
  local source_kind="$1"
  local source_url="$2"
  local cache_dir
  cache_dir="$(recipe_cache_dir)"

  {
    echo "kind=${source_kind}"
    echo "url=${source_url}"
    echo "updated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "${cache_dir}/.servobox-channel"
}

recipe_source_install_from_archive() {
  local url="$1"
  local cache_dir
  local tmp_dir
  local archive
  local checksum_url
  local checksum_file
  local extracted_root=""
  local candidate

  cache_dir="$(recipe_cache_dir)"
  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/servobox-recipes.tar.gz"
  checksum_file="${tmp_dir}/servobox-recipes.sha256"

  echo "Fetching ServoBox recipes from ${url}..."
  recipe_source_download "${url}" "${archive}"

  checksum_url="$(recipe_source_checksum_url "${url}")"
  if recipe_source_download "${checksum_url}" "${checksum_file}" 2>/dev/null; then
    if have sha256sum; then
      (cd "${tmp_dir}" && sha256sum -c "$(basename "${checksum_file}")")
    else
      echo "Warning: sha256sum not found; skipping recipe archive checksum verification." >&2
    fi
  fi

  mkdir -p "${tmp_dir}/extract"
  tar -xzf "${archive}" -C "${tmp_dir}/extract"

  if [[ -d "${tmp_dir}/extract/recipes" ]]; then
    extracted_root="${tmp_dir}/extract"
  else
    for candidate in "${tmp_dir}/extract"/*; do
      if [[ -d "${candidate}/recipes" ]]; then
        extracted_root="${candidate}"
        break
      fi
    done
  fi

  if [[ -z "${extracted_root}" || ! -d "${extracted_root}/recipes" ]]; then
    echo "Error: recipe archive does not contain a recipes/ directory." >&2
    return 1
  fi

  rm -rf "${cache_dir}.new"
  mkdir -p "$(dirname "${cache_dir}")" "${cache_dir}.new"
  cp -a "${extracted_root}/." "${cache_dir}.new/"
  rm -rf "${cache_dir}"
  mv "${cache_dir}.new" "${cache_dir}"
  recipe_source_write_metadata "archive" "${url}"
  rm -rf "${tmp_dir}"
}

recipe_source_install_from_git() {
  local raw_url="$1"
  local url="${raw_url#git+}"
  local cache_dir

  cache_dir="$(recipe_cache_dir)"
  if ! have git; then
    echo "Error: git recipe channels require git to be installed." >&2
    return 1
  fi

  if [[ -d "${cache_dir}/.git" ]]; then
    echo "Updating ServoBox recipes from ${url}..."
    git -C "${cache_dir}" fetch --depth 1 origin
    git -C "${cache_dir}" reset --hard origin/HEAD
  else
    rm -rf "${cache_dir}"
    mkdir -p "$(dirname "${cache_dir}")"
    echo "Cloning ServoBox recipes from ${url}..."
    git clone --depth 1 "${url}" "${cache_dir}"
  fi

  if [[ ! -d "${cache_dir}/recipes" ]]; then
    echo "Error: git recipe channel does not contain a recipes/ directory." >&2
    return 1
  fi
  recipe_source_write_metadata "git" "${raw_url}"
}

recipe_source_update() {
  local url
  url="$(recipe_channel_url)"

  if [[ "${url}" == git+* || "${url}" == *.git ]]; then
    recipe_source_install_from_git "${url}"
  else
    recipe_source_install_from_archive "${url}"
  fi
}

recipe_source_ensure() {
  local cache_dir

  cache_dir="$(recipe_cache_dir)"
  if [[ -d "${cache_dir}/recipes" ]]; then
    return 0
  fi

  recipe_source_update
}

recipe_source_recipes_dir() {
  local cache_dir

  cache_dir="$(recipe_cache_dir)"
  if [[ -d "${cache_dir}/recipes" ]]; then
    echo "${cache_dir}/recipes"
    return 0
  fi

  recipe_source_ensure >/dev/null
  if [[ -d "${cache_dir}/recipes" ]]; then
    echo "${cache_dir}/recipes"
    return 0
  fi

  echo "Error: no ServoBox recipes are available." >&2
  return 1
}

recipe_source_configs_dir() {
  local recipes_dir="$1"
  local root_dir
  root_dir="$(dirname "${recipes_dir}")"
  if [[ -d "${root_dir}/configs" ]]; then
    echo "${root_dir}/configs"
  fi
}

recipe_source_status() {
  local cache_dir
  local metadata
  cache_dir="$(recipe_cache_dir)"
  metadata="$(recipe_channel_metadata_file)"

  echo "ServoBox recipe channel"
  echo "URL: $(recipe_channel_url)"
  echo "Cache: ${cache_dir}"

  if [[ -f "${metadata}" ]]; then
    while IFS= read -r line; do
      echo "${line}"
    done < "${metadata}"
  elif [[ -d "${cache_dir}/recipes" ]]; then
    echo "status=cached"
  else
    echo "status=not cached"
  fi

  if [[ -d "${cache_dir}/recipes" ]]; then
    local count
    count=$(find "${cache_dir}/recipes" -mindepth 1 -maxdepth 1 -type d | wc -l | xargs)
    echo "recipes=${count}"
  fi
}

cmd_recipes() {
  local action="${2:-status}"
  case "${action}" in
    update)
      recipe_source_update
      recipe_source_status
      ;;
    status)
      recipe_source_status
      ;;
    -h|--help|help)
      echo "Usage: servobox recipes <status|update>"
      ;;
    *)
      echo "Unknown recipes command: ${action}" >&2
      echo "Usage: servobox recipes <status|update>" >&2
      exit 1
      ;;
  esac
}
