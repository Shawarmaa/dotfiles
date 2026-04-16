#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$REPO_DIR"

# 1. Install Homebrew if missing
if ! command -v brew >/dev/null 2>&1; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 2. Install everything from the Brewfile
echo "==> Installing Brewfile packages..."
brew bundle --file="$REPO_DIR/Brewfile"

# 3. Clean .DS_Store cruft before stowing
find "$REPO_DIR" -name .DS_Store -delete

# 4. Stow each package
PACKAGES=(zsh git aerospace lazygit yazi kaku nvim)
for pkg in "${PACKAGES[@]}"; do
  echo "==> Stowing $pkg..."
  stow -v --target="$HOME" --restow "$pkg"
done

# 5. Post-install reminders
cat <<EOF

==> Automated steps complete. Manual follow-ups:

  1. Launch Kaku once so it regenerates ~/.config/kaku/zsh/ integration.
  2. Open Raycast -> "Import Preferences & Data" -> select:
       $REPO_DIR/raycast/raycast.rayconfig
  3. Sign in to the Mac App Store, then re-run:
       brew bundle --file=$REPO_DIR/Brewfile
     (so 'mas' can install Xcode)

EOF
