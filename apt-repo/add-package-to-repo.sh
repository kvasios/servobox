#!/bin/bash
# Add one or more .deb packages to the APT repository
# Usage: ./add-package-to-repo.sh path/to/package1.deb [path/to/package2.deb ...]

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path-to-deb-file> [<path-to-deb-file> ...]"
    exit 1
fi

REPO_DIR="apt-repo"
ORIGINAL_DIR="$(pwd)"
BINARY_DIR="${REPO_DIR}/dists/stable/main/binary-amd64"
POOL_DIR="${REPO_DIR}/pool/main/s/servobox"

SIGNING_KEY_FPR="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')"

for DEB_FILE in "$@"; do
    if [ ! -f "$DEB_FILE" ]; then
        echo "Error: $DEB_FILE not found"
        exit 1
    fi
done

# Create repository structure if it doesn't exist
if [ ! -d "${BINARY_DIR}" ]; then
    echo "Creating APT repository structure..."
    mkdir -p "${BINARY_DIR}"
    mkdir -p "${REPO_DIR}/dists/stable/main/source"
    mkdir -p "${POOL_DIR}"
fi

mkdir -p "${POOL_DIR}"

echo "Adding package(s) to APT repository..."
for DEB_FILE in "$@"; do
    echo " - $DEB_FILE"
    # Standard Debian repo layout keeps .deb files under pool/
    cp -f "$DEB_FILE" "${POOL_DIR}/"
done

# Create Packages file
echo "Creating Packages file..."
cd "${ORIGINAL_DIR}/${REPO_DIR}"
dpkg-scanpackages --multiversion pool /dev/null > dists/stable/main/binary-amd64/Packages
gzip -n -k -f dists/stable/main/binary-amd64/Packages

# Create Release file
echo "Creating Release file..."
cd dists/stable
APT_FTPARCHIVE_CONF="$(mktemp)"
cat > "${APT_FTPARCHIVE_CONF}" <<EOF
APT::FTPArchive::Release::Origin "ServoBox APT Repository";
APT::FTPArchive::Release::Label "ServoBox";
APT::FTPArchive::Release::Suite "stable";
APT::FTPArchive::Release::Codename "stable";
APT::FTPArchive::Release::Architectures "amd64";
APT::FTPArchive::Release::Components "main";
APT::FTPArchive::Release::Description "ServoBox - One-command launcher for real-time VMs";
APT::FTPArchive::Release::Acquire-By-Hash "yes";
EOF
apt-ftparchive -c "${APT_FTPARCHIVE_CONF}" release . > Release
rm -f "${APT_FTPARCHIVE_CONF}"

# Sign the Release file (if GPG key is available)
echo "Signing Release file..."
if [ -n "${SIGNING_KEY_FPR}" ]; then
    # Remove old signature files if they exist
    rm -f InRelease Release.gpg

    # Create InRelease (inline-signed Release file) - modern standard
    # Use --batch and --pinentry-mode loopback for non-interactive signing (CI/CD)
    gpg --batch --yes --pinentry-mode loopback --local-user "${SIGNING_KEY_FPR}" --clearsign -o InRelease Release
    # Also create Release.gpg (detached signature) for compatibility
    gpg --batch --yes --pinentry-mode loopback --local-user "${SIGNING_KEY_FPR}" --detach-sign -o Release.gpg Release
    echo "Release file signed successfully (InRelease + Release.gpg created)"
else
    echo "Warning: no secret signing key found. Release file not signed."
    echo "To enable signing, run setup-apt-repo.sh first or import the signing key."
fi

echo "Package added successfully!"
echo "Repository updated in: ${REPO_DIR}/"
echo ""
