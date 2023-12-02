#!/bin/bash

# Define your repository and target directory
REPO_URL="https://github.com/sebdanielsson/infra.git"
TARGET_DIR="$HOME/Git/infra"
HOMEBREW_PACKAGES=(ansible 1password 1password-cli)

# Check for root privileges
if [ $UID -eq 0 ]; then
    echo "You should not run this script as root. Exiting."
    exit 0
fi

# Clone the infra repo if not cloned
if [ -d "$TARGET_DIR" ]; then
    echo "Repository directory already exists. Pulling latest changes."
    cd "$TARGET_DIR" || exit
    git pull
else
    echo "Cloning repository."
    git clone "$REPO_URL" "$TARGET_DIR"
fi

# Install Ansible dependencies
if [ -d "$TARGET_DIR" ]; then
    echo "Installing Ansible dependencies."
    cd "$TARGET_DIR/ansible" || exit
    ansible-galaxy install -r requirements.yml
fi

# Install Homebrew if not installed
if ! command -v brew >/dev/null; then
    echo "Homebrew is not installed. Installing Homebrew."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)" >> /Users/sebastian/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "Homebrew is already installed. Updating Homebrew."
    brew upgrade
fi

# Install Homebrew packages
echo "Installing Homebrew packages."
brew install "${HOMEBREW_PACKAGES[@]}"

# Start 1Password.app to login
echo "The script will start 1Password and then exit. Please login to 1Password and enable the 1Password CLI, then run 'op signin' in the terminal."
read -t 5 -p "Opening 1Password in 10 seconds. Press enter to skip countdown." -r
open -a 1Password
exit 0
