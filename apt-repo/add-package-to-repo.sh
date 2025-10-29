#!/bin/bash
# Add a .deb package to the APT repository
# Usage: ./add-package-to-repo.sh path/to/package.deb

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <path-to-deb-file>"
    exit 1
fi

DEB_FILE="$1"
REPO_DIR="apt-repo"
GPG_KEY_ID="servobox-apt"
ORIGINAL_DIR="$(pwd)"

if [ ! -f "$DEB_FILE" ]; then
    echo "Error: $DEB_FILE not found"
    exit 1
fi

# Create repository structure if it doesn't exist
if [ ! -d "${REPO_DIR}/dists/stable/main/binary-amd64" ]; then
    echo "Creating APT repository structure..."
    mkdir -p "${REPO_DIR}/dists/stable/main/binary-amd64"
    mkdir -p "${REPO_DIR}/dists/stable/main/source"
fi

echo "Adding $DEB_FILE to APT repository..."

# Copy package to repository
cp "$DEB_FILE" "${REPO_DIR}/dists/stable/main/binary-amd64/"

# Create Packages file
echo "Creating Packages file..."
cd "${REPO_DIR}/dists/stable/main/binary-amd64"
# Use --multiversion to handle multiple versions, output relative path from dists/stable/
dpkg-scanpackages --multiversion . /dev/null | sed 's|^Filename: \./|Filename: dists/stable/main/binary-amd64/|' > Packages
gzip -k -f Packages

# Create Release file
echo "Creating Release file..."
cd "${ORIGINAL_DIR}/${REPO_DIR}/dists/stable"
cat > Release <<EOF
Origin: ServoBox APT Repository
Label: ServoBox
Suite: stable
Codename: stable
Version: 1.0
Architectures: amd64
Components: main
Description: ServoBox - One-command launcher for real-time VMs
EOF

# Add checksums
apt-ftparchive release . >> Release

# Sign the Release file (if GPG key is available)
echo "Signing Release file..."
if gpg --list-secret-keys --keyid-format LONG | grep -q "${GPG_KEY_ID}"; then
    # Remove old signature files if they exist
    rm -f InRelease Release.gpg
    
    # Create InRelease (inline-signed Release file) - modern standard
    # Use --batch and --pinentry-mode loopback for non-interactive signing (CI/CD)
    gpg --batch --pinentry-mode loopback --clearsign --armor --default-key "${GPG_KEY_ID}" -o InRelease Release
    # Also create Release.gpg (detached signature) for compatibility
    gpg --batch --pinentry-mode loopback --armor --detach-sign --default-key "${GPG_KEY_ID}" -o Release.gpg Release
    echo "Release file signed successfully (InRelease + Release.gpg created)"
else
    echo "Warning: GPG key '${GPG_KEY_ID}' not found. Release file not signed."
    echo "To enable signing, run setup-apt-repo.sh first or import the signing key."
fi

echo "Package added successfully!"
echo "Repository updated in: ${REPO_DIR}/"
echo ""
