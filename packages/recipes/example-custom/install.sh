#!/usr/bin/env bash
set -euo pipefail

# Example Custom Package Installation Script
# This template shows common patterns for ServoBox recipes

echo "Installing example-custom package..."

# Always set this for non-interactive installations
export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# HELPER FUNCTIONS (Optional but recommended)
# ============================================================================

# Load helper functions if available (provides apt_update, apt_install, etc.)
if [[ -n "${PACKAGE_HELPERS:-}" && -f "${PACKAGE_HELPERS}" ]]; then
  # shellcheck source=/dev/null
  . "${PACKAGE_HELPERS}"
else
  # Fallback to repo-relative helper for local execution
  if [[ -f "$(cd "$(dirname "$0")/../.." && pwd)/scripts/pkg-helpers.sh" ]]; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "$0")/../.." && pwd)/scripts/pkg-helpers.sh"
  fi
fi

# ============================================================================
# EXAMPLE 1: Install system packages via apt
# ============================================================================

echo "Installing system dependencies..."

# Using helpers (preferred):
apt_update
apt_install curl wget git

# Or manually:
# apt-get update
# apt-get install -y curl wget git

# ============================================================================
# EXAMPLE 2: Download and install from source
# ============================================================================

echo "Installing from source..."

# Work in user's home directory
cd /home/servobox-usr || { echo "Error: /home/servobox-usr not available" >&2; exit 1; }

# Clone repository (use --recursive if needed)
# rm -rf example-repo  # Clean any existing
# git clone https://github.com/example/repo.git example-repo
# cd example-repo
# git checkout v1.0.0

# Build and install
# mkdir -p build && cd build
# cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local ..
# cmake --build . -j$(nproc)
# cmake --install .

# ============================================================================
# EXAMPLE 3: Install Python packages
# ============================================================================

echo "Installing Python dependencies..."

# System-wide (use with caution):
# pip3 install numpy scipy matplotlib

# Or create a virtual environment (recommended):
# python3 -m venv /home/servobox-usr/venv
# source /home/servobox-usr/venv/bin/activate
# pip install numpy scipy matplotlib

# ============================================================================
# EXAMPLE 4: Download pre-built binaries
# ============================================================================

echo "Downloading pre-built binaries..."

# Download and extract:
# cd /home/servobox-usr
# wget https://example.com/package.tar.gz
# tar -xzf package.tar.gz
# rm package.tar.gz

# Make executable:
# chmod +x /home/servobox-usr/package/bin/*

# ============================================================================
# EXAMPLE 5: Create configuration files
# ============================================================================

echo "Creating configuration..."

# Create config directory
# mkdir -p /home/servobox-usr/.config/myapp

# Write config file
# cat > /home/servobox-usr/.config/myapp/config.yaml <<EOF
# setting1: value1
# setting2: value2
# EOF

# ============================================================================
# EXAMPLE 6: Set up environment variables
# ============================================================================

# Add to bashrc (so it persists across sessions)
# cat >> /home/servobox-usr/.bashrc <<'EOF'
# # Custom package environment
# export MY_CUSTOM_VAR="/path/to/something"
# export PATH="/home/servobox-usr/custom/bin:$PATH"
# EOF

# ============================================================================
# FINALIZATION
# ============================================================================

# Always set proper ownership for user files
echo "Setting permissions..."
chown -R servobox-usr:servobox-usr /home/servobox-usr 2>/dev/null || true

# Update shared library cache if you installed libraries
ldconfig 2>/dev/null || true

# Clean up apt cache (saves space)
if type apt_cleanup >/dev/null 2>&1; then
  apt_cleanup
else
  apt-get clean
  rm -rf /var/lib/apt/lists/*
fi

echo "example-custom installation completed!"
echo "Package is now available in the VM"
echo ""
echo "Optional: This package includes a run.sh script for demonstration."
echo "You can test it with: servobox run example-custom"

# ============================================================================
# TIPS:
# ============================================================================
# 1. Always use 'set -euo pipefail' at the top (fails on errors)
# 2. Use 'echo' to show progress (helps users follow along)
# 3. Set ownership with 'chown -R servobox-usr:servobox-usr'
# 4. Clean up temporary files and caches
# 5. Test your recipe with: servobox pkg-install --recipe-dir ~/my-recipes example-custom
# 6. Use DEBIAN_FRONTEND=noninteractive for apt operations
# 7. Use $(nproc) for parallel builds (speeds up compilation)
# 8. Check for errors explicitly where needed
# 9. Document any post-install steps users need to know
# 10. Consider idempotency - recipe should work if run multiple times
# 11. Add optional run.sh script for package execution with 'servobox run <package>'

