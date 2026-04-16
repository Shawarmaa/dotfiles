#!/usr/bin/env bash
set -uo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$REPO_DIR"

if [ -t 1 ]; then
  B=$(tput bold); D=$(tput dim); R=$(tput sgr0)
  G=$(tput setaf 2); Y=$(tput setaf 3); C=$(tput setaf 6)
else
  B=""; D=""; R=""; G=""; Y=""; C=""
fi

step() { echo; echo "${B}${C}==> $1${R}"; }
START=$SECONDS

# -----------------------------------------------------------------------------
step "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  echo "${D}   installing...${R}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >/dev/null 2>&1
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "   ${G}✓${R} $(brew --version | head -1)"

# -----------------------------------------------------------------------------
BREWFILE="$REPO_DIR/Brewfile"
TOTAL=$(grep -cE '^(brew|cask|tap|mas) ' "$BREWFILE")
step "Installing $TOTAL packages"

# All brew output silenced. Only the rolling counter shows.
brew bundle --file="$BREWFILE" --no-upgrade 2>/dev/null | awk -v total="$TOTAL" -v D="$D" -v R="$R" '
  /^(Installing|Using|Tapping) [^ ]+$/ {
    if (count < total) count++
    printf "\r\033[K   %s[%d/%d]%s %s", D, count, total, R, $2
    fflush()
  }
' || true
echo

# Summarize: count missing packages after the run
MISSING=$(brew bundle check --file="$BREWFILE" --no-upgrade --verbose 2>/dev/null | grep -c -E "not installed|needs to be installed" || true)
if [ "${MISSING:-0}" -eq 0 ]; then
  echo "   ${G}✓${R} all $TOTAL packages installed"
else
  echo "   ${Y}!${R} $MISSING package(s) skipped (often pre-existing apps — safe to ignore)"
fi

# -----------------------------------------------------------------------------
step "Cleaning .DS_Store"
DEL=$(find "$REPO_DIR" -name .DS_Store -print -delete 2>/dev/null | wc -l | tr -d ' ')
echo "   ${G}✓${R} removed $DEL file(s)"

# -----------------------------------------------------------------------------
PKGS=(zsh git aerospace lazygit yazi kaku nvim)
step "Stowing ${#PKGS[@]} packages"
STOW_ERR=$(mktemp)
for i in "${!PKGS[@]}"; do
  n=$((i + 1))
  pkg="${PKGS[$i]}"
  printf "\r\033[K   ${D}[%d/%d]${R} %s" "$n" "${#PKGS[@]}" "$pkg"
  if ! stow --target="$HOME" --restow "$pkg" 2>"$STOW_ERR"; then
    echo
    cat "$STOW_ERR"
    rm -f "$STOW_ERR"
    exit 1
  fi
done
rm -f "$STOW_ERR"
echo
echo "   ${G}✓${R} all packages stowed"

# -----------------------------------------------------------------------------
ELAPSED=$((SECONDS - START))
echo
echo "${B}${G}✓ Done${R} in $((ELAPSED / 60))m$((ELAPSED % 60))s"
echo
cat <<EOF
${B}Next:${R}
  1. Launch Kaku once (regenerates shell integration)
  2. Raycast → "Import Preferences & Data" → $REPO_DIR/raycast/raycast.rayconfig
  3. After App Store sign-in, re-run: brew bundle --file=$REPO_DIR/Brewfile
EOF
