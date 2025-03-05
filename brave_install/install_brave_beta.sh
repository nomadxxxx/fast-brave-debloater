#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Logging functions
log_message() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

log_message "Installing Brave Browser (Beta)..."

# Detect distribution
if [ -f /etc/nixos/configuration.nix ]; then
  # NixOS
  log_message "Detected NixOS distribution"
  log_message "Installing Brave Beta using nix-env..."
  if nix-env -iA nixpkgs.brave-beta; then
    log_message "Brave Browser (Beta) installed successfully on NixOS."
    exit 0
  else
    log_error "Failed to install Brave Browser (Beta) on NixOS."
    exit 1
  fi

elif command -v apt &> /dev/null; then
  # Debian/Ubuntu based
  log_message "Detected Debian/Ubuntu-based distribution"
  sudo apt install apt-transport-https curl -y
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-beta-archive-keyring.gpg https://brave-browser-apt-beta.s3.brave.com/brave-browser-beta-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-beta-archive-keyring.gpg arch=amd64] https://brave-browser-apt-beta.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-beta-release.list
  sudo apt update
  sudo apt install brave-browser-beta -y
  
elif command -v dnf &> /dev/null; then
  # Fedora based
  log_message "Detected Fedora-based distribution"
  sudo dnf install dnf-plugins-core -y
  sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  sudo rpm --import https://brave-browser-rpm-beta.s3.brave.com/brave-core-beta.asc
  sudo dnf install brave-browser-beta -y
  
elif command -v pacman &> /dev/null; then
  # Arch based
  log_message "Detected Arch-based distribution"
  if command -v yay &> /dev/null; then
    yay -S brave-beta-bin
  else
    log_error "yay not found. Please install yay first."
    exit 1
  fi
  
elif command -v zypper &> /dev/null; then
  # OpenSUSE
  log_message "Detected OpenSUSE distribution"
  sudo rpm --import https://brave-browser-rpm-beta.s3.brave.com/brave-core-beta.asc
  sudo zypper addrepo https://brave-browser-rpm-beta.s3.brave.com/brave-browser-beta.repo
  sudo zypper install brave-browser-beta -y
  
else
  log_error "Unsupported distribution. Please install Brave Beta manually."
  exit 1
fi

# Check if installation was successful
if command -v brave-browser-beta &> /dev/null; then
  log_message "Brave Browser (Beta) installed successfully."
  exit 0
else
  log_error "Failed to install Brave Browser (Beta)."
fi

# At the end of the script, before exiting:
if ! command -v brave-browser-beta &> /dev/null; then
  log_message "Standard installation methods failed. Trying Brave's official install script..."
  curl -fsS https://dl.brave.com/install.sh | sh
  
  # Check again if installation succeeded
  if command -v brave-browser-beta &> /dev/null; then
    log_message "Brave Browser (Beta) installed successfully using official script."
    exit 0
  else
    log_error "All installation methods failed."
    exit 1
  fi
fi
