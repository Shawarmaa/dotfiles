
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
# nvm's bash_completion is sourced after compinit below (it needs compdef)

export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"

export PATH="$HOME/.bun/bin:$PATH"

# Android SDK platform-tools
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"

# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$HOME/.local/bin:$PATH"

# ===== Prompt and plugins (was Kaku's shell integration) =====
fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
autoload -Uz compinit bashcompinit && compinit -C && bashcompinit
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh)"

# fast-syntax-highlighting (what Kaku used) — repaints less, no flicker
source /opt/homebrew/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

ZSH_AUTOSUGGEST_MANUAL_REBIND=1
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=1
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# ===== History =====
HISTSIZE=50000
SAVEHIST=50000
HISTFILE="$HOME/.zsh_history"
setopt HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS HIST_REDUCE_BLANKS HIST_IGNORE_SPACE
setopt SHARE_HISTORY APPEND_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY

# prefix search on Up/Down: type "curl" then Up walks only curl commands
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey -e
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# Ghostty sends Ctrl+V for Cmd+V (so Claude Code can grab clipboard images);
# make Ctrl+V paste real text here instead of zsh's quoted-insert
_paste_clipboard() { LBUFFER+="$(pbpaste)" }
zle -N _paste_clipboard
bindkey '^V' _paste_clipboard

# ===== Shell options =====
setopt interactive_comments auto_cd auto_pushd pushd_ignore_dups pushdminus
export CLICOLOR=1
export LSCOLORS="gxfxcxdxbxegedabagacad"

# yazi launcher that cds to wherever you quit
y() {
    emulate -L zsh
    setopt local_options no_sh_word_split
    local tmp cwd
    tmp="$(mktemp -t 'yazi-cwd.XXXXXX')"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

#Claude alias
alias cc="CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000 claude --dangerously-skip-permissions"
#Codex alias
alias cx="codex --full-auto"
alias gm="gemini --yolo"

# Machine-specific config (work laptop etc.) — keep in ~/.zshrc.local, not tracked
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
