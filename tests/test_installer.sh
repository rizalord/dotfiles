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
test -L "$CONFIG_HOME/starship.toml"
test "$(readlink "$CONFIG_HOME/starship.toml")" = "$ROOT_DIR/starship/starship.toml"
test -L "$CONFIG_HOME/ghostty/config"
test "$(readlink "$CONFIG_HOME/ghostty/config")" = "$ROOT_DIR/ghostty/config"
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

# A relative symlink must remain recoverable after it is moved into the
# timestamped backup directory. The backup target must be made absolute so it
# does not become relative to the new backup location.
SYMLINK_HOME="$TMP_HOME/symlink-home"
SYMLINK_CONFIG="$TMP_HOME/symlink-config"
SYMLINK_GLOBAL="$TMP_HOME/symlink-global"
SYMLINK_TARGET="$SYMLINK_HOME/dotfiles/zsh/.zprofile"
mkdir -p "$SYMLINK_HOME/dotfiles/zsh"
SYMLINK_TARGET_PHYSICAL=$(CDPATH= cd -- "$(dirname "$SYMLINK_TARGET")" && \
  printf '%s/%s\n' "$(pwd -P)" "$(basename "$SYMLINK_TARGET")")
printf 'legacy symlink zprofile\n' > "$SYMLINK_TARGET"
ln -s 'dotfiles/zsh/.zprofile' "$SYMLINK_HOME/.zprofile"

run_symlink_installer() {
  HOME="$SYMLINK_HOME" \
  XDG_CONFIG_HOME="$SYMLINK_CONFIG" \
  GIT_CONFIG_GLOBAL="$SYMLINK_GLOBAL" \
  PATH="$FAKE_BIN:$PATH" \
  bash "$ROOT_DIR/install.sh" "$@"
}

run_symlink_installer
SYMLINK_BACKUP=$(find "$SYMLINK_HOME/.local/state/dotfiles-backups" -type l -name '.zprofile' -print -quit)
test -n "$SYMLINK_BACKUP"
test -L "$SYMLINK_BACKUP"
SYMLINK_BACKUP_TARGET=$(readlink "$SYMLINK_BACKUP")
case "$SYMLINK_BACKUP_TARGET" in
  /*) ;;
  *)
    echo "relative symlink backup target: $SYMLINK_BACKUP_TARGET" >&2
    exit 1
    ;;
esac
test "$SYMLINK_BACKUP_TARGET" = "$SYMLINK_TARGET_PHYSICAL"
test "$(<"$SYMLINK_BACKUP")" = 'legacy symlink zprofile'

# Even when the relative symlink target is already missing, preserve its
# original absolute location instead of making it relative to the backup
# directory.
DANGLING_HOME="$TMP_HOME/dangling-home"
DANGLING_CONFIG="$TMP_HOME/dangling-config"
DANGLING_GLOBAL="$TMP_HOME/dangling-global"
DANGLING_TARGET='missing-parent/dotfiles/.zprofile'
mkdir -p "$DANGLING_HOME"
ln -s "$DANGLING_TARGET" "$DANGLING_HOME/.zprofile"

run_dangling_installer() {
  HOME="$DANGLING_HOME" \
  XDG_CONFIG_HOME="$DANGLING_CONFIG" \
  GIT_CONFIG_GLOBAL="$DANGLING_GLOBAL" \
  PATH="$FAKE_BIN:$PATH" \
  bash "$ROOT_DIR/install.sh" "$@"
}

run_dangling_installer
DANGLING_BACKUP=$(find "$DANGLING_HOME/.local/state/dotfiles-backups" -type l -name '.zprofile' -print -quit)
test -n "$DANGLING_BACKUP"
DANGLING_HOME_PHYSICAL=$(CDPATH= cd -- "$DANGLING_HOME" && pwd -P)
test "$(readlink "$DANGLING_BACKUP")" = "$DANGLING_HOME_PHYSICAL/$DANGLING_TARGET"
test ! -e "$DANGLING_BACKUP"

echo "installer: PASS"
