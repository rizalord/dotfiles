[[ -o interactive ]] || return

HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
mkdir -p "${HISTFILE:h}" 2>/dev/null
setopt append_history share_history hist_ignore_dups hist_ignore_space

autoload -Uz compinit
compinit
bindkey -e

: "${EDITOR:=vim}"
: "${VISUAL:=$EDITOR}"
export EDITOR VISUAL

alias gs='git status'
alias gd='git diff'
alias gco='git checkout'
alias gsw='git switch'
alias glog='git log --oneline --graph --decorate'

if (( $+commands[fzf] )); then
  source <(fzf --zsh) 2>/dev/null || true
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

local_zsh="$XDG_CONFIG_HOME/zsh/local.zsh"
[[ -n "$XDG_CONFIG_HOME" ]] || local_zsh="$HOME/.config/zsh/local.zsh"
[[ -r "$local_zsh" ]] && source "$local_zsh"
unset local_zsh
