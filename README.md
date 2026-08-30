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
Create or register a key separately, then test the relevant SSH connection.

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

## Recovery and verification

When the installer replaces an existing file, it preserves the old item under
`~/.local/state/dotfiles-backups/` in a timestamped directory. To recover a
file, inspect the backup, remove the managed symlink, and move the desired
backup back into place. For example:

```sh
find "$HOME/.local/state/dotfiles-backups" -name .zshrc -print
rm "$HOME/.zshrc"
mv "$HOME/.local/state/dotfiles-backups/<timestamp>/.zshrc" "$HOME/.zshrc"
```

Do not delete a backup until the restored file has been checked. The
installer does not automatically remove backup data.

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
