# dotfiles

Dev environment for macOS: GNU Stow for configs, a Brewfile for apps, and
`skills.json` for agent skills.

```bash
git clone https://github.com/Shawarmaa/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

Then import `~/dotfiles/raycast/raycast.rayconfig` via Raycast's
**Import Preferences & Data**.

## Commands

| | |
|---|---|
| `./install.sh` | Everything: apps, skills, stow |
| `./install.sh apps` | Homebrew + bun packages only |
| `./install.sh nvim yazi` | Stow only the named packages |
| `./install.sh check` | Verify links, packages and skills resolve — changes nothing |
| `./install.sh update` | Pull latest brew packages, skills and style guide, then restow |

Run `check` after anything that rewrites files in here; it's what catches a
symlink that silently stopped resolving.

## What's tracked, and what isn't

Each top-level directory is a stow package mirroring its path under `$HOME`, so
`git/.gitconfig` becomes `~/.gitconfig`. Three things deliberately aren't files
in this repo:

- **Agent skills.** `skills.json` declares them; `scripts/skills-sync.sh` installs
  them into `agents/.agents/skills/`, which is gitignored. The manifest is the
  source of truth, the same way the Brewfile is for apps. Hand-written skills —
  currently just `summarize` — are excluded from the manifest and stay tracked.
- **Machine-local overrides.** `~/.zshrc.local` and `~/.gitconfig.local` are
  sourced if present and never tracked, which is where work identities go.
- **Raycast settings.** `raycast.rayconfig` is a binary export, so it's a
  snapshot you re-export by hand, not a live config.

## Agent setup

One skills directory feeds every agent. `agents/.agents/skills/` is the source:
Codex reads it natively at `~/.agents/skills`, and Claude Code reaches the same
directory through a single link at `~/.claude/skills`. There are no per-skill
symlinks to keep in sync.

The prose style guide from [prose.ami.rip](https://prose.ami.rip) lives once at
`claude/.claude/CLAUDE.md`, with `codex/.codex/AGENTS.md` symlinked to it so both
agents read identical instructions. Update it with `./install.sh update` — note
the upstream one-liner uses `>>`, which appends a second copy of the whole guide
each time you run it.
