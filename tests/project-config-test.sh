#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain '${needle}', got: ${haystack}"
  fi
}

make_recipe() {
  local root="$1"
  local name="$2"
  local dir="${root}/${name}"

  mkdir -p "${dir}"
  cat > "${dir}/recipe.conf" <<EOF
name="${name}"
version="1.0.0"
description="${name} test recipe"
dependencies=""
EOF
  cat > "${dir}/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "install"
EOF
  chmod +x "${dir}/install.sh"
}

export REPO_ROOT
export LIBVIRT_IMAGES_BASE="${TMP_DIR}/libvirt-images"

# shellcheck source=../scripts/servobox-lib/project-config.sh
source "${REPO_ROOT}/scripts/servobox-lib/project-config.sh"

PROJECT_DIR="${TMP_DIR}/client"
NESTED_DIR="${PROJECT_DIR}/src/policy"
mkdir -p "${NESTED_DIR}"

(
  cd "${PROJECT_DIR}"
  cmd_config config init
)

[[ -f "${PROJECT_DIR}/.servobox/config" ]] || fail "config init did not create .servobox/config"
assert_contains "$(<"${PROJECT_DIR}/.servobox/config")" "SERVOBOX_VCPUS"

cat > "${PROJECT_DIR}/.servobox/config" <<'EOF'
SERVOBOX_NAME="policy-vm"
SERVOBOX_VCPUS=6
SERVOBOX_MEMORY=16384
SERVOBOX_DISK_GB=80
SERVOBOX_RT_MODE="performance"
SERVOBOX_HOST_NICS=("eno1" "eno2")
SERVOBOX_PKG_INSTALL="custom-policy"
SERVOBOX_PKG_CUSTOM=".servobox/recipes"
EOF

mkdir -p "${PROJECT_DIR}/.servobox/recipes"
make_recipe "${PROJECT_DIR}/.servobox/recipes" "custom-policy"
DEFAULT_RECIPES="${TMP_DIR}/default-recipes"
mkdir -p "${DEFAULT_RECIPES}"
make_recipe "${DEFAULT_RECIPES}" "channel-only"
cat > "${PROJECT_DIR}/.servobox/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "project run"
EOF
chmod +x "${PROJECT_DIR}/.servobox/run.sh"

(
  cd "${NESTED_DIR}"
  NAME="servobox-vm"
  VCPUS=4
  MEMORY=8192
  DISK_GB=20
  RT_MODE="balanced"
  BRIDGE=""
  STATIC_IP_CIDR=""
  BASE_OVERRIDE=""
  HOST_NICS=()
  ASK_NIC=0
  SSH_PUBKEY_PATH=""
  SSH_PRIVKEY_PATH=""

  servobox_project_config_load
  servobox_project_config_apply_defaults

  [[ "${SERVOBOX_PROJECT_DIR}" == "${PROJECT_DIR}" ]] || fail "unexpected project dir: ${SERVOBOX_PROJECT_DIR}"
  [[ "${NAME}" == "policy-vm" ]] || fail "NAME was not applied"
  [[ "${VCPUS}" == "6" ]] || fail "VCPUS was not applied"
  [[ "${MEMORY}" == "16384" ]] || fail "MEMORY was not applied"
  [[ "${DISK_GB}" == "80" ]] || fail "DISK_GB was not applied"
  [[ "${RT_MODE}" == "performance" ]] || fail "RT_MODE was not applied"
  [[ "${#HOST_NICS[@]}" -eq 2 ]] || fail "HOST_NICS was not applied"

  custom_path="$(servobox_project_configured_pkg_custom)"
  [[ "${custom_path}" == "${PROJECT_DIR}/.servobox/recipes" ]] || fail "custom path was not project-relative"
)

pkg_list="$(
  cd "${NESTED_DIR}"
  export PACKAGES_PM=""
  # shellcheck source=../scripts/servobox-lib/recipe-source.sh
  source "${REPO_ROOT}/scripts/servobox-lib/recipe-source.sh"
  # shellcheck source=../scripts/servobox-lib/pkg-install.sh
  source "${REPO_ROOT}/scripts/servobox-lib/pkg-install.sh"
  servobox_project_config_load
  cmd_pkg_install pkg-install --list
)"
assert_contains "${pkg_list}" "custom-policy"

run_output="$(
  cd "${NESTED_DIR}"
  NAME="policy-vm"
  # shellcheck source=../scripts/servobox-lib/recipe-source.sh
  source "${REPO_ROOT}/scripts/servobox-lib/recipe-source.sh"
  # shellcheck source=../scripts/servobox-lib/recipe-run.sh
  source "${REPO_ROOT}/scripts/servobox-lib/recipe-run.sh"
  servobox_project_config_load
  recipe_source_recipes_dir() { echo "${DEFAULT_RECIPES}"; }
  resolved_channel_recipe="$(resolve_recipe_run_dir channel-only)"
  [[ "${resolved_channel_recipe}" == "${DEFAULT_RECIPES}/channel-only" ]] || fail "run did not fall back to channel recipes"
  ensure_vm_running() { :; }
  exec_recipe_in_vm() { echo "exec:${1}:${2}"; }
  cmd_recipe_run run
)"
assert_contains "${run_output}" "Running project .servobox/run.sh"
assert_contains "${run_output}" "exec:project:${PROJECT_DIR}/.servobox/run.sh"

echo "project-config tests passed"
