
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"

export PATH="/Users/muhammadabdullah/.bun/bin:$PATH"

# Android SDK platform-tools
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"

# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$HOME/.local/bin:$PATH"

[[ ":$PATH:" != *":$HOME/.config/kaku/zsh/bin:"* ]] && export PATH="$HOME/.config/kaku/zsh/bin:$PATH" # Kaku PATH Integration
[[ -f "$HOME/.config/kaku/zsh/kaku.zsh" ]] && source "$HOME/.config/kaku/zsh/kaku.zsh" # Kaku Shell Integration

#Claude alias
alias cc="CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000 claude --dangerously-skip-permissions"
#Codex alias
alias cx="codex --full-auto"
