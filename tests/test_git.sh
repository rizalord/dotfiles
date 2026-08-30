#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG="$ROOT_DIR/git/.gitconfig"

test -f "$CONFIG"
test "$(git config --file "$CONFIG" --get init.defaultBranch)" = main
test "$(git config --file "$CONFIG" --get pull.rebase)" = true
test "$(git config --file "$CONFIG" --get fetch.prune)" = true
test "$(git config --file "$CONFIG" --get push.autoSetupRemote)" = true
test "$(git config --file "$CONFIG" --get rerere.enabled)" = true
test "$(git config --file "$CONFIG" --get core.excludesFile)" = "~/.config/git/ignore"
git config --file "$CONFIG" --get-regexp "^alias\." | grep -Fq "alias.st "
git config --file "$CONFIG" --get-regexp "^alias\." | grep -Fq "alias.lg "
if git config --file "$CONFIG" --get-regexp "^user\." >/dev/null 2>&1; then
  echo "shared config must not contain user identity" >&2
  exit 1
fi

echo "git configuration: PASS"
