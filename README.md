# Dotfiles Foundation

Portable, macOS-first dotfiles for zsh, Git, developer CLI tools, and a
Colima-backed Docker workflow. Shared configuration is kept in this
repository; credentials, Git identity, and machine-specific overrides stay
outside it.

## Quick start

The supported first setup on macOS is:

```sh
git clone git@github.com:rizalord/dotfiles.git "$HOME/src/dotfiles"
cd "$HOME/src/dotfiles"
./install.sh --dry-run
./install.sh
./scripts/install-tools.sh
```

After the tool installer returns, open a new zsh login shell before
continuing (for example, run `exec zsh -l`), or refresh the relevant PATH
entries manually. The installer runs as a child process, so exports it makes
cannot update the parent shell's PATH; a new login shell rereads the zsh
configuration and sees the installed tools. In the new shell, run:

```sh
./scripts/check.sh --installed --strict-tools
```

`--dry-run` prints the installer plan without creating links, backups, or
Git configuration. The installer is safe to run again: managed links that
already point at this checkout are kept as-is, while other existing targets
are moved to a timestamped backup before replacement.

The tool installer uses Homebrew on macOS, manages Node.js with `mise`, and
does not log in to any service. It installs the optional Codex and Claude Code
CLIs only when they are missing. Node is deliberately not installed as a
global Homebrew formula.

## Runtime tools

Use `mise` for language runtimes and versions. For example:

```sh
mise use --global node@lts
```

On macOS, Colima is the container runtime used by the Docker CLI. Start it
when you need containers, then verify Docker and Compose:

```sh
colima start
docker run --rm hello-world
docker compose version
```

Linux can use the shell and Git portions of this repository, but the
Homebrew bundle is skipped there. Docker Engine and Portainer provisioning
are intentionally outside this foundation because Linux setup depends on the
distribution's package manager, systemd, firewall, and root permissions.

## Authentication and local settings

The expected default SSH authentication key is `~/.ssh/id_ed25519`. The
installer does not create keys, copy private keys, or copy credential stores.
Handle SSH authentication manually after installation. If the default key
already exists, use it; generate one only when it is absent:

```sh
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  umask 077
  ssh-keygen -t ed25519 -f "$SSH_KEY" -C "you@example.com"
fi
if [ ! -f "$SSH_KEY.pub" ]; then
  ssh-keygen -y -f "$SSH_KEY" > "$SSH_KEY.pub"
fi
```

On macOS, add the key to the Apple keychain, copy the public key, and add it
to the SSH keys page for each service:

```sh
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain "$SSH_KEY"
pbcopy < "$SSH_KEY.pub"
```

Paste the copied key into GitHub **Settings → SSH and GPG keys** and GitLab
**Preferences/Settings → SSH Keys**, then test both connections:

```sh
ssh -T git@github.com
ssh -T git@gitlab.com
```

The installer remains non-authenticated and never runs these commands.

After the tools are installed, authenticate manually when needed:

```sh
gh auth login
glab auth login
codex login
claude login
```

These commands are intentionally not run by the installer and any tokens stay
in each tool's normal local credential storage.

To register the VS Code `code` command, open VS Code's Command Palette and
run **Shell Command: Install 'code' command in PATH**. The checker treats
`code` as an optional command.

Machine-specific zsh settings belong in
`~/.config/zsh/local.zsh`. This file is sourced only when it exists and is
not tracked by the repository. Use it for local PATH entries, environment
variables, or aliases that should not become shared configuration.

Git identity also remains local to the machine, outside the shared
`git/.gitconfig`. Set it in the user's global Git config, for example:

```sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

The shared preferences are included through
`~/.config/git/dotfiles.gitconfig`; they contain no identity, signing key, or
credential helper.

With a custom `XDG_CONFIG_HOME`, the installer puts its Git symlinks and
include at `$XDG_CONFIG_HOME/git/dotfiles.gitconfig` and
`$XDG_CONFIG_HOME/git/ignore`. The shared config's
`core.excludesFile` intentionally remains `~/.config/git/ignore`, so custom
XDG users must set the global excludes file explicitly after installation:

```sh
git config --global core.excludesFile "$XDG_CONFIG_HOME/git/ignore"
```

## Recovery and verification

When the installer replaces an existing file, it preserves the old item under
`~/.local/state/dotfiles-backups/` in a directory named
`<YYYYMMDD-HHMMSS>-<pid>-<attempt>` (for example,
`20260830-120000-24187-0`). To recover `.zshrc`, first inspect the backups.
Before unlinking anything, verify that `.zshrc` is still the expected
managed symlink to this checkout. Then move the desired backup back into
place:

```sh
find "$HOME/.local/state/dotfiles-backups" -name .zshrc -print
BACKUP_DIR="$HOME/.local/state/dotfiles-backups/<YYYYMMDD-HHMMSS>-<pid>-<attempt>"
DOTFILES_ROOT="$HOME/src/dotfiles"  # adjust if this checkout is elsewhere
if [ -L "$HOME/.zshrc" ] \
  && [ "$(readlink "$HOME/.zshrc")" = "$DOTFILES_ROOT/zsh/.zshrc" ]; then
  unlink "$HOME/.zshrc"
else
  printf 'refusing to unlink unexpected ~/.zshrc\n' >&2
  exit 1
fi
test -f "$BACKUP_DIR/.zshrc"
mv "$BACKUP_DIR/.zshrc" "$HOME/.zshrc"
```

Replace the angle-bracket placeholders in `BACKUP_DIR` with the actual
directory selected from `find`. Do not remove a backup until the restored
file has been checked. The installer does not automatically remove backup
data.

Useful read-only and inspection commands are:

```sh
./install.sh --dry-run
./scripts/check.sh
./scripts/check.sh --installed
./scripts/check.sh --installed --strict-tools
./scripts/test.sh
```

Without `--strict-tools`, unavailable optional commands are reported as
warnings. `--strict-tools` makes missing tools fail the check. The test
runner is network-free, uses a temporary `HOME` and Git config, and removes
that temporary state when it exits.

## Two-remote workflow

Keep GitHub as the primary `origin`. Add the GitLab mirror once if it is not
already configured:

```sh
git remote add gitlab git@gitlab.com:rizalord/dotfiles.git
```

Synchronize and publish explicitly to each remote:

```sh
git pull --rebase origin main
git push origin main
git push gitlab main
```

The installer and test runner never pull, push, or log in automatically.
