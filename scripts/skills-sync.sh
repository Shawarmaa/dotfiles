#!/usr/bin/env bash
# Install/update agent skills declared in skills.json.
#
#   ./scripts/skills-sync.sh              install or update every skill
#   ./scripts/skills-sync.sh check ui     only those skills
#   DEST=/tmp/x ./scripts/skills-sync.sh  install elsewhere (used to verify)
#
# Each skill is copied from its upstream repo into <dest>/<name>/. Skills not
# listed in skills.json are never touched, so hand-written ones stay put.
set -uo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
MANIFEST="$REPO_DIR/skills.json"

if [ -t 1 ]; then
  D=$(tput dim); R=$(tput sgr0); G=$(tput setaf 2); Y=$(tput setaf 3)
else
  D=""; R=""; G=""; Y=""
fi

[ -f "$MANIFEST" ] || { echo "missing $MANIFEST"; exit 1; }

DEST="${DEST:-$REPO_DIR/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["dest"])' "$MANIFEST")}"
mkdir -p "$DEST"

# name|repo|path|ref|include(comma-separated), filtered to the names passed as
# arguments (if any). Fields are separated by US (\x1f), not tab: bash `read`
# collapses runs of whitespace delimiters, so an empty `ref` would silently
# shift every field after it.
SEP=$'\x1f'
ENTRIES=$(python3 - "$MANIFEST" "$@" <<'PY'
import json, sys
manifest, wanted = sys.argv[1], set(sys.argv[2:])
for s in json.load(open(manifest))["skills"]:
    if wanted and s["name"] not in wanted:
        continue
    print("\x1f".join([s["name"], s["repo"], s.get("path", "."),
                       s.get("ref", ""), ",".join(s.get("include", []))]))
PY
)

if [ -z "$ENTRIES" ]; then
  echo "no matching skills in skills.json"; exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TOTAL=$(printf '%s\n' "$ENTRIES" | wc -l | tr -d ' ')
n=0
FAILED=()

while IFS="$SEP" read -r name repo path ref include; do
  n=$((n + 1))
  printf "\r\033[K   ${D}[%d/%d]${R} %s" "$n" "$TOTAL" "$name"

  # $name is interpolated into an rm -rf target below. Keep it a plain
  # directory name so a stray '..' or '/' in the manifest cannot escape DEST.
  case "$name" in
    *[!A-Za-z0-9_-]*|"") FAILED+=("${name:-<empty>} (invalid skill name)"); continue ;;
  esac

  # One clone per repo — Waza alone provides eight skills.
  clone="$TMP/$(echo "$repo" | sed 's|[^A-Za-z0-9]|_|g')"
  if [ ! -d "$clone" ]; then
    if [ -n "$ref" ]; then
      git clone --quiet "$repo" "$clone" 2>/dev/null && git -C "$clone" checkout --quiet "$ref" 2>/dev/null
    else
      git clone --quiet --depth 1 "$repo" "$clone" 2>/dev/null
    fi
    if [ ! -d "$clone/.git" ]; then
      FAILED+=("$name (clone failed: $repo)"); continue
    fi
  fi

  src="$clone/$path"
  if [ ! -d "$src" ]; then
    FAILED+=("$name (path not found upstream: $path)"); continue
  fi

  # Replace atomically-ish: build beside the target, then swap.
  staged="$TMP/staged-$name"
  rm -rf "$staged"

  if [ -n "$include" ]; then
    # Skills whose SKILL.md lives at the repo root: copy only the paths it
    # actually references, not the entire project.
    mkdir -p "$staged"
    missing=""
    IFS=',' read -ra WANT <<< "$include"
    for item in "${WANT[@]}"; do
      if [ -e "$src/$item" ]; then
        mkdir -p "$staged/$(dirname "$item")"
        cp -R "$src/$item" "$staged/$item"
      else
        missing="$missing $item"
      fi
    done
    if [ -n "$missing" ]; then
      FAILED+=("$name (missing upstream:$missing)"); continue
    fi
  else
    cp -R "$src" "$staged"
  fi

  rm -rf "$staged/.git"

  # Vendored skills match the ignore pattern; hand-written ones are the named
  # exceptions to it. If a manifest entry ever takes the name of a hand-written
  # skill, the rm -rf below would delete work with no upstream to restore from.
  # --no-index because these paths are still tracked from before they were
  # ignored, and check-ignore stays silent about tracked files without it.
  if [ -d "$DEST/$name" ] && ! git -C "$REPO_DIR" check-ignore --no-index -q "$DEST/$name"; then
    FAILED+=("$name (would overwrite a hand-written skill — rename one of them)")
    continue
  fi

  rm -rf "${DEST:?}/$name"
  mv "$staged" "$DEST/$name"
done <<< "$ENTRIES"

printf "\r\033[K"
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "   ${G}✓${R} $TOTAL skill(s) synced to ${DEST/#$HOME/'~'}"
else
  echo "   ${Y}!${R} $((TOTAL - ${#FAILED[@]}))/$TOTAL synced; failed:"
  printf '     %s\n' "${FAILED[@]}"
  exit 1
fi
