#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DRY_RUN=false

usage() {
  printf 'Usage: %s [--dry-run]\n' "${0##*/}" >&2
}

case "$#" in
  0) ;;
  1)
    if [ "$1" = '--dry-run' ]; then
      DRY_RUN=true
    else
      usage
      exit 2
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
BACKUP_ROOT="$HOME/.local/state/dotfiles-backups"
BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=''
GIT_CONFIG_PATH="$XDG_CONFIG_HOME/git/dotfiles.gitconfig"
if [ "$XDG_CONFIG_HOME" = "$HOME/.config" ]; then
  GIT_INCLUDE='~/.config/git/dotfiles.gitconfig'
else
  GIT_INCLUDE="$GIT_CONFIG_PATH"
fi

log() {
  printf '%s\n' "$*"
}

ensure_backup_directory() {
  local attempt=0
  local candidate

  if [ -n "$BACKUP_DIR" ]; then
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    BACKUP_DIR="$BACKUP_ROOT/${BACKUP_TIMESTAMP}-$$"
    return
  fi

  mkdir -p "$BACKUP_ROOT"
  while :; do
    candidate="$BACKUP_ROOT/${BACKUP_TIMESTAMP}-$$-$attempt"
    if mkdir "$candidate" 2>/dev/null; then
      BACKUP_DIR="$candidate"
      return
    fi
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
      printf 'failed to create backup directory: %s\n' "$candidate" >&2
      return 1
    fi
    attempt=$((attempt + 1))
  done
}

backup_existing() {
  local destination="$1"
  ensure_backup_directory
  local backup_path="$BACKUP_DIR/$(basename "$destination")"
  local link_target
  local resolved_link_target
  local backup_temp

  if [ "$DRY_RUN" = true ]; then
    log "would back up $destination to $backup_path"
    return
  fi

  if [ -L "$destination" ]; then
    link_target=$(readlink "$destination")
    case "$link_target" in
      /*) ;;
      *)
        if resolved_link_target=$(CDPATH= cd -- "$(dirname "$destination")" && \
          printf '%s/%s\n' "$(pwd -P)" "$link_target"); then
          backup_temp="$backup_path.tmp.$$"
          ln -s "$resolved_link_target" "$backup_temp"
          mv "$destination" "$backup_path"
          mv -f "$backup_temp" "$backup_path"
          log "backed up $destination to $backup_path"
          return
        fi
        ;;
    esac
  fi

  mv "$destination" "$backup_path"
  log "backed up $destination to $backup_path"
}

ensure_directory() {
  local directory="$1"

  if [ -d "$directory" ] && [ ! -L "$directory" ]; then
    return
  fi

  if [ -e "$directory" ] || [ -L "$directory" ]; then
    backup_existing "$directory"
  fi

  if [ "$DRY_RUN" = true ]; then
    log "would create directory $directory"
    return
  fi

  mkdir -p "$directory"
  log "created directory $directory"
}

link_managed_file() {
  local source="$1"
  local destination="$2"

  if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then
    log "already linked $destination"
    return
  fi

  ensure_directory "$(dirname "$destination")"

  if [ -e "$destination" ] || [ -L "$destination" ]; then
    backup_existing "$destination"
  fi

  if [ "$DRY_RUN" = true ]; then
    log "would link $destination to $source"
    return
  fi

  ln -s "$source" "$destination"
  log "linked $destination to $source"
}

ensure_git_include() {
  if git config --global --get-all include.path 2>/dev/null | grep -Fxq "$GIT_INCLUDE"; then
    log "Git include already configured: $GIT_INCLUDE"
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    log "would add Git include: $GIT_INCLUDE"
    return
  fi

  git config --global --add include.path "$GIT_INCLUDE"
  log "added Git include: $GIT_INCLUDE"
}

link_managed_file "$ROOT_DIR/zsh/.zshrc" "$HOME/.zshrc"
link_managed_file "$ROOT_DIR/zsh/.zprofile" "$HOME/.zprofile"
link_managed_file "$ROOT_DIR/git/.gitconfig" "$XDG_CONFIG_HOME/git/dotfiles.gitconfig"
link_managed_file "$ROOT_DIR/git/.gitignore_global" "$XDG_CONFIG_HOME/git/ignore"
ensure_git_include
