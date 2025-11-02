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
│       │       └── servobox_*.deb
│       └── Release
└── servobox-apt-key.gpg
```

## How It Works

1. **GitHub Actions** builds the `.deb` package on each release
2. **GitHub Actions** automatically updates this repository with the new package
3. **GitHub Pages** serves the repository at `https://kvasios.github.io/servobox/apt-repo/`
4. **Users** can add this repository to their APT sources and install with `sudo apt install servobox`

## Setup Instructions

### For Users

Add the repository to your system:

```bash
# Add the GPG key using wget (pre-installed on Ubuntu)
wget -qO- https://kvasios.github.io/servobox/apt-repo/servobox-apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/servobox-apt-keyring.gpg

# Or if you prefer curl:
# curl -sSL https://kvasios.github.io/servobox/apt-repo/servobox-apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/servobox-apt-keyring.gpg

# Add the repository
echo "deb [signed-by=/usr/share/keyrings/servobox-apt-keyring.gpg] https://kvasios.github.io/servobox/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/servobox.list

# Update and install
sudo apt update
sudo apt install servobox
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

To enable GitHub Pages for this repository:

1. Go to your repository settings
2. Navigate to "Pages" section
3. Set source to "Deploy from a branch"
4. Select "main" branch and "/apt-repo" folder
5. Save the settings

The repository will be available at: `https://kvasios.github.io/servobox/apt-repo/`

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
