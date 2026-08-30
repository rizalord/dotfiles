#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_HOME=$(mktemp -d)
trap 'rm -rf -- "$TMP_HOME"' EXIT

run_installer() {
  HOME="$TMP_HOME" \
  XDG_CONFIG_HOME="$TMP_HOME/.config" \
  GIT_CONFIG_GLOBAL="$TMP_HOME/.gitconfig" \
  bash "$ROOT_DIR/install.sh" "$@"
}

run_installer --dry-run
test ! -e "$TMP_HOME/.zshrc"
test ! -e "$TMP_HOME/.config/git/dotfiles.gitconfig"

mkdir -p "$TMP_HOME"
printf 'legacy zsh\n' > "$TMP_HOME/.zshrc"
run_installer

test -L "$TMP_HOME/.zshrc"
test "$(readlink "$TMP_HOME/.zshrc")" = "$ROOT_DIR/zsh/.zshrc"
test -L "$TMP_HOME/.zprofile"
test -L "$TMP_HOME/.config/git/dotfiles.gitconfig"
test -L "$TMP_HOME/.config/git/ignore"
test "$(HOME="$TMP_HOME" GIT_CONFIG_GLOBAL="$TMP_HOME/.gitconfig" git --no-pager config --global --get-all include.path)" = "~/.config/git/dotfiles.gitconfig"
find "$TMP_HOME/.local/state/dotfiles-backups" -type f -name ".zshrc" -print -quit | grep -Fq .

BACKUPS_BEFORE=$(find "$TMP_HOME/.local/state/dotfiles-backups" -type f | wc -l | tr -d " ")
run_installer
BACKUPS_AFTER=$(find "$TMP_HOME/.local/state/dotfiles-backups" -type f | wc -l | tr -d " ")
test "$BACKUPS_BEFORE" = "$BACKUPS_AFTER"

echo "installer: PASS"
