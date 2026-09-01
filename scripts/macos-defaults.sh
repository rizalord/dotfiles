#!/usr/bin/env bash
# Opt-in macOS system defaults for a developer machine.
#
# This script is NOT run by install.sh. Review it, then run it yourself:
#   ./scripts/macos-defaults.sh            # apply
#   ./scripts/macos-defaults.sh --dry-run  # print what would change
#
# Every setting here is reversible with `defaults delete` or the matching
# System Settings toggle.
set -euo pipefail

if [ "$(uname -s)" != Darwin ]; then
  printf 'macos-defaults: this script only runs on macOS.\n' >&2
  exit 1
fi

DRY_RUN=false
case "${1:-}" in
  '') ;;
  --dry-run) DRY_RUN=true ;;
  *)
    printf 'Usage: %s [--dry-run]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

run() {
  if [ "$DRY_RUN" = true ]; then
    printf '+ %s\n' "$*"
  else
    "$@"
  fi
}

printf 'Applying macOS defaults (keyboard, text, Finder, screenshots, Dock)...\n'

# Keyboard: fast key repeat and no press-and-hold accent popover.
run defaults write NSGlobalDomain KeyRepeat -int 2
run defaults write NSGlobalDomain InitialKeyRepeat -int 15
run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Text: turn off substitutions that fight with writing code.
run defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Finder: extensions, path bar, status bar, POSIX path in title, list view,
# folders first, search the current folder, no .DS_Store on network/USB volumes.
run defaults write NSGlobalDomain AppleShowAllExtensions -bool true
run defaults write com.apple.finder ShowPathbar -bool true
run defaults write com.apple.finder ShowStatusBar -bool true
run defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
run defaults write com.apple.finder FXPreferredViewStyle -string 'Nlsv'
run defaults write com.apple.finder _FXSortFoldersFirst -bool true
run defaults write com.apple.finder FXDefaultSearchScope -string 'SCcf'
run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
run defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Save and print panels expanded by default.
run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Screenshots: PNG, no window shadow, saved to ~/Screenshots.
run mkdir -p "$HOME/Screenshots"
run defaults write com.apple.screencapture location -string "$HOME/Screenshots"
run defaults write com.apple.screencapture type -string 'png'
run defaults write com.apple.screencapture disable-shadow -bool true

# Dock: autohide instantly, no recent-apps section, no auto space reordering.
run defaults write com.apple.dock autohide -bool true
run defaults write com.apple.dock autohide-delay -float 0
run defaults write com.apple.dock autohide-time-modifier -float 0.15
run defaults write com.apple.dock show-recents -bool false
run defaults write com.apple.dock mru-spaces -bool false

# Reveal the ~/Library folder.
run chflags nohidden "$HOME/Library"

if [ "$DRY_RUN" = true ]; then
  printf '\nDry run only; nothing was changed.\n'
  exit 0
fi

for app in Finder Dock SystemUIServer; do
  killall "$app" >/dev/null 2>&1 || true
done

printf '\nDone. A few settings need a logout or restart to take full effect.\n'
