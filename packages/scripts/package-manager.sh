#!/usr/bin/env bash
set -euo pipefail

# ServoBox Package Manager
# Manages software package recipes for building ServoBox images

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# Determine base directory and support both repo and installed layouts
# Repo layout:
#   packages/scripts/package-manager.sh
#   packages/recipes/
# Installed layout (per debian .install):
#   /usr/share/servobox/scripts/package-manager.sh
#   /usr/share/servobox/packages/recipes/
BASE_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

if [[ -d "${BASE_DIR}/recipes" ]]; then
  # Repo layout: BASE_DIR == <repo>/packages
  PACKAGES_DIR="${BASE_DIR}"
  RECIPES_DIR="${PACKAGES_DIR}/recipes"
elif [[ -d "${BASE_DIR}/packages/recipes" ]]; then
  # Installed layout: BASE_DIR == /usr/share/servobox
  PACKAGES_DIR="${BASE_DIR}"
  RECIPES_DIR="${PACKAGES_DIR}/packages/recipes"
else
  # Fallback to repo layout paths; errors will be raised later if missing
  PACKAGES_DIR="${BASE_DIR}"
  RECIPES_DIR="${PACKAGES_DIR}/recipes"
fi

usage() {
  cat <<EOF
package-manager.sh - Manage ServoBox software packages

Usage:
  package-manager.sh <command> [options]

Commands:
  list                    List all available packages
  deps <package>          Show dependency tree for a package
  build <package>         Build a specific package
  validate                Validate all package recipes
  install <package> <img> Install package (with dependencies) into image
  installed <img>         List packages already installed in image
  sync-tracking <img>     Sync host tracking file from VM image (for recovery)

Options:
  --verbose               Enable verbose output
  --dry-run               Show what would be done without executing
  --force                 Force rebuild even if already built
  --force-package PKG     Force reinstall only the specified package (not dependencies)
  --recipe-dir DIR        Use custom recipe directory (for testing/development)

Examples:
  package-manager.sh list
  package-manager.sh deps serl-franka-controllers
  package-manager.sh build ros2-humble
  package-manager.sh validate
  package-manager.sh install serl-franka-controllers image.qcow2
  package-manager.sh --recipe-dir ~/my-recipes list
  package-manager.sh --recipe-dir ~/my-recipes install my-pkg image.qcow2

Notes:
  - The 'install' command automatically resolves and installs dependencies
  - Use 'deps' to see what will be installed before running 'install'
  - Dependencies are declared in each recipe's recipe.conf file
EOF
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_verbose() {
  if [[ "${VERBOSE:-0}" -eq 1 ]]; then
    log "$*"
  fi
}

error() {
  echo "Error: $*" >&2
  exit 1
}

# Check if a package recipe exists and is valid
validate_package() {
  local package="$1"
  local recipe_dir="${RECIPES_DIR}/${package}"
  
  if [[ ! -d "$recipe_dir" ]]; then
    error "Package recipe not found: $package"
  fi
  
  local recipe_conf="${recipe_dir}/recipe.conf"
  local install_script="${recipe_dir}/install.sh"
  
  if [[ ! -f "$recipe_conf" ]]; then
    error "Package $package missing recipe.conf"
  fi
  
  if [[ ! -f "$install_script" ]]; then
    error "Package $package missing install.sh"
  fi
  
  if [[ ! -x "$install_script" ]]; then
    error "Package $package install.sh is not executable"
  fi
  
  # Validate recipe.conf format
  if ! grep -q "^name=" "$recipe_conf"; then
    error "Package $package recipe.conf missing 'name' field"
  fi
  
  if ! grep -q "^version=" "$recipe_conf"; then
    error "Package $package recipe.conf missing 'version' field"
  fi
  
  log_verbose "Package $package is valid"
  return 0
}

# Load package metadata from recipe.conf
load_package_metadata() {
  local package="$1"
  local recipe_dir="${RECIPES_DIR}/${package}"
  local recipe_conf="${recipe_dir}/recipe.conf"
  
  if [[ ! -f "$recipe_conf" ]]; then
    error "Package $package recipe.conf not found"
  fi
  
  # Source the recipe configuration
  # shellcheck source=/dev/null
  source "$recipe_conf"
}

# Parse dependencies from recipe.conf
# Returns space-separated list of dependencies
get_package_dependencies() {
  local package="$1"
  
  # Clear any previously set dependencies
  unset dependencies
  
  load_package_metadata "$package"
  
  # Return dependencies (space or comma separated, normalize to space)
  echo "${dependencies:-}" | tr ',' ' '
}

# Topological sort using DFS (Depth-First Search)
# Returns packages in installation order (dependencies first)
topological_sort() {
  local -a packages=("$@")
  local -A visited=()
  local -A in_progress=()
  local -a sorted=()
  
  visit() {
    local pkg="$1"
    
    # Check for circular dependency
    if [[ "${in_progress[$pkg]:-0}" == "1" ]]; then
      error "Circular dependency detected: $pkg"
    fi
    
    # Skip if already visited
    if [[ "${visited[$pkg]:-0}" == "1" ]]; then
      return 0
    fi
    
    # Mark as in progress
    in_progress[$pkg]=1
    
    # Visit dependencies first
    local deps
    deps=$(get_package_dependencies "$pkg" 2>/dev/null || echo "")
    
    for dep in $deps; do
      dep=$(echo "$dep" | xargs) # trim whitespace
      if [[ -n "$dep" ]]; then
        visit "$dep"
      fi
    done
    
    # Mark as visited
    visited[$pkg]=1
    in_progress[$pkg]=0
    
    # Add to sorted list
    sorted+=("$pkg")
  }
  
  # Visit each package
  for pkg in "${packages[@]}"; do
    if [[ -n "$pkg" ]]; then
      visit "$pkg"
    fi
  done
  
  # Return sorted list
  echo "${sorted[@]}"
}

# Resolve dependencies for a package and return install order
resolve_dependencies() {
  local package="$1"
  
  log_verbose "Resolving dependencies for: $package"
  
  # Get topologically sorted list
  local sorted
  sorted=$(topological_sort "$package")
  
  echo "$sorted"
}

# List all available packages
cmd_list() {
  for recipe_dir in "${RECIPES_DIR}"/*; do
    if [[ ! -d "$recipe_dir" ]]; then
      continue
    fi
    
    local package
    package=$(basename "$recipe_dir")
    
    if validate_package "$package" 2>/dev/null; then
      load_package_metadata "$package"
      printf "  %-20s %-10s %s\n" "$package" "${version:-unknown}" "${description:-No description}"
    else
      printf "  %-20s %s\n" "$package" "(invalid recipe)"
    fi
  done
}

# Build a specific package
cmd_build() {
  local package="$1"
  
  if [[ -z "$package" ]]; then
    error "Package name required"
  fi
  
  validate_package "$package"
  load_package_metadata "$package"
  
  log "Building package: $package (version: ${version:-unknown})"
  
  local recipe_dir="${RECIPES_DIR}/${package}"
  local install_script="${recipe_dir}/install.sh"
  
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "DRY RUN: Would execute $install_script"
    return 0
  fi
  
  # Change to recipe directory for relative paths
  cd "$recipe_dir"
  
  # Set environment variables for the install script
  export PACKAGE_NAME="$package"
  export PACKAGE_VERSION="${version:-}"
  export PACKAGE_DESCRIPTION="${description:-}"
  export VERBOSE="${VERBOSE:-0}"
  
  # Execute the install script
  if [[ "${VERBOSE:-0}" -eq 1 ]]; then
    bash -x "$install_script"
  else
    bash "$install_script"
  fi
  
  log "Package $package built successfully"
}

# Validate all package recipes
cmd_validate() {
  local errors=0
  
  log "Validating all package recipes..."
  
  for recipe_dir in "${RECIPES_DIR}"/*; do
    if [[ ! -d "$recipe_dir" ]]; then
      continue
    fi
    
    local package
    package=$(basename "$recipe_dir")
    
    if validate_package "$package" 2>/dev/null; then
      log_verbose "✓ $package is valid"
    else
      log "✗ $package is invalid"
      ((errors++))
    fi
  done
  
  if [[ $errors -eq 0 ]]; then
    log "All packages are valid"
  else
    log "$errors package(s) have errors"
    exit 1
  fi
}

# Install package into image (with automatic dependency resolution)
cmd_install() {
  local package="$1"
  local image="$2"
  
  if [[ -z "$package" || -z "$image" ]]; then
    error "Package name and image path required"
  fi
  
  if [[ ! -f "$image" ]]; then
    error "Image file not found: $image"
  fi
  
  # Validate the requested package exists
  validate_package "$package"
  
  # Resolve dependencies and get installation order
  log "Resolving dependencies for $package..."
  local install_order
  install_order=$(resolve_dependencies "$package")
  
  if [[ -z "$install_order" ]]; then
    error "Failed to resolve dependencies for $package"
  fi
  
  # Show what will be installed
  local pkg_count
  pkg_count=$(echo "$install_order" | wc -w)
  
  if [[ $pkg_count -gt 1 ]]; then
    log "Will install $pkg_count packages in order: $install_order"
  else
    log "Installing package: $package (no dependencies)"
  fi
  
  # Install each package in dependency order
  for pkg in $install_order; do
    pkg=$(echo "$pkg" | xargs) # trim whitespace
    if [[ -z "$pkg" ]]; then
      continue
    fi
    
    install_single_package "$pkg" "$image"
  done
  
  log "All packages installed successfully"
}

# Get the host-side tracking file path for a VM image
get_image_tracking_file() {
  local image="$1"
  # Create tracking file next to the image with .servobox-packages extension
  echo "${image}.servobox-packages"
}

# Check if a package is already installed in the image (using host-side tracking)
is_package_installed_in_image() {
  local package="$1"
  local image="$2"
  local tracking_file
  
  tracking_file=$(get_image_tracking_file "$image")
  
  # If tracking file doesn't exist, nothing is installed yet
  if [[ ! -f "$tracking_file" ]]; then
    return 1
  fi
  
  # Check if package is in the tracking file
  if grep -q "^${package}$" "$tracking_file" 2>/dev/null; then
    return 0  # Package is installed
  else
    return 1  # Package is not installed
  fi
}

# Mark a package as installed in the host-side tracking file
mark_package_installed_in_tracking() {
  local package="$1"
  local image="$2"
  local tracking_file
  
  tracking_file=$(get_image_tracking_file "$image")
  
  # Create tracking file directory if needed
  mkdir -p "$(dirname "$tracking_file")"
  
  # Add package to tracking file if not already there
  if ! grep -q "^${package}$" "$tracking_file" 2>/dev/null; then
    echo "$package" >> "$tracking_file"
  fi
}

# Install a single package into image (internal function, called by cmd_install)
install_single_package() {
  local package="$1"
  local image="$2"
  
  validate_package "$package"
  load_package_metadata "$package"
  
  # Check if package is already installed (unless --force or --force-package is specified)
  local should_force=0
  if [[ "${FORCE:-0}" -eq 1 ]]; then
    should_force=1
  elif [[ -n "${FORCE_PACKAGE:-}" && "${FORCE_PACKAGE}" == "$package" ]]; then
    should_force=1
  fi
  
  if [[ $should_force -ne 1 ]] && is_package_installed_in_image "$package" "$image"; then
    log "Package $package is already installed, skipping (use --force or --force-package to reinstall)"
    return 0
  fi
  
  log "Installing package $package into image $image"
  echo ""
  echo "⏳ Package installation in progress..."
  echo "   This may take several minutes (especially for packages that compile from source)"
  echo "   virt-customize buffers output - you'll see results when complete"
  echo ""
  # Environment defaults for libguestfs
  export LIBGUESTFS_BACKEND=${LIBGUESTFS_BACKEND:-direct}
  export LIBGUESTFS_MEMSIZE=${LIBGUESTFS_MEMSIZE:-6144}
  
  local recipe_dir="${RECIPES_DIR}/${package}"
  local install_script="${recipe_dir}/install.sh"
  local helpers_script="${PACKAGES_DIR}/scripts/pkg-helpers.sh"
  local script_base
  script_base=$(basename "$install_script")
  local recipe_name
  recipe_name=$(basename "$recipe_dir")
  
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "DRY RUN: Would install $package into $image using virt-customize"
    return 0
  fi
  
  # In verbose mode, show virt-customize output directly; otherwise capture it
  if [[ "${VERBOSE:-0}" -eq 1 ]]; then
    log_verbose "Running virt-customize with verbose output..."
    log_verbose "Command: virt-customize -v -a $image --memsize ${LIBGUESTFS_MEMSIZE}"
    log_verbose "  --copy-in $install_script:/tmp/"
    log_verbose "  --copy-in $helpers_script:/tmp/"
    log_verbose "  --run-command 'chmod +x /tmp/${script_base}'"
    log_verbose "  --run-command 'PACKAGE_NAME=$package ... bash /tmp/${script_base}'"
    
    # Run with output visible (add -v to virt-customize and use bash -x for script tracing)
    if virt-customize -v -a "$image" \
        --memsize ${LIBGUESTFS_MEMSIZE} \
        --copy-in "$recipe_dir:/tmp/" \
        --copy-in "$helpers_script:/tmp/" \
        --run-command "chmod +x /tmp/${recipe_name}/${script_base}" \
        --run-command "PACKAGE_NAME='$package' PACKAGE_VERSION='${version:-}' PACKAGE_HELPERS='/tmp/pkg-helpers.sh' RECIPE_DIR='/tmp/${recipe_name}' bash -x /tmp/${recipe_name}/${script_base}" \
        --run-command "mkdir -p /var/lib/servobox && echo '$package' >> /var/lib/servobox/installed-packages" \
        --run-command "rm -rf /tmp/${recipe_name} /tmp/pkg-helpers.sh"; then
      :
    else
      if sudo -n env LIBGUESTFS_BACKEND="${LIBGUESTFS_BACKEND}" LIBGUESTFS_MEMSIZE="${LIBGUESTFS_MEMSIZE}" virt-customize -v -a "$image" \
          --memsize ${LIBGUESTFS_MEMSIZE} \
          --copy-in "$recipe_dir:/tmp/" \
          --copy-in "$helpers_script:/tmp/" \
          --run-command "chmod +x /tmp/${recipe_name}/${script_base}" \
          --run-command "PACKAGE_NAME='$package' PACKAGE_VERSION='${version:-}' PACKAGE_HELPERS='/tmp/pkg-helpers.sh' RECIPE_DIR='/tmp/${recipe_name}' bash -x /tmp/${recipe_name}/${script_base}" \
          --run-command "mkdir -p /var/lib/servobox && echo '$package' >> /var/lib/servobox/installed-packages" \
          --run-command "rm -rf /tmp/${recipe_name} /tmp/pkg-helpers.sh"; then
        :
      else
        error "virt-customize failed. Ensure libguestfs is installed and /dev/kvm is accessible."
      fi
    fi
  else
    # Normal mode: virt-customize buffers all output until completion
    # Show a progress indicator while it runs
    
    # Start virt-customize in background with output to temp file
    TMP_OUT=$(mktemp)
    virt-customize -a "$image" \
        --memsize ${LIBGUESTFS_MEMSIZE} \
        --copy-in "$recipe_dir:/tmp/" \
        --copy-in "$helpers_script:/tmp/" \
        --run-command "chmod +x /tmp/${recipe_name}/${script_base}" \
        --run-command "PACKAGE_NAME='$package' PACKAGE_VERSION='${version:-}' PACKAGE_HELPERS='/tmp/pkg-helpers.sh' RECIPE_DIR='/tmp/${recipe_name}' bash /tmp/${recipe_name}/${script_base}" \
        --run-command "mkdir -p /var/lib/servobox && echo '$package' >> /var/lib/servobox/installed-packages" \
        --run-command "rm -rf /tmp/${recipe_name} /tmp/pkg-helpers.sh" >"${TMP_OUT}" 2>&1 &
    VC_PID=$!
    
    # Show progress while it runs
    elapsed=0
    while kill -0 $VC_PID 2>/dev/null; do
      if (( elapsed % 10 == 0 && elapsed > 0 )); then
        echo "   Still working... ($elapsed seconds elapsed)"
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done
    
    # Wait for completion and get exit code
    wait $VC_PID
    VC_EXIT=$?
    
    # Show the output now
    echo ""
    cat "${TMP_OUT}"
    echo ""
    
    if [ $VC_EXIT -ne 0 ]; then
      rm -f "${TMP_OUT}"
      log "First attempt failed with exit code $VC_EXIT"
      
      # Try with sudo if permissions might be the issue
      echo ""
      echo "⚠️  Retrying with sudo (may require password)..."
      echo ""
      
      TMP_OUT_SUDO=$(mktemp)
      if sudo -n env LIBGUESTFS_BACKEND="${LIBGUESTFS_BACKEND}" LIBGUESTFS_MEMSIZE="${LIBGUESTFS_MEMSIZE}" virt-customize -a "$image" \
          --memsize ${LIBGUESTFS_MEMSIZE} \
          --copy-in "$recipe_dir:/tmp/" \
          --copy-in "$helpers_script:/tmp/" \
          --run-command "chmod +x /tmp/${recipe_name}/${script_base}" \
          --run-command "PACKAGE_NAME='$package' PACKAGE_VERSION='${version:-}' PACKAGE_HELPERS='/tmp/pkg-helpers.sh' RECIPE_DIR='/tmp/${recipe_name}' bash /tmp/${recipe_name}/${script_base}" \
          --run-command "mkdir -p /var/lib/servobox && echo '$package' >> /var/lib/servobox/installed-packages" \
          --run-command "rm -rf /tmp/${recipe_name} /tmp/pkg-helpers.sh" >"${TMP_OUT_SUDO}" 2>&1; then
        echo ""
        cat "${TMP_OUT_SUDO}"
        rm -f "${TMP_OUT_SUDO}"
      else
        echo ""
        cat "${TMP_OUT_SUDO}"
        rm -f "${TMP_OUT_SUDO}"
        echo ""
        error "Package installation failed even with sudo. See error output above. If this is a permissions issue, try: sudo usermod -aG kvm,libvirt \$USER && newgrp kvm"
      fi
    else
      rm -f "${TMP_OUT}"
    fi
  fi
  
  # Mark package as installed in host-side tracking file
  mark_package_installed_in_tracking "$package" "$image"
  
  log "Package $package installed successfully"
}

# List packages already installed in image
cmd_installed() {
  local image="$1"
  
  if [[ -z "$image" ]]; then
    error "Image path required"
  fi
  
  if [[ ! -f "$image" ]]; then
    error "Image file not found: $image"
  fi
  
  local tracking_file
  tracking_file=$(get_image_tracking_file "$image")
  
  log "Installed packages in: $image"
  echo ""
  
  if [[ -f "$tracking_file" && -s "$tracking_file" ]]; then
    echo "Installed packages:"
    while IFS= read -r pkg; do
      echo "  • $pkg"
    done < "$tracking_file"
    echo ""
    echo "Total: $(wc -l < "$tracking_file") package(s)"
  else
    echo "No packages have been installed yet via servobox package manager"
  fi
}

# Sync tracking file from VM image (for recovery/migration scenarios)
cmd_sync_tracking() {
  local image="${1:-}"
  
  if [[ -z "$image" ]]; then
    error "Image path required for sync-tracking command"
  fi
  
  if [[ ! -f "$image" ]]; then
    error "Image file not found: $image"
  fi
  
  local tracking_file
  tracking_file=$(get_image_tracking_file "$image")
  
  log "Syncing package tracking from VM image to host..."
  
  # Extract the installed packages list from VM to host
  if virt-cat -a "$image" /var/lib/servobox/installed-packages > "$tracking_file" 2>/dev/null; then
    log "Successfully synced tracking file: $tracking_file"
    echo ""
    echo "Synced packages:"
    while IFS= read -r pkg; do
      echo "  • $pkg"
    done < "$tracking_file"
  else
    log "No package tracking found in VM image"
    rm -f "$tracking_file"
  fi
}

# Show package dependencies
cmd_deps() {
  local package="$1"
  
  if [[ -z "$package" ]]; then
    error "Package name required"
  fi
  
  validate_package "$package"
  
  log "Dependency tree for: $package"
  echo
  
  # Get dependencies
  local deps
  deps=$(get_package_dependencies "$package")
  
  if [[ -z "$deps" ]]; then
    echo "  (no dependencies)"
  else
    echo "  Direct dependencies: $deps"
    echo
    echo "  Installation order:"
    local install_order
    install_order=$(resolve_dependencies "$package")
    local idx=1
    for pkg in $install_order; do
      if [[ "$pkg" == "$package" ]]; then
        echo "    $idx. $pkg (requested package)"
      else
        echo "    $idx. $pkg"
      fi
      idx=$((idx + 1))
    done
  fi
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose) VERBOSE=1; shift;;
      --dry-run) DRY_RUN=1; shift;;
      --force) FORCE=1; shift;;
      -h|--help) usage; exit 0;;
      *) break;;
    esac
  done
}

# Main command dispatcher
main() {
  local cmd="${1:-help}"
  shift || true
  
  # Parse flags and get remaining args
  local remaining_args=()
  local custom_recipe_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose) VERBOSE=1; shift;;
      --dry-run) DRY_RUN=1; shift;;
      --force) FORCE=1; shift;;
      --force-package) FORCE_PACKAGE="$2"; shift 2;;
      --recipe-dir) custom_recipe_dir="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) remaining_args+=("$1"); shift;;
    esac
  done
  
  # Override recipes directory if specified
  if [[ -n "${custom_recipe_dir}" ]]; then
    if [[ ! -d "${custom_recipe_dir}" ]]; then
      error "Custom recipe directory not found: ${custom_recipe_dir}"
    fi
    RECIPES_DIR="${custom_recipe_dir}"
    log_verbose "Using custom recipe directory: ${RECIPES_DIR}"
  fi
  
  case "$cmd" in
    list) cmd_list;;
    deps) cmd_deps "${remaining_args[@]}";;
    build) cmd_build "${remaining_args[@]}";;
    validate) cmd_validate;;
    install) cmd_install "${remaining_args[@]}";;
    installed) cmd_installed "${remaining_args[@]}";;
    sync-tracking) cmd_sync_tracking "${remaining_args[@]}";;
    help|*) usage; exit 1;;
  esac
}

main "$@"
