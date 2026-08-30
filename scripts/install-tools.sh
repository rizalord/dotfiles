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

read_file_mode() {
  local file_path="$1"
  local file_mode

  file_mode=$(stat -f '%Lp' "$file_path" 2>/dev/null || true)
  case "$file_mode" in
    ''|*[!0-7]*) file_mode=$(stat -c '%a' "$file_path" 2>/dev/null || true) ;;
  esac
  case "$file_mode" in
    ''|*[!0-7]*) return 1 ;;
    *) printf '%s\n' "$file_mode" ;;
  esac
}

validate_docker_config_path() {
  local config_dir="$1"
  local normalized_path
  local parent

  case "$config_dir" in
    /*) ;;
    *)
      printf 'invalid Docker config path: DOCKER_CONFIG must be an absolute path: %s\n' "$config_dir" >&2
      return 1
      ;;
  esac

  case "$config_dir" in
    /|*'//'|*/./*|*/.|*/../*|*/..)
      printf 'invalid Docker config path: DOCKER_CONFIG contains a root, duplicate separator, or traversal component: %s\n' "$config_dir" >&2
      return 1
      ;;
  esac

  case "$config_dir" in
    "$ROOT_DIR"|"$ROOT_DIR"/*)
      printf 'invalid Docker config path: DOCKER_CONFIG must not point inside this repository: %s\n' "$config_dir" >&2
      return 1
      ;;
  esac

  normalized_path="$config_dir"
  while [ "$normalized_path" != "/" ] && [ "${normalized_path%/}" != "$normalized_path" ]; do
    normalized_path="${normalized_path%/}"
  done
  parent="$normalized_path"
  while [ "$parent" != "/" ]; do
    if [ -L "$parent" ]; then
      printf 'invalid Docker config path: DOCKER_CONFIG has a symlinked parent directory: %s\n' "$config_dir" >&2
      return 1
    fi
    parent="${parent%/*}"
    if [ -z "$parent" ]; then
      parent="/"
    fi
  done
}

configure_docker_cli_plugins() {
  local os_name
  local brew_prefix
  local plugin_dir
  local docker_config_dir
  local config_path
  local jq_command
  local temp_config
  local config_mode

  os_name=$(uname -s)
  if [ "$os_name" != Darwin ]; then
    log 'Docker CLI plugin config skipped: macOS only.'
    return 0
  fi

  docker_config_dir=${DOCKER_CONFIG:-"$HOME/.docker"}
  if ! validate_docker_config_path "$docker_config_dir"; then
    return 1
  fi
  while [ "$docker_config_dir" != "/" ] && [ "${docker_config_dir%/}" != "$docker_config_dir" ]; do
    docker_config_dir="${docker_config_dir%/}"
  done
  config_path="$docker_config_dir/config.json"

  if [ "$DRY_RUN" = true ]; then
    plugin_dir='$(brew --prefix)/lib/docker/cli-plugins'
    log "dry-run: would configure Docker CLI plugins in $config_path using $plugin_dir"
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    if [ "$SKIP_BREW" = true ]; then
      log 'Docker CLI plugin config skipped: Homebrew unavailable with --skip-brew.'
      return 0
    fi
    printf 'missing prerequisite: Homebrew is required to discover Docker CLI plugins. Install Homebrew, then rerun this script.\n' >&2
    return 1
  fi

  if ! brew_prefix=$(brew --prefix 2>/dev/null) || [ -z "$brew_prefix" ]; then
    printf 'missing prerequisite: unable to determine the Homebrew prefix with "brew --prefix". Fix Homebrew, then rerun this script.\n' >&2
    return 1
  fi

  plugin_dir="$brew_prefix/lib/docker/cli-plugins"
  if [ ! -d "$plugin_dir" ]; then
    printf 'missing prerequisite: Docker CLI plugin directory %s. Run brew bundle and ensure docker-buildx/docker-compose are installed, then rerun this script.\n' "$plugin_dir" >&2
    return 1
  fi

  if jq_command=$(command -v jq 2>/dev/null); then
    :
  elif [ -x "$brew_prefix/bin/jq" ]; then
    jq_command="$brew_prefix/bin/jq"
  else
    printf 'missing prerequisite: jq is required to update Docker config.json safely. Run brew bundle or make jq available in PATH, then rerun this script.\n' >&2
    return 1
  fi

  if [ -e "$config_path" ] && [ ! -f "$config_path" ]; then
    printf 'invalid Docker config: %s is not a regular file. Move it aside or choose another DOCKER_CONFIG, then rerun this script.\n' "$config_path" >&2
    return 1
  fi
  if [ -L "$config_path" ]; then
    printf 'invalid Docker config: %s is a symlink. Refusing to replace it; move it aside or choose another DOCKER_CONFIG, then rerun this script.\n' "$config_path" >&2
    return 1
  fi

  if [ -f "$config_path" ]; then
    if ! "$jq_command" -e 'type == "object" and ((.cliPluginsExtraDirs? == null) or (((.cliPluginsExtraDirs | type) == "array") and all(.cliPluginsExtraDirs[]; type == "string")))' "$config_path" >/dev/null 2>&1; then
      printf 'invalid Docker config: %s is not valid JSON or has an invalid cliPluginsExtraDirs array. Fix it or choose another DOCKER_CONFIG, then rerun this script.\n' "$config_path" >&2
      return 1
    fi
    if "$jq_command" -e --arg plugin "$plugin_dir" '(.cliPluginsExtraDirs // []) | index($plugin) != null' "$config_path" >/dev/null 2>&1; then
      log "Docker CLI plugin directory already configured: $plugin_dir"
      return 0
    fi
  fi

  if ! mkdir -p "$docker_config_dir"; then
    printf 'unable to create Docker config directory: %s. Check the path and permissions, then rerun this script.\n' "$docker_config_dir" >&2
    return 1
  fi

  if ! temp_config=$(mktemp "$docker_config_dir/.config.json.tmp.XXXXXX"); then
    printf 'unable to create a temporary Docker config in: %s. Check the path and permissions, then rerun this script.\n' "$docker_config_dir" >&2
    return 1
  fi

  if [ -f "$config_path" ]; then
    if ! "$jq_command" --arg plugin "$plugin_dir" '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + [$plugin] | unique)' "$config_path" > "$temp_config"; then
      rm -f "$temp_config"
      printf 'unable to update Docker config safely: %s. Fix the JSON or choose another DOCKER_CONFIG, then rerun this script.\n' "$config_path" >&2
      return 1
    fi
    if ! config_mode=$(read_file_mode "$config_path") || ! chmod "$config_mode" "$temp_config"; then
      rm -f "$temp_config"
      printf 'unable to preserve Docker config permissions: %s. Check the file, then rerun this script.\n' "$config_path" >&2
      return 1
    fi
  else
    if ! "$jq_command" -n --arg plugin "$plugin_dir" '{cliPluginsExtraDirs: [$plugin]}' > "$temp_config"; then
      rm -f "$temp_config"
      printf 'unable to create Docker config safely: %s. Check the path and permissions, then rerun this script.\n' "$config_path" >&2
      return 1
    fi
  fi

  if ! mv -f "$temp_config" "$config_path"; then
    rm -f "$temp_config"
    printf 'unable to install Docker config: %s. Check the path and permissions, then rerun this script.\n' "$config_path" >&2
    return 1
  fi
  log "Docker CLI plugin directory configured: $plugin_dir"
}

verify_docker_cli_plugins() {
  if [ "$DRY_RUN" = true ]; then
    log 'dry-run: would verify Docker Buildx: docker buildx version'
    log 'dry-run: would verify Docker Compose: docker compose version'
    return 0
  fi

  if ! docker buildx version >/dev/null 2>&1; then
    printf 'missing prerequisite: Docker Buildx. Install the docker-buildx plugin and ensure Docker can find it, then rerun this script.\n' >&2
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    printf 'missing prerequisite: Docker Compose. Install the docker-compose plugin and ensure Docker can find it, then rerun this script.\n' >&2
    return 1
  fi
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

if [ "$DRY_RUN" = false ]; then
  for required_tool in mise colima docker gh glab; do
    require_command "$required_tool"
  done
else
  for required_tool in mise colima docker gh glab; do
    log "dry-run: would verify prerequisite: $required_tool"
  done
fi

configure_docker_cli_plugins
verify_docker_cli_plugins

export NPM_CONFIG_PREFIX="$HOME/.local"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
log "NPM_CONFIG_PREFIX=$NPM_CONFIG_PREFIX"

missing_ai_cli=false
for ai_cli in codex claude; do
  if command -v "$ai_cli" >/dev/null 2>&1; then
    if [ "$DRY_RUN" = true ]; then
      if [ "$ai_cli" = codex ]; then
        log 'codex already available; @openai/codex installation is skipped.'
      else
        log 'claude already available; @anthropic-ai/claude-code installation is skipped.'
      fi
    else
      log "$ai_cli already available; npm package installation is skipped."
    fi
  else
    missing_ai_cli=true
  fi
done

if [ "$missing_ai_cli" = false ]; then
  exit 0
fi

run mkdir -p "$NPM_CONFIG_PREFIX/bin"
run mise use --global node@lts

if [ "$DRY_RUN" = true ]; then
  run mise exec -- npm --version
else
  if ! mise exec -- npm --version >/dev/null 2>&1; then
    printf 'missing prerequisite: mise-managed npm. Run "mise use --global node@lts" and ensure mise can execute npm, then rerun this script.\n' >&2
    exit 1
  fi
fi

if command -v codex >/dev/null 2>&1; then
  log 'codex already available; @openai/codex installation is skipped.'
else
  run mise exec -- npm install --global @openai/codex
fi

if command -v claude >/dev/null 2>&1; then
  log 'claude already available; @anthropic-ai/claude-code installation is skipped.'
else
  run mise exec -- npm install --global @anthropic-ai/claude-code
fi
