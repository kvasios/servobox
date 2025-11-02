#!/usr/bin/env bash

set -euo pipefail

# Purpose: Ensure a GitHub release exists and upload VM image asset(s) to it.
#
# Behaviors:
# - Auto-detects tag from debian/changelog (e.g. 0.1.2 -> v0.1.2) if not provided
# - Ensures authenticated gh session; prefers non-interactive token if available
# - Creates the release if missing (with --generate-notes)
# - Uploads provided files or auto-discovers the latest built image(s)
#
# Usage examples:
#   scripts/utils/upload-image.sh --tag v0.1.2 out/vm-0.1.2.qcow2
#   GITHUB_TOKEN=... scripts/utils/upload-image.sh --all
#   scripts/utils/upload-image.sh                 # auto-tag, auto-latest asset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Defaults
TAG=""
NOTES=""
DISCOVERY_ROOT="${REPO_ROOT}/artifacts/images"
GLOB_PATTERN=""   # if provided, overrides default discovery patterns
UPLOAD_ALL=false   # if true, upload all discovered assets; else newest only

log() { printf "[upload-image] %s\n" "$*"; }
err() { printf "[upload-image][error] %s\n" "$*" 1>&2; }
die() { err "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--tag TAG] [--glob PATTERN] [--all] [--notes TEXT] [FILES...]

Options:
  --tag TAG       Release tag (e.g. v0.1.2). If omitted, parsed from debian/changelog as v<version>.
  --glob PATTERN  Glob used to discover assets (rooted at ${DISCOVERY_ROOT}). Implies discovery mode.
  --all           Upload all discovered assets instead of only the newest one.
  --notes TEXT    Extra text to include in generated release notes (only when creating release).
  -h, --help      Show this help.

Positional FILES:
  One or more files to upload. If omitted, script will auto-discover image assets under ${DISCOVERY_ROOT}.

Auth:
  Uses existing gh auth session. If not authenticated and GITHUB_TOKEN is set, logs in non-interactively.
  If still not authenticated and running in an interactive TTY, will invoke web-based login.
EOF
}

is_interactive() { [[ -t 0 && -t 1 ]]; }

parse_args() {
  local arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --tag)
        shift; TAG="${1:-}" || true; [[ -n "$TAG" ]] || die "--tag requires a value"
        ;;
      --glob)
        shift; GLOB_PATTERN="${1:-}" || true; [[ -n "$GLOB_PATTERN" ]] || die "--glob requires a value"
        ;;
      --all)
        UPLOAD_ALL=true
        ;;
      --notes)
        shift; NOTES="${1:-}" || true; [[ -n "$NOTES" ]] || die "--notes requires a value"
        ;;
      -h|--help)
        usage; exit 0
        ;;
      --)
        shift; break
        ;;
      -*)
        die "Unknown option: $arg"
        ;;
      *)
        # Positional file
        break
        ;;
    esac
    shift || true
  done
  # Remaining args are files
  REMAINING_FILES=("$@")
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

parse_tag_from_debian_changelog() {
  local changelog="${REPO_ROOT}/debian/changelog"
  [[ -f "$changelog" ]] || return 1
  # Expect first line like: "servobox (0.1.2) unstable; urgency=medium"
  local first_line
  first_line="$(head -n1 "$changelog" || true)"
  [[ -n "$first_line" ]] || return 1
  local version
  version="$(printf "%s" "$first_line" | sed -n 's/.*(\([^)]\+\)).*/\1/p')"
  [[ -n "$version" ]] || return 1
  printf "v%s" "$version"
}

ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    log "Authenticating to GitHub using GITHUB_TOKEN"
    # shellcheck disable=SC2312
    if printf "%s" "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1; then
      return 0
    else
      err "Token-based authentication failed."
    fi
  fi

  if is_interactive; then
    log "Launching browser-based GitHub login (grant 'repo' scope)"
    gh auth login -w -s "repo" || die "GitHub authentication failed"
    return 0
  fi

  die "Not authenticated to GitHub. Set GITHUB_TOKEN or run interactively to login."
}

ensure_release() {
  local tag="$1"
  if gh release view "$tag" >/dev/null 2>&1; then
    log "Release $tag exists"
    return 0
  fi
  log "Creating release $tag with generated notes"
  if [[ -n "$NOTES" ]]; then
    gh release create "$tag" --generate-notes --notes "$NOTES" >/dev/null
  else
    gh release create "$tag" --generate-notes >/dev/null
  fi
}

discover_assets() {
  local -a files=()

  if [[ ${#REMAINING_FILES[@]} -gt 0 ]]; then
    for f in "${REMAINING_FILES[@]}"; do
      [[ -f "$f" ]] || die "File not found: $f"
      files+=("$f")
    done
    printf '%s\n' "${files[@]}"
    return 0
  fi

  [[ -d "$DISCOVERY_ROOT" ]] || die "Discovery root not found: $DISCOVERY_ROOT"

  local find_expr
  if [[ -n "$GLOB_PATTERN" ]]; then
    # Use provided simple glob pattern(s), comma-separated
    IFS=',' read -r -a patterns <<< "$GLOB_PATTERN"
    for pat in "${patterns[@]}"; do
      while IFS= read -r -d '' p; do files+=("$p"); done < <(find "$DISCOVERY_ROOT" -type f -path "$DISCOVERY_ROOT/$pat" -print0 2>/dev/null || true)
    done
  else
    # Default pattern: only compressed qcow2 images
    while IFS= read -r -d '' p; do files+=("$p"); done < <(
      find "$DISCOVERY_ROOT" -type f \
        \( -name "*.qcow2.xz" \) \
        -print0 2>/dev/null || true
    )
  fi

  [[ ${#files[@]} -gt 0 ]] || die "No assets discovered under $DISCOVERY_ROOT"

  if $UPLOAD_ALL; then
    printf '%s\n' "${files[@]}"
    return 0
  fi

  # Pick newest single file
  local newest
  # shellcheck disable=SC2010
  newest="$(ls -1t -- "${files[@]}" 2>/dev/null | head -n1 || true)"
  [[ -n "$newest" ]] || die "Failed to determine newest asset"
  printf '%s\n' "$newest"
}

upload_assets() {
  local tag="$1"; shift
  local -a assets=("$@")
  log "Uploading ${#assets[@]} asset(s) to release $tag"
  gh release upload "$tag" "${assets[@]}" --clobber
}

main() {
  parse_args "$@"

  require_cmd gh

  if [[ -z "$TAG" ]]; then
    TAG="$(parse_tag_from_debian_changelog || true)"
  fi
  [[ -n "$TAG" ]] || die "Release tag not provided and could not be parsed from debian/changelog"

  ensure_gh_auth
  ensure_release "$TAG"

  mapfile -t ASSETS < <(discover_assets)

  # Safety: refuse to upload extremely large sets by accident unless --all
  if ! $UPLOAD_ALL && [[ ${#ASSETS[@]} -gt 1 ]]; then
    # Should not happen because discover_assets returns one when --all not set
    ASSETS=("${ASSETS[0]}")
  fi

  upload_assets "$TAG" "${ASSETS[@]}"
  log "Done."
}

main "$@"


