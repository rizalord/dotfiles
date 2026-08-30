#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
assert_contains() { grep -Fq -- "$2" "$1" || exit 1; }

zsh -n "$ROOT_DIR/zsh/.zprofile"
zsh -n "$ROOT_DIR/zsh/.zshrc"
assert_contains "$ROOT_DIR/zsh/.zprofile" "brew shellenv"
assert_contains "$ROOT_DIR/zsh/.zprofile" '$HOME/.local/bin'
assert_contains "$ROOT_DIR/zsh/.zshrc" '[[ -o interactive ]] || return'
assert_contains "$ROOT_DIR/zsh/.zshrc" 'bindkey -e'
assert_contains "$ROOT_DIR/zsh/.zshrc" 'mise activate zsh'
assert_contains "$ROOT_DIR/zsh/.zshrc" 'local.zsh'

TMP_HOME=$(mktemp -d)
trap 'rm -rf -- "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.config/zsh"
printf 'export DOTFILES_TEST_MARKER=loaded\n' > "$TMP_HOME/.config/zsh/local.zsh"

OUTPUT=$(HOME="$TMP_HOME" \
  XDG_CONFIG_HOME="$TMP_HOME/.config" \
  XDG_STATE_HOME="$TMP_HOME/.state" \
  ZDOTDIR="$TMP_HOME" \
  DOTFILES_RC="$ROOT_DIR/zsh/.zshrc" \
  zsh -flic 'bindkey -v; source "$DOTFILES_RC"; print -r -- "$DOTFILES_TEST_MARKER"; alias gs; bindkey -lL main' 2>&1)

grep -Fq loaded <<<"$OUTPUT"
grep -Fq "git status" <<<"$OUTPUT"
grep -Fq 'bindkey -A emacs main' <<<"$OUTPUT"
test -d "$TMP_HOME/.state/zsh"
echo "zsh configuration: PASS"
