#!/usr/bin/env bash
# Opt-in macOS-style desktop for GNOME on Ubuntu.
#
# This script is NOT run by install.sh or install-tools.sh. Review it, then
# run it yourself:
#   ./scripts/gnome-macos-theme.sh            # apply
#   ./scripts/gnome-macos-theme.sh --dry-run  # print what would change
#
# Installs the WhiteSur GTK/icon/cursor themes (vinceliuice/WhiteSur-*), the
# User Themes / Dash to Dock / Blur my Shell GNOME Shell extensions, the
# Inter font (a free SF Pro stand-in), and Ulauncher (a Spotlight-like
# launcher), then points GNOME at all of it via gsettings/dconf.
#
# GNOME Shell only loads new extensions after a full log out/in (or, on
# Xorg sessions, Alt+F2 -> "r" -> Enter). Nothing here touches files outside
# your home directory except through apt, and every setting is reversible:
# gsettings reset-recursively org.gnome.desktop.interface, disabling the
# extensions in the Extensions app, and removing ~/.local/share/*-src.
set -euo pipefail

CURL_TIMEOUT_OPTS=(--connect-timeout 10 --max-time 120)
DRY_RUN=false

case "${1:-}" in
  '') ;;
  --dry-run) DRY_RUN=true ;;
  *)
    printf 'Usage: %s [--dry-run]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

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

if [ "$(id -u)" -eq 0 ]; then
  printf 'gnome-macos-theme: run this as your normal user, not with sudo. It calls sudo itself for the apt-get steps; running the whole script as root points $HOME at /root and installs everything into the wrong session.\n' >&2
  exit 1
fi

if [ "$(uname -s)" != Linux ] || ! command -v apt-get >/dev/null 2>&1; then
  printf 'gnome-macos-theme: this script only supports apt-based Linux (Ubuntu).\n' >&2
  exit 1
fi

if ! command -v gnome-shell >/dev/null 2>&1; then
  printf 'gnome-macos-theme: GNOME Shell was not found; this script only styles a GNOME desktop.\n' >&2
  exit 1
fi

SRC_DIR="$HOME/.local/share/dotfiles-gnome-theme-src"
GTK_THEME_SRC="$SRC_DIR/WhiteSur-gtk-theme"
ICON_THEME_SRC="$SRC_DIR/WhiteSur-icon-theme"
CURSOR_THEME_SRC="$SRC_DIR/WhiteSur-cursors"
GNOME_SHELL_VERSION=$(gnome-shell --version | grep -oE '[0-9]+' | head -n1)

# Ubuntu ships its own dock (ubuntu-dock@ubuntu.com) as a fork of Dash to
# Dock that reuses its exact GSettings schema, already enabled by default.
# Installing the vanilla extension alongside it would render two docks, so
# only install one if nothing already provides this schema.
if gsettings list-schemas | grep -qx 'org.gnome.shell.extensions.dash-to-dock'; then
  NEED_VANILLA_DASH_TO_DOCK=false
else
  NEED_VANILLA_DASH_TO_DOCK=true
fi

install_apt_packages() {
  local package_name
  local missing_packages=()

  for package_name in "$@"; do
    if ! dpkg -s "$package_name" >/dev/null 2>&1; then
      missing_packages+=("$package_name")
    fi
  done

  if [ "${#missing_packages[@]}" -eq 0 ]; then
    return
  fi

  log "installing apt packages: ${missing_packages[*]}"
  run sudo apt-get update
  run sudo apt-get install -y "${missing_packages[@]}"
}

clone_or_update() {
  local repo_url="$1"
  local dest_dir="$2"

  if [ -d "$dest_dir/.git" ]; then
    log "updating $(basename "$dest_dir")"
    run git -C "$dest_dir" pull --ff-only
  else
    log "cloning $(basename "$dest_dir")"
    run mkdir -p "$(dirname "$dest_dir")"
    run git clone --depth 1 "$repo_url" "$dest_dir"
  fi
}

extension_installed() {
  [ -d "$HOME/.local/share/gnome-shell/extensions/$1" ]
}

# GNOME Shell only scans ~/.local/share/gnome-shell/extensions for new
# UUIDs at login; `gnome-extensions enable` talks to the *running* shell and
# fails with "does not exist" for one installed in the current session. So
# instead of that, mark it enabled directly in gsettings' string list -
# GNOME Shell will find it there and turn it on the next time it starts.
enable_gnome_extension() {
  local uuid="$1"
  local current new

  current=$(gsettings get org.gnome.shell enabled-extensions)
  case "$current" in
    *"'$uuid'"*)
      log "$uuid already marked enabled"
      return
      ;;
  esac

  if [ "$current" = '[]' ]; then
    new="['$uuid']"
  else
    new="${current%]}, '$uuid']"
  fi
  run gsettings set org.gnome.shell enabled-extensions "$new"
}

install_gnome_extension() {
  local uuid="$1"
  local ext_dir="$HOME/.local/share/gnome-shell/extensions/$uuid"

  if extension_installed "$uuid"; then
    log "GNOME Shell extension already installed: $uuid"
    # Self-heal installs made by an older version of this script that
    # predates the glib-compile-schemas fix below.
    if [ -d "$ext_dir/schemas" ] && [ ! -f "$ext_dir/schemas/gschemas.compiled" ]; then
      glib-compile-schemas "$ext_dir/schemas"
    fi
  elif [ "$DRY_RUN" = true ]; then
    log "dry-run: would download and install GNOME Shell extension $uuid"
  else
    local info_url version_tag zip_path
    info_url="https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${GNOME_SHELL_VERSION}"
    version_tag=$(curl "${CURL_TIMEOUT_OPTS[@]}" -fsSL "$info_url" \
      | jq -r --arg v "$GNOME_SHELL_VERSION" '.shell_version_map[$v].pk // empty')
    if [ -z "$version_tag" ]; then
      printf 'gnome-macos-theme: %s has no published release for GNOME Shell %s; install it manually from extensions.gnome.org.\n' "$uuid" "$GNOME_SHELL_VERSION" >&2
      return 1
    fi

    log "installing GNOME Shell extension $uuid"
    zip_path=$(mktemp --suffix=.zip)
    curl "${CURL_TIMEOUT_OPTS[@]}" -fsSL \
      "https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}" \
      -o "$zip_path"
    rm -rf "$ext_dir"
    mkdir -p "$ext_dir"
    unzip -q "$zip_path" -d "$ext_dir"
    rm -f "$zip_path"

    # extensions.gnome.org ships raw .gschema.xml files; GNOME Shell refuses
    # to enable an extension whose schema isn't compiled (silently, from its
    # own async EnableExtension handler, so gnome-extensions enable below
    # would otherwise report success while nothing actually got enabled).
    if [ -d "$ext_dir/schemas" ]; then
      glib-compile-schemas "$ext_dir/schemas"
    fi
  fi

  enable_gnome_extension "$uuid"
}

install_whitesur_gtk_theme() {
  clone_or_update https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$GTK_THEME_SRC"
  log 'installing WhiteSur GTK theme (Light + Dark).'
  run bash "$GTK_THEME_SRC/install.sh"
}

install_whitesur_icon_theme() {
  clone_or_update https://github.com/vinceliuice/WhiteSur-icon-theme.git "$ICON_THEME_SRC"
  log 'installing WhiteSur icon theme.'
  run bash "$ICON_THEME_SRC/install.sh"
}

install_whitesur_cursor_theme() {
  clone_or_update https://github.com/vinceliuice/WhiteSur-cursors.git "$CURSOR_THEME_SRC"
  log 'installing WhiteSur cursor theme.'
  # Unlike the gtk/icon installers, this one's install.sh copies a relative
  # "dist" path, so it must be run with its own directory as the cwd.
  run env -C "$CURSOR_THEME_SRC" bash install.sh
}

ensure_dock_extension() {
  if [ "$NEED_VANILLA_DASH_TO_DOCK" = false ]; then
    log 'a dash-to-dock-compatible extension is already present (Ubuntu ships its own fork as ubuntu-dock); configuring it instead of installing a second dock.'
    return
  fi
  install_gnome_extension dash-to-dock@micxgx.gmail.com \
    || log 'warning: dash-to-dock extension install failed; install it manually via the Extensions app.'
}

# Reconnects the GTK theme's Dash to Dock CSS overrides. tweaks.sh only
# knows how to find the vanilla dash-to-dock@micxgx.gmail.com uuid, so this
# only applies when that's the extension actually in use (see
# NEED_VANILLA_DASH_TO_DOCK above); ubuntu-dock gets styled well enough by
# the GTK theme alone.
apply_dash_to_dock_theme_fix() {
  if [ "$NEED_VANILLA_DASH_TO_DOCK" = false ]; then
    return
  fi
  if [ "$DRY_RUN" = true ]; then
    log 'dry-run: would run WhiteSur-gtk-theme tweaks.sh --dash-to-dock'
    return
  fi
  bash "$GTK_THEME_SRC/tweaks.sh" --dash-to-dock \
    || log 'warning: WhiteSur dash-to-dock CSS tweak failed; the dock will still work with default styling.'
}

install_ulauncher() {
  if command -v ulauncher >/dev/null 2>&1; then
    log 'ulauncher already available; installation is skipped.'
    return
  fi

  local download_url deb_path
  download_url=$(curl "${CURL_TIMEOUT_OPTS[@]}" -fsSL https://api.github.com/repos/Ulauncher/Ulauncher/releases/latest \
    | jq -r '.assets[] | select(.name | test("_all\\.deb$")) | .browser_download_url' | head -n1)
  if [ -z "$download_url" ]; then
    printf 'ulauncher: could not find a GitHub release .deb; install it manually.\n' >&2
    return 1
  fi

  if [ "$DRY_RUN" = true ]; then
    log "dry-run: would download and install ulauncher from $download_url"
    return
  fi

  log 'installing ulauncher from its GitHub release .deb (Spotlight-like launcher; set its hotkey to Super+Space after first launch).'
  deb_path=$(mktemp --suffix=.deb)
  curl "${CURL_TIMEOUT_OPTS[@]}" -fsSL "$download_url" -o "$deb_path"
  sudo apt-get install -y "$deb_path"
  rm -f "$deb_path"
}

# GTK apps don't follow the system light/dark switch on their own; pick the
# WhiteSur variant that matches it right now. Re-run this script after
# toggling dark mode to switch the GTK/icon/shell theme to match.
select_variant() {
  local scheme
  scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || printf "'default'")
  case "$scheme" in
    *prefer-dark*) printf 'dark\n' ;;
    *) printf 'light\n' ;;
  esac
}

apply_interface_settings() {
  local gtk_theme icon_theme

  if [ "$(select_variant)" = dark ]; then
    gtk_theme='WhiteSur-Dark'
    icon_theme='WhiteSur-dark'
  else
    gtk_theme='WhiteSur-Light'
    icon_theme='WhiteSur'
  fi

  run gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
  run gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"
  run gsettings set org.gnome.desktop.interface cursor-theme 'WhiteSur-cursors'
  run gsettings set org.gnome.desktop.interface font-name 'Inter 11'
  run gsettings set org.gnome.desktop.interface document-font-name 'Inter 11'
  run gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter Bold 11'
  run dconf write /org/gnome/shell/extensions/user-theme/name "'$gtk_theme'"
}

apply_dock_settings() {
  local dock=/org/gnome/shell/extensions/dash-to-dock

  run dconf write "$dock/dock-position" "'BOTTOM'"
  run dconf write "$dock/extend-height" 'false'
  run dconf write "$dock/dock-fixed" 'false'
  run dconf write "$dock/autohide" 'true'
  run dconf write "$dock/intellihide" 'true'
  run dconf write "$dock/dash-max-icon-size" '48'
  run dconf write "$dock/show-trash" 'false'
  run dconf write "$dock/show-mounts" 'false'
  run dconf write "$dock/click-action" "'minimize'"
}

install_apt_packages \
  git curl jq unzip dconf-cli gnome-shell-extension-manager gnome-tweaks \
  fonts-inter sassc libglib2.0-dev-bin libxml2-utils

install_whitesur_gtk_theme
install_whitesur_icon_theme
install_whitesur_cursor_theme

# Each install is allowed to fail independently (a transient network hiccup
# on one extension shouldn't abort the rest of the script).
install_gnome_extension user-theme@gnome-shell-extensions.gcampax.github.com \
  || log 'warning: user-theme extension install failed; install it manually via the Extensions app.'
ensure_dock_extension
install_gnome_extension blur-my-shell@aunetx \
  || log 'warning: blur-my-shell extension install failed; install it manually via the Extensions app.'
apply_dash_to_dock_theme_fix

install_ulauncher \
  || log 'warning: ulauncher install failed; install it manually from https://ulauncher.io.'

apply_interface_settings
apply_dock_settings

if [ "$DRY_RUN" = true ]; then
  log ''
  log 'Dry run only; nothing was changed.'
else
  log ''
  log 'Done. Log out and back in so GNOME Shell picks up the new extensions,'
  if [ "$NEED_VANILLA_DASH_TO_DOCK" = true ]; then
    log 'then confirm User Themes, Dash to Dock, and Blur my Shell are enabled'
  else
    log 'then confirm User Themes and Blur my Shell are enabled (the dock is'
    log 'Ubuntu'"'"'s own ubuntu-dock, already enabled, just reconfigured)'
  fi
  log 'in the Extensions app. Open Ulauncher once and set its hotkey to Super+Space.'
fi
