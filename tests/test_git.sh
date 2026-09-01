#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG="${GIT_CONFIG_FILE:-$ROOT_DIR/git/.gitconfig}"

assert_no_matching_keys() {
  local pattern="$1"
  local description="$2"
  local matches
  local status

  if matches=$(git config --file "$CONFIG" --name-only --get-regexp "$pattern" 2>/dev/null); then
    printf 'shared config must not contain %s: %s\n' "$description" "$matches" >&2
    return 1
  else
    status=$?
    test "$status" -eq 1
  fi
}

test -f "$CONFIG"
test "$(git config --file "$CONFIG" --get init.defaultBranch)" = main
test "$(git config --file "$CONFIG" --get pull.rebase)" = true
test "$(git config --file "$CONFIG" --get fetch.prune)" = true
test "$(git config --file "$CONFIG" --get push.autoSetupRemote)" = true
test "$(git config --file "$CONFIG" --get rerere.enabled)" = true
test "$(git config --file "$CONFIG" --get core.excludesFile)" = "~/.config/git/ignore"
test "$(git config --file "$CONFIG" --get core.pager)" = delta
test "$(git config --file "$CONFIG" --get interactive.diffFilter)" = "delta --color-only"
test "$(git config --file "$CONFIG" --get delta.navigate)" = true

EXPECTED_ALIASES=$(
  printf '%s\n' \
    'alias.amend commit --amend --no-edit' \
    'alias.ci commit' \
    'alias.co switch' \
    'alias.last log -1 HEAD --stat' \
    'alias.lg log --oneline --decorate --graph' \
    'alias.st status --short --branch' \
    'alias.unstage restore --staged' |
    LC_ALL=C sort
)
ACTUAL_ALIASES=$(git config --file "$CONFIG" --get-regexp "^alias\." | LC_ALL=C sort)
test "$ACTUAL_ALIASES" = "$EXPECTED_ALIASES"

assert_no_matching_keys '^user\.' 'user identity'
assert_no_matching_keys '^commit\.gpgsign$' 'commit.gpgSign'
assert_no_matching_keys '^user\.signingkey$' 'user.signingKey'
assert_no_matching_keys '(^|\.)(gpgsign|signingkey)(\.|$)|^gpg\.' 'signing configuration'
assert_no_matching_keys '^credential\.' 'credential.* fields'
assert_no_matching_keys 'token' 'token fields'
assert_no_matching_keys '^include(if)?\.' 'include.* directives'

echo "git configuration: PASS"
