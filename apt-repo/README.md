# ServoBox APT Repository

This directory contains the APT repository files for ServoBox, hosted on GitHub Pages.

## Repository Structure

```
apt-repo/
├── dists/
│   └── stable/
│       ├── main/
│       │   └── binary-amd64/
│       │       ├── Packages
│       │       ├── Packages.gz
│       └── Release
├── pool/
│   └── main/
│       └── s/
│           └── servobox/
│               └── servobox_*.deb
└── servobox-archive-keyring.gpg
```

## How It Works

1. **GitHub Actions** builds the `.deb` package on each tagged release
2. **GitHub Actions** updates the APT repository contents on a dedicated **`apt-repo` branch** (so `main` is never modified)
3. **GitHub Pages** serves the repository at `https://kvasios.github.io/servobox/apt-repo/`
4. **Users** add the repo and install with `sudo apt install servobox`

## Setup Instructions

### For Maintainers (CI signing key)

CI must use a **stable** GPG signing key (do not generate a new key per run).

- Create a long-lived key (locally), export the **private key** (ASCII-armored), and add it as a GitHub repository secret named:
  - `APT_GPG_PRIVATE_KEY_ASCII_ARMOR`

### For Users

Add the repository to your system:

```bash
# Install the repository keyring
sudo wget -O /usr/share/keyrings/servobox-archive-keyring.gpg https://kvasios.github.io/servobox/apt-repo/servobox-archive-keyring.gpg

# Or if you prefer curl:
# sudo curl -fsSL -o /usr/share/keyrings/servobox-archive-keyring.gpg https://kvasios.github.io/servobox/apt-repo/servobox-archive-keyring.gpg

# Add the repository
echo "deb [signed-by=/usr/share/keyrings/servobox-archive-keyring.gpg] https://kvasios.github.io/servobox/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/servobox.list

# Update and install
sudo apt update
sudo apt install servobox

# Upgrade later to newest published version
sudo apt update
sudo apt install --only-upgrade servobox
```

### For Developers

The repository is automatically maintained by GitHub Actions. If you need to manually update it:

```bash
# Add a package to the repository
./apt-repo/add-package-to-repo.sh path/to/package.deb

# Commit and push changes
git add apt-repo/
git commit -m "Update APT repository"
git push
```

## GitHub Pages Configuration

This repo uses the **GitHub Pages workflow** (`.github/workflows/pages.yml`) to deploy docs and include the APT repository.
The APT repository contents are sourced from the `apt-repo` branch.

## Security Notes

- The repository uses GPG signing for package verification
- Users should verify the GPG key fingerprint before adding the repository
- The Release file is signed to prevent tampering

## Troubleshooting

### Repository Not Found
- Ensure GitHub Pages is enabled for the `/apt-repo` directory
- Check that the repository URL is correct
- Verify the repository structure matches the expected layout

### GPG Key Issues
- Users can skip verification with `[trusted=yes]` (not recommended)
- Ensure the GPG key is properly exported and accessible

### Package Installation Issues
- Check that all dependencies are installed
- Verify the package architecture matches your system
- Check for conflicts with existing packages
