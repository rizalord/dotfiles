#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_HOME=$(mktemp -d)
trap 'rm -rf -- "$TMP_HOME"' EXIT
CONFIG_HOME="$TMP_HOME/custom-config"
FAKE_BIN="$TMP_HOME/fake-bin"
GIT_GLOBAL="$TMP_HOME/.gitconfig"

mkdir -p "$FAKE_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'printf "20260830-120000\\n"' > "$FAKE_BIN/date"
chmod +x "$FAKE_BIN/date"

run_installer() {
  HOME="$TMP_HOME" \
  XDG_CONFIG_HOME="$CONFIG_HOME" \
  GIT_CONFIG_GLOBAL="$GIT_GLOBAL" \
  PATH="$FAKE_BIN:$PATH" \
  bash "$ROOT_DIR/install.sh" "$@"
}

git_global() {
  HOME="$TMP_HOME" \
  XDG_CONFIG_HOME="$CONFIG_HOME" \
  GIT_CONFIG_GLOBAL="$GIT_GLOBAL" \
  git --no-pager config --global "$@"
}

git_effective() {
  HOME="$TMP_HOME" \
  XDG_CONFIG_HOME="$CONFIG_HOME" \
  GIT_CONFIG_GLOBAL="$GIT_GLOBAL" \
  git --no-pager config --includes --global "$@"
}

mkdir -p "$TMP_HOME"
printf '[user]\n\tname = Existing User\n\temail = existing@example.test\n' > "$GIT_GLOBAL"
printf 'legacy zsh\n' > "$TMP_HOME/.zshrc"

run_installer --dry-run
test -f "$TMP_HOME/.zshrc"
test "$(<"$TMP_HOME/.zshrc")" = 'legacy zsh'
test ! -e "$CONFIG_HOME/git/dotfiles.gitconfig"
test ! -e "$TMP_HOME/.local/state/dotfiles-backups"
test "$(<"$GIT_GLOBAL")" = $'[user]\n\tname = Existing User\n\temail = existing@example.test'
if git_global --get-all include.path >/dev/null 2>&1; then
  echo 'dry-run unexpectedly added a Git include' >&2
  exit 1
fi

if output=$(run_installer --unexpected 2>&1); then
  echo 'invalid argument unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq 'Usage: install.sh [--dry-run]' <<<"$output"

run_installer

test -L "$TMP_HOME/.zshrc"
test "$(readlink "$TMP_HOME/.zshrc")" = "$ROOT_DIR/zsh/.zshrc"
test -L "$TMP_HOME/.zprofile"
test -L "$CONFIG_HOME/git/dotfiles.gitconfig"
test -L "$CONFIG_HOME/git/ignore"
EXPECTED_GIT_INCLUDE="$CONFIG_HOME/git/dotfiles.gitconfig"
test "$(git_global --get-all include.path)" = "$EXPECTED_GIT_INCLUDE"
test "$(git_effective --get init.defaultBranch)" = main
test "$(git_effective --get pull.rebase)" = true
test "$(git_global --get user.name)" = 'Existing User'
test "$(git_global --get user.email)" = 'existing@example.test'
test "$(git_global --get-all include.path | grep -Fxc -- "$EXPECTED_GIT_INCLUDE")" = 1

BACKUP_ROOT="$TMP_HOME/.local/state/dotfiles-backups"
BACKUP_COUNT=$(find "$BACKUP_ROOT" -type f -name ".zshrc" | wc -l | tr -d " ")
test "$BACKUP_COUNT" = 1

rm "$TMP_HOME/.zshrc"
printf 'second legacy zsh\n' > "$TMP_HOME/.zshrc"
run_installer

BACKUP_COUNT=$(find "$BACKUP_ROOT" -type f -name ".zshrc" | wc -l | tr -d " ")
test "$BACKUP_COUNT" = 2
LEGACY_BACKUPS=0
SECOND_LEGACY_BACKUPS=0
while IFS= read -r backup_file; do
  case "$(<"$backup_file")" in
    'legacy zsh') LEGACY_BACKUPS=$((LEGACY_BACKUPS + 1)) ;;
    'second legacy zsh') SECOND_LEGACY_BACKUPS=$((SECOND_LEGACY_BACKUPS + 1)) ;;
  esac
done < <(find "$BACKUP_ROOT" -type f -name ".zshrc" -print)
test "$LEGACY_BACKUPS" = 1
test "$SECOND_LEGACY_BACKUPS" = 1
test "$(git_global --get-all include.path | grep -Fxc -- "$EXPECTED_GIT_INCLUDE")" = 1

BACKUPS_BEFORE=$(find "$BACKUP_ROOT" -type f | wc -l | tr -d " ")
run_installer
BACKUPS_AFTER=$(find "$BACKUP_ROOT" -type f | wc -l | tr -d " ")
test "$BACKUPS_BEFORE" = "$BACKUPS_AFTER"
test "$(git_effective --get init.defaultBranch)" = main

echo "installer: PASS"
