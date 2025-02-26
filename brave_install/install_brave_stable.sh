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

log_message "Installing Brave Browser (Stable)..."

# Detect distribution
if command -v apt &> /dev/null; then
  # Debian/Ubuntu based
  log_message "Detected Debian/Ubuntu-based distribution"
  sudo apt install apt-transport-https curl -y
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
  sudo apt update
  sudo apt install brave-browser -y
  
elif command -v dnf &> /dev/null; then
  # Fedora based
  log_message "Detected Fedora-based distribution"
  sudo dnf install dnf-plugins-core -y
  sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
  sudo dnf install brave-browser -y
  
elif command -v pacman &> /dev/null; then
  # Arch based
  log_message "Detected Arch-based distribution"
  if command -v yay &> /dev/null; then
    yay -S brave-bin
  else
    log_error "yay not found. Please install yay first."
    exit 1
  fi
  
elif command -v zypper &> /dev/null; then
  # OpenSUSE
  log_message "Detected OpenSUSE distribution"
  sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
  sudo zypper addrepo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  sudo zypper install brave-browser -y
  
else
  log_error "Unsupported distribution. Please install Brave manually."
  exit 1
fi

# Check if installation was successful
if command -v brave-browser &> /dev/null || command -v brave &> /dev/null; then
  log_message "Brave Browser (Stable) installed successfully."
  exit 0
else
  log_error "Failed to install Brave Browser (Stable)."
  exit 1
fi
# At the end of the script, before exiting:
if ! command -v brave-browser &> /dev/null && ! command -v brave &> /dev/null; then
  log_message "Standard installation methods failed. Trying Brave's official install script..."
  curl -fsS https://dl.brave.com/install.sh | sh
  
  # Check again if installation succeeded
  if command -v brave-browser &> /dev/null || command -v brave &> /dev/null; then
    log_message "Brave Browser (Stable) installed successfully using official script."
    exit 0
  else
    log_error "All installation methods failed."
    exit 1
  fi
fi
