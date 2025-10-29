#!/bin/bash
# Setup script for GitHub Pages-based APT repository
# This script initializes the APT repository structure

set -e

REPO_DIR="apt-repo"
GPG_KEY_ID="servobox-apt"

echo "Setting up APT repository structure..."

# Create repository directory structure
mkdir -p "${REPO_DIR}/dists/stable/main/binary-amd64"
mkdir -p "${REPO_DIR}/dists/stable/main/source"

# Create GPG key for signing packages (if it doesn't exist)
if ! gpg --list-secret-keys --keyid-format LONG | grep -q "${GPG_KEY_ID}"; then
    echo "Creating GPG key for package signing..."
    # Create a temporary config file for GPG
    cat > /tmp/gpg-batch.conf << 'EOFGPG'
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ServoBox APT Repository
Name-Email: servobox-apt@users.noreply.github.com
Expire-Date: 0
%commit
EOFGPG
    gpg --batch --full-generate-key /tmp/gpg-batch.conf
    rm /tmp/gpg-batch.conf
else
    echo "GPG key already exists"
fi

# Export public key for users to add to their keyring
echo "Exporting public key..."
gpg --armor --export "${GPG_KEY_ID}" > "${REPO_DIR}/servobox-apt-key.gpg"

echo "APT repository structure created in: ${REPO_DIR}/"
echo "Public key exported to: ${REPO_DIR}/servobox-apt-key.gpg"
echo ""
echo "Next steps:"
echo "1. Commit the ${REPO_DIR}/ directory to your repository"
echo "2. Enable GitHub Pages for the ${REPO_DIR}/ directory"
echo "3. Run add-package-to-repo.sh when you have new .deb files"
