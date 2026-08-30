
if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi

typeset -U path PATH
path=("$HOME/.local/bin" $path)
