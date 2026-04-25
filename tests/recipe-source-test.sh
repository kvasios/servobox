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
  local deps="${3:-}"
  local with_run="${4:-0}"
  local dir="${root}/recipes/${name}"

  mkdir -p "${dir}"
  cat > "${dir}/recipe.conf" <<EOF
name="${name}"
version="1.0.0"
description="${name} test recipe"
dependencies="${deps}"
EOF
  cat > "${dir}/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "install"
EOF
  chmod +x "${dir}/install.sh"

  if [[ "${with_run}" == "1" ]]; then
    cat > "${dir}/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "run"
EOF
    chmod +x "${dir}/run.sh"
  fi
}

CHANNEL_ROOT="${TMP_DIR}/channel"
DIST_DIR="${TMP_DIR}/dist"
mkdir -p "${CHANNEL_ROOT}/recipes" "${DIST_DIR}"
make_recipe "${CHANNEL_ROOT}" "base" "" "0"
make_recipe "${CHANNEL_ROOT}" "app" "base" "1"
cat > "${CHANNEL_ROOT}/index.json" <<'EOF'
{"schema_version":1,"recipes":{}}
EOF

tar -C "${CHANNEL_ROOT}" -czf "${DIST_DIR}/servobox-recipes.tar.gz" recipes index.json
(cd "${DIST_DIR}" && sha256sum servobox-recipes.tar.gz > servobox-recipes.sha256)

export REPO_ROOT
export XDG_CACHE_HOME="${TMP_DIR}/cache"
export SERVOBOX_RECIPE_CHANNEL_URL="${DIST_DIR}/servobox-recipes.tar.gz"
export SERVOBOX_DISABLE_BUNDLED_RECIPES=1

# shellcheck source=../scripts/servobox-lib/recipe-source.sh
source "${REPO_ROOT}/scripts/servobox-lib/recipe-source.sh"

recipes_dir="$(recipe_source_recipes_dir)"
expected_dir="${XDG_CACHE_HOME}/servobox/recipes/default/recipes"
[[ "${recipes_dir}" == "${expected_dir}" ]] || fail "unexpected recipes dir: ${recipes_dir}"
[[ -f "${recipes_dir}/app/recipe.conf" ]] || fail "cold cache did not extract app recipe"

status_output="$(recipe_source_status)"
assert_contains "${status_output}" "kind=archive"
assert_contains "${status_output}" "recipes=2"

SERVOBOX_RECIPE_CHANNEL_URL="${TMP_DIR}/missing.tar.gz"
warm_recipes_dir="$(recipe_source_recipes_dir)"
[[ "${warm_recipes_dir}" == "${recipes_dir}" ]] || fail "warm cache did not reuse existing recipes"

order="$("${REPO_ROOT}/scripts/servobox-tools/package-manager.sh" --recipe-dir "${recipes_dir}" install-order app)"
[[ "${order}" == $'base\napp' ]] || fail "unexpected dependency order: ${order}"

if "${REPO_ROOT}/scripts/servobox-tools/package-manager.sh" --recipe-dir "${recipes_dir}" install-order missing >/dev/null 2>&1; then
  fail "missing recipe unexpectedly resolved"
fi

# shellcheck source=../scripts/servobox-lib/recipe-run.sh
source "${REPO_ROOT}/scripts/servobox-lib/recipe-run.sh"
run_list="$(list_recipes_with_run)"
assert_contains "${run_list}" "app"

CUSTOM_ROOT="${TMP_DIR}/custom"
mkdir -p "${CUSTOM_ROOT}/recipes"
make_recipe "${CUSTOM_ROOT}" "custom-only" "" "0"
custom_list="$(
  XDG_CACHE_HOME="${TMP_DIR}/custom-cache" \
  SERVOBOX_RECIPE_CHANNEL_URL="${TMP_DIR}/missing.tar.gz" \
  SERVOBOX_DISABLE_BUNDLED_RECIPES=1 \
  "${REPO_ROOT}/scripts/servobox" pkg-install --list --custom "${CUSTOM_ROOT}/recipes"
)"
assert_contains "${custom_list}" "custom-only"

echo "recipe-source tests passed"
