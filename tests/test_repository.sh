#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

assert_file() {
  test -f "$1" || { echo "missing file: $1" >&2; exit 1; }
}

assert_contains() {
  grep -Fq -- "$2" "$1" || { echo "missing text '$2' in $1" >&2; exit 1; }
}

assert_ignored() {
  git -C "$ROOT_DIR" check-ignore -q -- "$1" || {
    echo "path is not ignored: $1" >&2
    exit 1
  }
}

assert_not_ignored() {
  if git -C "$ROOT_DIR" check-ignore -q -- "$1"; then
    echo "path is unexpectedly ignored: $1" >&2
    exit 1
  fi
}

assert_file "$ROOT_DIR/.gitignore"
assert_file "$ROOT_DIR/Brewfile"
assert_file "$ROOT_DIR/git/.gitignore_global"
assert_contains "$ROOT_DIR/.gitignore" ".env"
assert_contains "$ROOT_DIR/.gitignore" "*.pem"
assert_contains "$ROOT_DIR/.gitignore" ".codex/"
assert_contains "$ROOT_DIR/.gitignore" ".claude/"
assert_contains "$ROOT_DIR/Brewfile" 'brew "gh"'
assert_contains "$ROOT_DIR/Brewfile" 'brew "glab"'
assert_contains "$ROOT_DIR/Brewfile" 'brew "mise"'
assert_contains "$ROOT_DIR/Brewfile" 'brew "colima"'
assert_contains "$ROOT_DIR/Brewfile" 'brew "docker"'
assert_contains "$ROOT_DIR/git/.gitignore_global" ".DS_Store"
assert_ignored ".env"
assert_ignored "credentials.pem"
assert_ignored ".codex/state.json"
assert_ignored "notes.log"
assert_ignored ".DS_Store"
assert_ignored "scratch.swp"
assert_ignored "id_ed25519"
assert_not_ignored ".env.example"

echo "repository hygiene: PASS"
