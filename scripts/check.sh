#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_INSTALLED=false
STRICT_TOOLS=false
FAILED=false

usage() {
  printf 'Usage: %s [--installed] [--strict-tools]\n' "${0##*/}" >&2
}

pass() {
  printf 'check: PASS: %s\n' "$*"
}

fail() {
  printf 'check: FAIL: %s\n' "$*" >&2
  FAILED=true
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --installed) CHECK_INSTALLED=true ;;
    --strict-tools) STRICT_TOOLS=true ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

check_file() {
  local file_path="$1"
  if [ -f "$file_path" ]; then
    pass "file present: ${file_path#$ROOT_DIR/}"
  else
    fail "missing file: ${file_path#$ROOT_DIR/}"
  fi
}

check_required_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "required command available: $command_name"
  else
    fail "required command missing: $command_name"
  fi
}

check_optional_command() {
  local display_name="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    pass "tool available: $display_name"
  elif [ "$STRICT_TOOLS" = true ]; then
    fail "tool missing: $display_name"
  else
    printf 'check: MISSING: %s\n' "$display_name"
  fi
}

check_managed_link() {
  local link_path="$1"
  local expected_target="$2"
  local actual_target

  if [ ! -L "$link_path" ]; then
    fail "managed link missing: $link_path"
    return
  fi

  actual_target=$(readlink "$link_path") || {
    fail "managed link target unreadable: $link_path"
    return
  }
  if [ "$actual_target" = "$expected_target" ]; then
    pass "managed link valid: $link_path"
  else
    fail "managed link target mismatch: $link_path (actual: $actual_target; expected: $expected_target)"
  fi
}

check_file "$ROOT_DIR/.gitignore"
check_file "$ROOT_DIR/LICENSE"
check_file "$ROOT_DIR/README.md"
check_file "$ROOT_DIR/Brewfile"
check_file "$ROOT_DIR/git/.gitconfig"
check_file "$ROOT_DIR/git/.gitignore_global"
check_file "$ROOT_DIR/zsh/.zprofile"
check_file "$ROOT_DIR/zsh/.zshrc"
check_file "$ROOT_DIR/starship/starship.toml"
check_file "$ROOT_DIR/ghostty/config"
check_file "$ROOT_DIR/fastfetch/config.jsonc"
check_file "$ROOT_DIR/ssh/config"
check_file "$ROOT_DIR/scripts/macos-defaults.sh"
check_file "$ROOT_DIR/scripts/gnome-macos-theme.sh"
check_file "$ROOT_DIR/scripts/install-apt.sh"
check_file "$ROOT_DIR/.github/workflows/ci.yml"

for formula in gh glab mise colima docker docker-buildx docker-compose; do
  if grep -Fq -- "brew \"$formula\"" "$ROOT_DIR/Brewfile"; then
    pass "Brewfile includes: $formula"
  else
    fail "Brewfile missing formula: $formula"
  fi
done

check_required_command git
check_required_command zsh

if command -v zsh >/dev/null 2>&1; then
  for zsh_file in "$ROOT_DIR/zsh/.zprofile" "$ROOT_DIR/zsh/.zshrc"; do
    if zsh -n "$zsh_file"; then
      pass "zsh syntax: ${zsh_file#$ROOT_DIR/}"
    else
      fail "invalid zsh syntax: ${zsh_file#$ROOT_DIR/}"
    fi
  done
fi

for shell_file in "$ROOT_DIR/install.sh" "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/tests/*.sh; do
  if bash -n "$shell_file"; then
    pass "bash syntax: ${shell_file#$ROOT_DIR/}"
  else
    fail "invalid bash syntax: ${shell_file#$ROOT_DIR/}"
  fi
done

if git config --file "$ROOT_DIR/git/.gitconfig" --get init.defaultBranch 2>/dev/null | grep -Fxq main; then
  pass 'shared Git configuration is valid'
else
  fail 'shared Git configuration is invalid'
fi

# Reject secrets and personal absolute paths from tracked content. Markers are
# split with quotes so this script never matches itself.
readonly private_key_prefix='BEGIN '
readonly private_key_suffix='.* PRIVATE KEY'
readonly private_key_pattern="${private_key_prefix}${private_key_suffix}"
readonly path_marker="/Users/"'rizalord'
readonly openai_marker="OPENAI_API_KEY"'='
readonly anthropic_marker="ANTHROPIC_API_KEY"'='
readonly github_marker='gho''_'
readonly gitlab_marker='glpat''-'

for forbidden_pattern in \
  "$path_marker" \
  "$openai_marker" \
  "$anthropic_marker" \
  "$github_marker" \
  "$gitlab_marker" \
  "$private_key_pattern"; do
  if git -C "$ROOT_DIR" grep -lIE -- "$forbidden_pattern" -- . >/dev/null 2>&1; then
    fail "forbidden tracked content matches: $forbidden_pattern"
  else
    pass "security pattern absent: $forbidden_pattern"
  fi
done

if git -C "$ROOT_DIR" ls-files -- '*.pem' | grep -q .; then
  fail 'tracked PEM file found'
else
  pass 'no tracked PEM files'
fi

for tool in brew mise gh glab codex claude opencode code colima docker fzf zoxide starship eza bat delta fastfetch; do
  check_optional_command "$tool" command -v "$tool"
done
check_optional_command 'docker buildx' docker buildx version
check_optional_command 'docker compose' docker compose version

if [ "$CHECK_INSTALLED" = true ]; then
  XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
  if [ "$XDG_CONFIG_HOME" = "$HOME/.config" ]; then
    expected_include='~/.config/git/dotfiles.gitconfig'
  else
    expected_include="$XDG_CONFIG_HOME/git/dotfiles.gitconfig"
  fi

  check_managed_link "$HOME/.zshrc" "$ROOT_DIR/zsh/.zshrc"
  check_managed_link "$HOME/.zprofile" "$ROOT_DIR/zsh/.zprofile"
  check_managed_link "$XDG_CONFIG_HOME/git/dotfiles.gitconfig" "$ROOT_DIR/git/.gitconfig"
  check_managed_link "$XDG_CONFIG_HOME/git/ignore" "$ROOT_DIR/git/.gitignore_global"
  check_managed_link "$XDG_CONFIG_HOME/starship.toml" "$ROOT_DIR/starship/starship.toml"
  check_managed_link "$XDG_CONFIG_HOME/ghostty/config" "$ROOT_DIR/ghostty/config"
  check_managed_link "$XDG_CONFIG_HOME/fastfetch/config.jsonc" "$ROOT_DIR/fastfetch/config.jsonc"
  check_managed_link "$HOME/.ssh/config" "$ROOT_DIR/ssh/config"

  if git config --global --get-all include.path 2>/dev/null | grep -Fxq "$expected_include"; then
    pass "Git include present: $expected_include"
  else
    fail "Git include missing: $expected_include"
  fi
fi

if [ "$FAILED" = true ]; then
  printf 'check: FAILED\n' >&2
  exit 1
fi

printf 'check: PASS\n'
