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

# Stow one package at a time, so a conflict in one does not skip the rest, and
# report exactly what was left alone. Two flags matter here:
#   --no-folding  link files, never whole directories. Without it stow points a
#                 missing target dir straight at the repo, and everything the app
#                 writes later (herdr's logs and sockets, Ghostty's auto/ state)
#                 lands inside git.
#   no --adopt    on a conflict stow leaves the machine's file untouched. --adopt
#                 would pull that file into the repo and overwrite the committed
#                 version, which is the one way this script could lose a config.
# Claude reads skills from ~/.claude/skills, the other agents from ~/.agents/skills.
# One symlink for the whole directory would make that path belong to this repo:
# a machine with its own skills there loses the entire claude package to a stow
# conflict, and any skill installed later gets written into the repo. Mirroring
# one link per skill keeps ~/.claude/skills a real directory, so ours and theirs
# sit side by side. Generated, never committed.
mirror_skills() {
  local src="$REPO_DIR/agents/.agents/skills" dst="$REPO_DIR/claude/.claude/skills" n
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  # Drop stale links first, so a removed skill does not linger as a dead link.
  find "$dst" -maxdepth 1 -type l -delete 2>/dev/null
  for d in "$src"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    ln -sfn "../../../agents/.agents/skills/$n" "$dst/$n"
  done
}

stow_pkgs() {
  local pkgs=("$@") err conflicts pkg i linked=0 skipped=0
  err=$(mktemp); conflicts=$(mktemp)

  for i in "${!pkgs[@]}"; do
    pkg="${pkgs[$i]}"
    printf "\r\033[K   ${D}[%d/%d]${R} %s" "$((i + 1))" "${#pkgs[@]}" "$pkg"
    if stow --target="$HOME" --restow --no-folding "$pkg" 2>"$err"; then
      linked=$((linked + 1))
      continue
    fi
    skipped=$((skipped + 1))
    if grep -q 'existing target' "$err"; then
      grep 'existing target' "$err" \
        | sed -e 's/.*existing target //' -e 's/ since .*//' -e "s|^|$pkg\t|" >>"$conflicts"
    else
      # Not a conflict: permissions, a missing package dir, a stow bug.
      grep -v '^$' "$err" | head -2 | sed "s|^|$pkg\t|" >>"$conflicts"
    fi
  done
  printf "\r\033[K"

  [ "$linked" -gt 0 ] && echo "   ${G}✓${R} $linked package(s) linked"
  if [ "$skipped" -gt 0 ]; then
    echo "   ${Y}!${R} $skipped package(s) skipped — these already exist here and were left as they are:"
    while IFS=$'\t' read -r p t; do
      printf "       ${D}%-9s${R} ~/%s\n" "$p" "$t"
    done <"$conflicts"
    echo "   ${D}to take them over: move or delete those files, then run" \
         "./install.sh $(cut -f1 "$conflicts" | sort -u | tr '\n' ' ' | sed 's/ $//')${R}"
  fi

  rm -f "$err" "$conflicts"
  [ "$skipped" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Usage:
#   ./install.sh                 full install (apps + all configs)
#   ./install.sh apps            Homebrew/Brewfile + bun packages only
#   ./install.sh nvim yazi ...   stow only the named config packages
#   ./install.sh check           verify every link resolves; changes nothing
#   ./install.sh update          refresh brew, skills and the prose style guide
ALL_PKGS=(zsh git aerospace lazygit yazi nvim starship ghostty hammerspoon herdr claude codex agents)
DO_APPS=1
PKGS=("${ALL_PKGS[@]}")

# --- check: read-only health check -------------------------------------------
if [ "${1:-}" = "check" ]; then
  step "Checking"
  FAIL=0

  # Every package in ALL_PKGS must exist, and every dir must be a package.
  for p in "${ALL_PKGS[@]}"; do
    [ -d "$REPO_DIR/$p" ] || { echo "   ${Y}!${R} $p listed in ALL_PKGS but no such directory"; FAIL=1; }
  done
  for d in "$REPO_DIR"/*/; do
    n=$(basename "$d")
    [ "$n" = "raycast" ] || [ "$n" = "scripts" ] && continue
    case " ${ALL_PKGS[*]} " in
      *" $n "*) ;;
      *) echo "   ${Y}!${R} $n/ exists but is not in ALL_PKGS — it will never be stowed"; FAIL=1 ;;
    esac
  done

  # Dangling symlinks anywhere in the repo, and in the paths we own at $HOME.
  while IFS= read -r l; do
    echo "   ${Y}!${R} broken link in repo: ${l#$REPO_DIR/}"; FAIL=1
  done < <(find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -type l ! -exec test -e {} \; -print 2>/dev/null)

  for l in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.claude/CLAUDE.md" \
           "$HOME/.codex/AGENTS.md" "$HOME/.config/herdr/config.toml" \
           "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
    [ -e "$l" ] || { echo "   ${Y}!${R} not resolving: ${l#$HOME/}"; FAIL=1; }
  done

  # A stowed path that is no longer a symlink means an app replaced the link
  # with its own file: the repo copy silently stopped applying on this machine.
  for p in "${ALL_PKGS[@]}"; do
    while IFS= read -r f; do
      rel="${f#$p/}"; tgt="$HOME/$rel"
      [ -e "$tgt" ] || [ -L "$tgt" ] || continue          # not installed yet, not a divergence
      if [ ! -L "$tgt" ]; then
        echo "   ${Y}!${R} no longer linked: ~/$rel — an app replaced it, repo copy is not in use"; FAIL=1
      fi
    done < <(cd "$REPO_DIR/$p" 2>/dev/null && find . -type f -o -type l | sed 's|^\./||' | sed "s|^|$p/|")
  done

  # A stowed directory that is itself a symlink is folded: the whole directory
  # belongs to the repo, so anything the app writes there lands in git.
  for p in "${ALL_PKGS[@]}"; do
    while IFS= read -r d; do
      [ -L "$HOME/$d" ] || continue
      echo "   ${Y}!${R} folded into the repo: ~/$d — restow with: ./install.sh $p"; FAIL=1
    done < <(cd "$REPO_DIR/$p" 2>/dev/null && find . -type d ! -name . | sed 's|^\./||')
  done

  # Every skill must actually carry a SKILL.md, or the agent silently ignores it.
  for s in "$REPO_DIR"/agents/.agents/skills/*/; do
    [ -f "$s/SKILL.md" ] || { echo "   ${Y}!${R} $(basename "$s") has no SKILL.md"; FAIL=1; }
  done

  # Skills declared but never installed.
  while IFS= read -r name; do
    [ -d "$REPO_DIR/agents/.agents/skills/$name" ] || {
      echo "   ${Y}!${R} $name is in skills.json but not installed — run: ./install.sh update"; FAIL=1; }
  done < <(python3 -c 'import json;[print(s["name"]) for s in json.load(open("'"$REPO_DIR"'/skills.json"))["skills"]]' 2>/dev/null)

  [ "$FAIL" -eq 0 ] && echo "   ${G}✓${R} all packages, links and skills check out"
  exit "$FAIL"
fi

# --- update: refresh everything that comes from upstream ----------------------
if [ "${1:-}" = "update" ]; then
  step "Updating Homebrew packages"
  brew update >/dev/null 2>&1 && brew bundle --file="$REPO_DIR/Brewfile" >/dev/null 2>&1 \
    && echo "   ${G}✓${R} Brewfile applied" || echo "   ${Y}!${R} brew update had errors"

  step "Updating skills"
  "$REPO_DIR/scripts/skills-sync.sh"

  # Single '>' — the upstream install line uses '>>', which appends a second
  # copy of the whole style guide every time it is run.
  step "Updating prose style guide"
  # Explicit https and --proto '=https': this response is written straight into
  # CLAUDE.md, which every agent loads as instructions. A bare host would make
  # the first hop plaintext HTTP and let the redirect decide the scheme.
  if curl -fsSL --proto '=https' --max-time 20 \
       https://prose.ami.rip/STYLE.md -o "$REPO_DIR/claude/.claude/CLAUDE.md.new"; then
    if cmp -s "$REPO_DIR/claude/.claude/CLAUDE.md.new" "$REPO_DIR/claude/.claude/CLAUDE.md"; then
      rm -f "$REPO_DIR/claude/.claude/CLAUDE.md.new"
      echo "   ${G}✓${R} already current"
    else
      mv "$REPO_DIR/claude/.claude/CLAUDE.md.new" "$REPO_DIR/claude/.claude/CLAUDE.md"
      echo "   ${G}✓${R} updated — review with: git diff claude/.claude/CLAUDE.md"
    fi
  else
    rm -f "$REPO_DIR/claude/.claude/CLAUDE.md.new"
    echo "   ${Y}!${R} could not reach prose.ami.rip — left unchanged"
  fi

  step "Restowing ${#ALL_PKGS[@]} package(s)"
  mirror_skills
  stow_pkgs "${ALL_PKGS[@]}"

  echo
  echo "${B}${G}✓ Updated${R} — run ./install.sh check to verify"
  exit 0
fi

if [ $# -gt 0 ]; then
  if [ "$1" = "apps" ]; then
    PKGS=()
  else
    DO_APPS=0
    PKGS=()
    for a in "$@"; do
      case " ${ALL_PKGS[*]} " in
        *" $a "*) PKGS+=("$a") ;;
        *) echo "unknown package: $a"
           echo "available: ${ALL_PKGS[*]}"
           echo "or: apps, check, update"; exit 1 ;;
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
BUN_PKGS=("@aws-amplify/cli" clawdhub eas-cli)
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
# Skills are declared in skills.json and installed from upstream, not committed.
# A fresh clone has no agents/.agents/skills/* until this runs.
if [ "$DO_APPS" -eq 1 ]; then
step "Installing agent skills"
"$REPO_DIR/scripts/skills-sync.sh"
fi

# -----------------------------------------------------------------------------
step "Cleaning .DS_Store"
DEL=$(find "$REPO_DIR" -name .DS_Store -print -delete 2>/dev/null | wc -l | tr -d ' ')
echo "   ${G}✓${R} removed $DEL file(s)"

# -----------------------------------------------------------------------------
if [ ${#PKGS[@]} -gt 0 ]; then
step "Stowing ${#PKGS[@]} package(s)"
if ! command -v stow >/dev/null 2>&1; then
  echo "   ${Y}!${R} stow not found — fix the brew failures above, then re-run ./install.sh"
  exit 1
fi
mirror_skills
stow_pkgs "${PKGS[@]}" || STOW_SKIPPED=1
fi  # PKGS

# -----------------------------------------------------------------------------
ELAPSED=$((SECONDS - START))
echo
if [ "${STOW_SKIPPED:-0}" -eq 1 ]; then
  echo "${B}${Y}✓ Done${R} in $((ELAPSED / 60))m$((ELAPSED % 60))s — some packages skipped, see above"
else
  echo "${B}${G}✓ Done${R} in $((ELAPSED / 60))m$((ELAPSED % 60))s"
fi

[ "$DO_APPS" -eq 1 ] || exit 0
echo
cat <<EOF
${B}Next:${R}
  1. Raycast → "Import Preferences & Data" → $REPO_DIR/raycast/raycast.rayconfig
  2. After App Store sign-in, re-run: brew bundle --file=$REPO_DIR/Brewfile
EOF
