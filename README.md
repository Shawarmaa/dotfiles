# dotfiles

My Mac dev environment, managed with GNU Stow + a Homebrew Brewfile.

## Bootstrap a new Mac

```bash
xcode-select --install
git clone https://github.com/<your-user>/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

Then:

1. Launch Kaku once (it regenerates its shell integration under `~/.config/kaku/zsh/`).
2. Open Raycast and run **Import Preferences & Data**, selecting `~/dotfiles/raycast/raycast.rayconfig`.
3. Sign in to the Mac App Store, then re-run `brew bundle --file=~/dotfiles/Brewfile` so `mas` can install Xcode.

## What's inside

| Directory | What it holds |
|---|---|
| `zsh/` | `.zshrc` |
| `git/` | `.gitconfig` |
| `aerospace/` | `.aerospace.toml` — Aerospace window manager |
| `lazygit/` | `~/.config/lazygit/config.yml` |
| `yazi/` | `~/.config/yazi/` (config, keymap, theme, flavors) |
| `kaku/` | `~/.config/kaku/kaku.lua` — Kaku terminal visual tweaks |
| `nvim/` | `~/.config/nvim/` (forked from kickstart-nvim) |
| `raycast/` | Exported `raycast.rayconfig` — import via Raycast UI |
| `Brewfile` | CLI tools, GUI apps, and App Store items |
| `install.sh` | One-command bootstrap |

## How Stow works here

Each top-level directory (e.g. `zsh/`, `nvim/`) is a "stow package". Its inner layout mirrors `$HOME`. Running `stow zsh` from `~/dotfiles/` creates symlinks like `~/.zshrc -> ~/dotfiles/zsh/.zshrc`. `install.sh` stows every package.

## License

Do whatever you want with this.
