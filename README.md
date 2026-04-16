# dotfiles

Dev environment, managed with GNU Stow + a Homebrew Brewfile.

## New Mac

```bash
xcode-select --install
git clone https://github.com/<Shawarmaa>/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

Then:

1. Launch Kaku once (it regenerates its shell integration under `~/.config/kaku/zsh/`).
2. Open Raycast and run **Import Preferences & Data**, selecting `~/dotfiles/raycast/raycast.rayconfig`.
3. Sign in to the Mac App Store, then re-run `brew bundle --file=~/dotfiles/Brewfile` so `mas` can install Xcode.
