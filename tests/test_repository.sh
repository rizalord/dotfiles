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
assert_file "$ROOT_DIR/LICENSE"
assert_file "$ROOT_DIR/README.md"
assert_contains "$ROOT_DIR/LICENSE" "MIT License"
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
assert_contains "$ROOT_DIR/Brewfile" 'brew "eza"'
assert_contains "$ROOT_DIR/Brewfile" 'brew "fastfetch"'
assert_contains "$ROOT_DIR/Brewfile" 'brew "git-delta"'
assert_contains "$ROOT_DIR/Brewfile" 'brew "zsh-syntax-highlighting"'
assert_contains "$ROOT_DIR/Brewfile" 'cask "ghostty"'
assert_file "$ROOT_DIR/starship/starship.toml"
assert_file "$ROOT_DIR/ghostty/config"
assert_file "$ROOT_DIR/fastfetch/config.jsonc"
assert_file "$ROOT_DIR/ssh/config"
assert_file "$ROOT_DIR/scripts/macos-defaults.sh"
assert_file "$ROOT_DIR/scripts/install-apt.sh"
assert_file "$ROOT_DIR/.github/workflows/ci.yml"
assert_contains "$ROOT_DIR/ssh/config" "AddKeysToAgent yes"
assert_contains "$ROOT_DIR/ssh/config" "Include ~/.ssh/config.local"
assert_contains "$ROOT_DIR/.github/workflows/ci.yml" "scripts/test.sh"
assert_contains "$ROOT_DIR/scripts/install-apt.sh" "download.docker.com"
assert_contains "$ROOT_DIR/scripts/install-apt.sh" "cli.github.com"
assert_contains "$ROOT_DIR/git/.gitignore_global" ".DS_Store"
assert_ignored ".env"
assert_ignored "credentials.pem"
assert_ignored ".codex/state.json"
assert_ignored "docs/superpowers/plans/example.md"
assert_ignored "notes.log"
assert_ignored ".DS_Store"
assert_ignored "scratch.swp"
assert_ignored "id_ed25519"
assert_not_ignored ".env.example"
assert_ignored ".docker/config.json"
assert_ignored ".colima/default/config.yaml"
assert_ignored "docker-compose.override.yml"
assert_ignored "docker-compose.override.yaml"
assert_ignored "compose.override.yml"
assert_ignored "compose.override.yaml"
assert_ignored "docker-compose.local.yml"
assert_ignored "docker-compose.local.yaml"
assert_ignored "compose.local.yml"
assert_ignored "compose.local.yaml"
assert_ignored "docker-compose.state"
assert_ignored "compose.state"
assert_not_ignored "docker-compose.yml"
assert_not_ignored "docker-compose.dev.yml"
assert_not_ignored "compose.yml"
assert_not_ignored "compose.dev.yml"

echo "repository hygiene: PASS"
