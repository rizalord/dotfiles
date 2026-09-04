[[ -o interactive ]] || return

HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
mkdir -p "${HISTFILE:h}" 2>/dev/null
setopt append_history share_history hist_ignore_dups hist_ignore_space
setopt extended_history hist_ignore_all_dups hist_save_no_dups hist_reduce_blanks hist_verify

setopt auto_cd auto_pushd pushd_ignore_dups pushd_silent
setopt interactive_comments complete_in_word always_to_end no_beep

# Completion. Run the full security check at most once every 24h; otherwise
# load the cached dump with -C so new shells start fast.
autoload -Uz compinit
zmodload zsh/complist
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${_zcompdump:h}" 2>/dev/null
if [[ -n ${_zcompdump}(#qNmh-24) ]]; then
  compinit -C -d "$_zcompdump"
else
  compinit -d "$_zcompdump"
fi
unset _zcompdump

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Emacs keybindings, kept explicit so a vi-mode parent shell cannot leak in.
bindkey -e
bindkey '^[[1;3C' forward-word
bindkey '^[[1;3D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[3~'   delete-char
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

: "${EDITOR:=vim}"
: "${VISUAL:=$EDITOR}"
export EDITOR VISUAL

alias gs='git status'
alias gd='git diff'
alias gco='git checkout'
alias gsw='git switch'
alias glog='git log --oneline --graph --decorate'

if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -lh --group-directories-first --icons=auto --git'
  alias la='eza -lah --group-directories-first --icons=auto --git'
  alias lt='eza --tree --level=2 --icons=auto'
fi

if (( $+commands[bat] )); then
  export MANPAGER="sh -c 'col -bx | bat --language man --style plain'"
  export MANROFFOPT='-c'
fi

if (( $+commands[fzf] )); then
  source <(fzf --zsh) 2>/dev/null || true
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
  if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi
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

# Greet a new top-level shell with a system summary. Skipped for nested shells,
# non-tty stdout, and when DOTFILES_NO_FASTFETCH is set.
if (( $+commands[fastfetch] )) && [[ -t 1 && $SHLVL -eq 1 && -z $DOTFILES_NO_FASTFETCH ]]; then
  fastfetch
fi

# Interactive plugins, installed via Homebrew (macOS) or apt (Debian) and
# skipped when absent. zsh-history-substring-search isn't packaged for
# Debian, so it also looks in the git-clone location install-apt.sh uses.
_zsh_plugin_dirs=("${HOMEBREW_PREFIX:-/opt/homebrew}/share" /usr/share)
_source_zsh_plugin() {
  local plugin_name="$1" plugin_file="$2" dir
  for dir in "${_zsh_plugin_dirs[@]}" "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-plugins"; do
    if [[ -r "$dir/$plugin_name/$plugin_file" ]]; then
      source "$dir/$plugin_name/$plugin_file"
      return 0
    fi
  done
  return 1
}

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_MANUAL_REBIND=1
_source_zsh_plugin zsh-autosuggestions zsh-autosuggestions.zsh

local_zsh="$XDG_CONFIG_HOME/zsh/local.zsh"
[[ -n "$XDG_CONFIG_HOME" ]] || local_zsh="$HOME/.config/zsh/local.zsh"
[[ -r "$local_zsh" ]] && source "$local_zsh"
unset local_zsh

# zsh-syntax-highlighting must be sourced last; history-substring-search after it.
_source_zsh_plugin zsh-syntax-highlighting zsh-syntax-highlighting.zsh
if _source_zsh_plugin zsh-history-substring-search zsh-history-substring-search.zsh; then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey '^P'   history-substring-search-up
  bindkey '^N'   history-substring-search-down
fi
unset -f _source_zsh_plugin
unset _zsh_plugin_dirs
