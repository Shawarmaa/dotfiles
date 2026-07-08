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
# Usage:
#   ./install.sh                 full install (apps + all configs)
#   ./install.sh apps            Homebrew/Brewfile + bun packages only
#   ./install.sh nvim kaku ...   stow only the named config packages
ALL_PKGS=(zsh git aerospace lazygit yazi kaku nvim claude agents)
DO_APPS=1
PKGS=("${ALL_PKGS[@]}")
if [ $# -gt 0 ]; then
  if [ "$1" = "apps" ]; then
    PKGS=()
  else
    DO_APPS=0
    PKGS=()
    for a in "$@"; do
      case " ${ALL_PKGS[*]} " in
        *" $a "*) PKGS+=("$a") ;;
        *) echo "unknown package: $a"; echo "available: ${ALL_PKGS[*]} (or 'apps')"; exit 1 ;;
      esac
    done
  fi
fi

# -----------------------------------------------------------------------------
if [ "$DO_APPS" -eq 1 ]; then
step "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  echo "${D}   installing...${R}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >/dev/null 2>&1
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "   ${G}✓${R} $(brew --version | head -1)"

# -----------------------------------------------------------------------------
BREWFILE="$REPO_DIR/Brewfile"

# Homebrew 6+ refuses to install from untrusted third-party taps
if brew trust --help >/dev/null 2>&1; then
  grep -E '^tap ' "$BREWFILE" | cut -d'"' -f2 | while read -r t; do
    brew trust --tap "$t" >/dev/null 2>&1 || true
  done
fi

TOTAL=$(grep -cE '^(brew|cask|tap|mas) ' "$BREWFILE")
step "Installing $TOTAL packages"

# Brew stderr goes to a log so failures are diagnosable. Only the rolling counter shows.
BREW_LOG=$(mktemp)
brew bundle --file="$BREWFILE" --no-upgrade 2>"$BREW_LOG" | awk -v total="$TOTAL" -v D="$D" -v R="$R" '
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
  rm -f "$BREW_LOG"
else
  echo "   ${Y}!${R} $MISSING package(s) not installed — brew errors:"
  grep -iE 'error|fail' "$BREW_LOG" | head -15 | sed 's/^/     /'
  echo "   ${D}full log: $BREW_LOG${R}"
fi

# -----------------------------------------------------------------------------
BUN_PKGS=("@aws-amplify/cli" clawdhub eas-cli opencode-ai)
step "Installing ${#BUN_PKGS[@]} bun global packages"
if ! command -v bun >/dev/null 2>&1; then
  echo "   ${Y}!${R} bun not found (brew bundle failed above?) — skipping"
elif bun install -g "${BUN_PKGS[@]}" >/dev/null 2>&1; then
  echo "   ${G}✓${R} all ${#BUN_PKGS[@]} packages installed"
else
  echo "   ${Y}!${R} bun global install failed — run manually: bun install -g ${BUN_PKGS[*]}"
fi
fi  # DO_APPS

# -----------------------------------------------------------------------------
step "Cleaning .DS_Store"
DEL=$(find "$REPO_DIR" -name .DS_Store -print -delete 2>/dev/null | wc -l | tr -d ' ')
echo "   ${G}✓${R} removed $DEL file(s)"

# -----------------------------------------------------------------------------
if [ ${#PKGS[@]} -gt 0 ]; then
step "Stowing ${#PKGS[@]} packages"
if ! command -v stow >/dev/null 2>&1; then
  echo "   ${Y}!${R} stow not found — fix the brew failures above, then re-run ./install.sh"
  exit 1
fi
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
echo "   ${G}✓${R} all ${#PKGS[@]} package(s) stowed"
fi  # PKGS

# -----------------------------------------------------------------------------
ELAPSED=$((SECONDS - START))
echo
echo "${B}${G}✓ Done${R} in $((ELAPSED / 60))m$((ELAPSED % 60))s"

[ "$DO_APPS" -eq 1 ] || exit 0
echo
cat <<EOF
${B}Next:${R}
  1. Launch Kaku once (regenerates shell integration)
  2. Raycast → "Import Preferences & Data" → $REPO_DIR/raycast/raycast.rayconfig
  3. After App Store sign-in, re-run: brew bundle --file=$REPO_DIR/Brewfile
EOF
