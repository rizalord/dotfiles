#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

log() {
  printf '%s\n' "$*"
}

# Debian ships these under different binary names; give the tool its
# conventional name in ~/.local/bin without touching the apt-owned binary.
link_local_bin() {
  local link_name="$1"
  local target_command="$2"
  local target_path

  if command -v "$link_name" >/dev/null 2>&1; then
    return
  fi
  if ! target_path=$(command -v "$target_command" 2>/dev/null); then
    return
  fi

  mkdir -p "$HOME/.local/bin"
  ln -sf "$target_path" "$HOME/.local/bin/$link_name"
  log "linked $HOME/.local/bin/$link_name -> $target_path"
}

detect_arch() {
  case "$(dpkg --print-architecture)" in
    amd64) printf 'amd64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) printf 'unsupported\n' ;;
  esac
}

# GitHub Releases use a different arch naming convention than dpkg; this maps
# dpkg's amd64/arm64 to each project's own release-asset naming.
gnu_target_for_arch() {
  case "$1" in
    amd64) printf 'x86_64-unknown-linux-gnu\n' ;;
    arm64) printf 'aarch64-unknown-linux-gnu\n' ;;
    *) printf 'unsupported\n' ;;
  esac
}

github_latest_asset_url() {
  local repo="$1"
  local asset_pattern="$2"

  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | jq -r --arg pattern "$asset_pattern" \
      '.assets[] | select(.name | test($pattern)) | .browser_download_url' \
    | head -n1
}

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
  sudo apt-get update
  sudo apt-get install -y "${missing_packages[@]}"
}

install_core_apt_packages() {
  install_apt_packages \
    ca-certificates curl gnupg wget fontconfig \
    bat fd-find fzf jq ripgrep shellcheck zoxide \
    zsh-autosuggestions zsh-syntax-highlighting

  link_local_bin bat batcat
  link_local_bin fd fdfind
}

install_eza() {
  if command -v eza >/dev/null 2>&1; then
    log 'eza already available; installation is skipped.'
    return
  fi

  if sudo apt-get install -y eza; then
    return
  fi

  local arch gnu_target download_url archive_path extract_dir binary_path
  arch=$(detect_arch)
  gnu_target=$(gnu_target_for_arch "$arch")
  if [ "$gnu_target" = unsupported ]; then
    printf 'eza: no apt package and no known GitHub release asset for arch %s; install it manually.\n' "$arch" >&2
    return 1
  fi

  log 'eza not available via apt; downloading the official binary from eza-community/eza releases.'
  download_url=$(github_latest_asset_url eza-community/eza "eza_${gnu_target}.tar.gz")
  if [ -z "$download_url" ]; then
    printf 'eza: could not find a GitHub release asset for %s; install it manually.\n' "$gnu_target" >&2
    return 1
  fi

  archive_path=$(mktemp --suffix=.tar.gz)
  extract_dir=$(mktemp -d)
  curl -fsSL "$download_url" -o "$archive_path"
  tar -xzf "$archive_path" -C "$extract_dir"
  binary_path=$(find "$extract_dir" -type f -name eza | head -n1)
  if [ -z "$binary_path" ]; then
    rm -rf "$archive_path" "$extract_dir"
    printf 'eza: downloaded archive did not contain an "eza" binary; install it manually.\n' >&2
    return 1
  fi

  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$binary_path" "$HOME/.local/bin/eza"
  rm -rf "$archive_path" "$extract_dir"
  log "installed eza to $HOME/.local/bin/eza"
}

install_git_delta() {
  if command -v delta >/dev/null 2>&1; then
    log 'git-delta already available; installation is skipped.'
    return
  fi

  if sudo apt-get install -y git-delta; then
    return
  fi

  local arch download_url deb_path
  arch=$(detect_arch)
  if [ "$arch" = unsupported ]; then
    printf 'git-delta: no apt package and no known GitHub release asset for this arch; install it manually.\n' >&2
    return 1
  fi

  log 'git-delta not available via apt; downloading the official .deb from dandavison/delta releases.'
  download_url=$(github_latest_asset_url dandavison/delta "_${arch}.deb")
  if [ -z "$download_url" ]; then
    printf 'git-delta: could not find a GitHub release .deb for arch %s; install it manually.\n' "$arch" >&2
    return 1
  fi

  deb_path=$(mktemp --suffix=.deb)
  curl -fsSL "$download_url" -o "$deb_path"
  sudo dpkg -i "$deb_path"
  rm -f "$deb_path"
}

install_starship() {
  if command -v starship >/dev/null 2>&1; then
    log 'starship already available; installation is skipped.'
    return
  fi

  if sudo apt-get install -y starship; then
    return
  fi

  log 'starship not available via apt; running the official installer.'
  curl -sS https://starship.rs/install.sh | sh -s -- -y
}

install_mise() {
  if command -v mise >/dev/null 2>&1; then
    log 'mise already available; installation is skipped.'
    return
  fi

  log 'installing mise via the official installer.'
  curl https://mise.jdx.dev/install.sh | sh
}

install_gh() {
  if command -v gh >/dev/null 2>&1; then
    log 'gh already available; installation is skipped.'
    return
  fi

  local keyring=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  local sources_file=/etc/apt/sources.list.d/github-cli.list

  if [ ! -f "$sources_file" ]; then
    log 'configuring the official GitHub CLI apt repository.'
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee "$keyring" >/dev/null
    sudo chmod go+r "$keyring"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main" \
      | sudo tee "$sources_file" >/dev/null
  fi

  sudo apt-get update
  sudo apt-get install -y gh
}

install_glab() {
  if command -v glab >/dev/null 2>&1; then
    log 'glab already available; installation is skipped.'
    return
  fi

  local arch download_url deb_path
  arch=$(detect_arch)
  if [ "$arch" = unsupported ]; then
    printf 'glab: no known GitHub release asset for this arch; install it manually.\n' >&2
    return 1
  fi

  log 'glab has no official apt repository; downloading the official .deb from gitlab-org/cli releases.'
  download_url=$(github_latest_asset_url gitlab-org/cli "_${arch}.deb")
  if [ -z "$download_url" ]; then
    printf 'glab: could not find a GitHub release .deb for arch %s; install it manually.\n' "$arch" >&2
    return 1
  fi

  deb_path=$(mktemp --suffix=.deb)
  curl -fsSL "$download_url" -o "$deb_path"
  sudo dpkg -i "$deb_path"
  rm -f "$deb_path"
}

install_zsh_history_substring_search() {
  local plugin_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-plugins/zsh-history-substring-search"

  if [ -d "$plugin_dir" ]; then
    log "zsh-history-substring-search already cloned at $plugin_dir; skipped."
    return
  fi

  log 'zsh-history-substring-search is not packaged for Debian; cloning the upstream repo.'
  mkdir -p "$(dirname "$plugin_dir")"
  git clone --depth 1 https://github.com/zsh-users/zsh-history-substring-search "$plugin_dir"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log 'docker already available; installation is skipped.'
    return
  fi

  local keyring=/etc/apt/keyrings/docker.asc
  local sources_file=/etc/apt/sources.list.d/docker.sources

  log 'configuring the official Docker apt repository.'
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o "$keyring"
  sudo chmod a+r "$keyring"
  {
    printf 'Types: deb\n'
    printf 'URIs: https://download.docker.com/linux/debian\n'
    # shellcheck disable=SC1091 # sourcing the live system's os-release, not a repo file
    printf 'Suites: %s\n' "$(. /etc/os-release && echo "$VERSION_CODENAME")"
    printf 'Components: stable\n'
    printf 'Architectures: %s\n' "$(dpkg --print-architecture)"
    printf 'Signed-By: %s\n' "$keyring"
  } | sudo tee "$sources_file" >/dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  sudo usermod -aG docker "$USER"
  log 'added your user to the docker group; log out and back in (or run `newgrp docker`) for this to take effect.'
}

install_ghostty() {
  if command -v ghostty >/dev/null 2>&1; then
    log 'ghostty already available; installation is skipped.'
    return
  fi

  log 'ghostty has no official Debian package; running the community-maintained installer (mkasberg/ghostty-ubuntu, not signed by Ghostty upstream).'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
}

install_nerd_font() {
  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
  local marker="$font_dir/.installed"

  if [ -f "$marker" ]; then
    log 'JetBrains Mono Nerd Font already installed; skipped.'
    return
  fi

  log 'downloading JetBrains Mono Nerd Font.'
  local archive_path
  archive_path=$(mktemp --suffix=.tar.xz)
  curl -fLo "$archive_path" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
  mkdir -p "$font_dir"
  tar -xf "$archive_path" -C "$font_dir"
  rm -f "$archive_path"
  touch "$marker"
  fc-cache -f "$font_dir" >/dev/null
}

install_core_apt_packages
install_eza
install_git_delta
install_starship
install_mise
install_gh
install_glab
install_zsh_history_substring_search
install_docker
install_ghostty
install_nerd_font

log "apt-based tool installation complete (see $ROOT_DIR/README.md for what each step did)."
