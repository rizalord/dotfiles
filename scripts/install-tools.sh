#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DRY_RUN=false
SKIP_BREW=false

usage() {
  printf 'Usage: %s [--dry-run] [--skip-brew]\n' "${0##*/}" >&2
}

log() {
  printf '%s\n' "$*"
}

run() {
  if [ "$DRY_RUN" = true ]; then
    printf 'dry-run: '
    printf '%q ' "$@"
    printf '\n'
    return
  fi
  "$@"
}

require_command() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    return
  fi

  printf 'missing prerequisite: %s. Install it with Homebrew (or make it available in PATH), then rerun this script.\n' "$command_name" >&2
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --skip-brew) SKIP_BREW=true ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

if [ "$SKIP_BREW" = false ]; then
  if [ "$(uname -s)" = Darwin ]; then
    if command -v brew >/dev/null 2>&1; then
      run brew bundle "--file=$ROOT_DIR/Brewfile"
    else
      printf 'missing prerequisite: Homebrew. Install Homebrew, or rerun with --skip-brew if you manage tools separately.\n' >&2
      exit 1
    fi
  else
    log 'Homebrew bundle skipped: this installer only uses Brewfile on macOS.'
  fi
else
  log 'Homebrew bundle skipped by --skip-brew.'
fi

if [ "$DRY_RUN" = true ]; then
  for required_tool in mise colima docker gh glab; do
    log "dry-run: would verify prerequisite: $required_tool"
  done
  export NPM_CONFIG_PREFIX="$HOME/.local"
  export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
  log "NPM_CONFIG_PREFIX=$NPM_CONFIG_PREFIX"
  run mkdir -p "$NPM_CONFIG_PREFIX/bin"
  run mise use --global node@lts
  run npm install --global @openai/codex
  run npm install --global @anthropic-ai/claude-code
  exit 0
fi

for required_tool in mise colima docker gh glab; do
  require_command "$required_tool"
done

missing_ai_cli=false
for ai_cli in codex claude; do
  if command -v "$ai_cli" >/dev/null 2>&1; then
    log "$ai_cli already available; npm package installation is skipped."
  else
    missing_ai_cli=true
  fi
done

if [ "$missing_ai_cli" = false ]; then
  exit 0
fi

export NPM_CONFIG_PREFIX="$HOME/.local"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
log "NPM_CONFIG_PREFIX=$NPM_CONFIG_PREFIX"
run mkdir -p "$NPM_CONFIG_PREFIX/bin"
run mise use --global node@lts

require_command npm

if command -v codex >/dev/null 2>&1; then
  log 'codex already available; @openai/codex installation is skipped.'
else
  run npm install --global @openai/codex
fi

if command -v claude >/dev/null 2>&1; then
  log 'claude already available; @anthropic-ai/claude-code installation is skipped.'
else
  run npm install --global @anthropic-ai/claude-code
fi
