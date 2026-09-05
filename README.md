# Dotfiles

[![CI](https://github.com/rizalord/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/rizalord/dotfiles/actions/workflows/ci.yml)

Portable configuration for **zsh**, **Git**, a modern terminal, a set of
developer CLIs, and a Docker workflow — for macOS (Colima-backed) and Ubuntu
Linux (native Docker Engine).

The guiding rule: **shared configuration lives in this repository; secrets,
your Git identity, and machine-specific settings never do.** A small install
script symlinks the tracked files into place and backs up whatever was there
before.

---

## Table of contents

- [What you get](#what-you-get)
- [Requirements](#requirements)
- [Ubuntu/Linux notes](#ubuntulinux-notes)
- [Install](#install)
- [What the installer links](#what-the-installer-links)
- [First-run setup (SSH, Git identity, sign-in)](#first-run-setup)
- [Living in the shell](#living-in-the-shell)
- [Local, per-machine overrides](#local-per-machine-overrides)
- [Optional: macOS system defaults](#optional-macos-system-defaults)
- [Optional: macOS-style GNOME desktop (Ubuntu)](#optional-macos-style-gnome-desktop-ubuntu)
- [Updating](#updating)
- [Undo: restoring from a backup](#undo-restoring-from-a-backup)
- [How it stays safe](#how-it-stays-safe)
- [Development](#development)
- [License](#license)

---

## What you get

| Area | Highlights |
| --- | --- |
| **Terminal** | [Ghostty](https://ghostty.org) config + JetBrainsMono Nerd Font, light/dark auto theme |
| **Prompt** | [Starship](https://starship.rs) — directory, Git state, runtime versions, command duration |
| **Shell** | autosuggestions, syntax highlighting, history-substring search, cached completion, `fzf` bindings |
| **Listing / paging** | `eza` aliases, `bat` man pages, `delta` for Git diffs |
| **Runtimes** | [`mise`](https://mise.jdx.dev) pins Node and [Bun](https://bun.sh) (both `latest`) globally, and manages other languages too — no global Homebrew Node |
| **Containers** | Docker CLI with Buildx and Compose wired up — via Colima on macOS, native Docker Engine on Ubuntu |
| **Greeting** | `fastfetch` system summary on a new terminal (toggleable) |
| **Safety** | idempotent installer, timestamped backups, secret/path scanner, CI on every push |

Everything is plain files and a POSIX shell script. No dotfile framework
(no chezmoi, no GNU Stow).

---

## Requirements

Two supported platforms, each with its own package manager — pick the one
that matches your machine:

- **macOS** (Apple Silicon or Intel), via **[Homebrew](https://brew.sh)**:

  ```sh
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

- **Ubuntu** 22.04 (jammy) or 24.04 (noble), via **apt**. Nothing extra to
  install first — `scripts/install-tools.sh` drives `apt-get` itself (with
  `sudo`). See [Ubuntu/Linux notes](#ubuntulinux-notes) for what that
  involves and where a couple of tools fall back to the vendor's own
  installer instead of a plain apt package.

Either way you also need **Git** and **zsh** (both are already present on a
default install of either OS).

---

## Ubuntu/Linux notes

[`scripts/install-apt.sh`](scripts/install-apt.sh) is what
`scripts/install-tools.sh` runs on Ubuntu instead of `brew bundle`. It's
idempotent (skips anything already on your `PATH`) and, like the Homebrew
path, installs software automatically — no separate confirmation step. Being
transparent about *where* each tool comes from, in the same spirit as
[How it stays safe](#how-it-stays-safe):

- **Plain apt packages**: `bat`, `fd`, `fzf`, `jq`, `ripgrep`, `shellcheck`,
  `zoxide`, `zsh-autosuggestions`, `zsh-syntax-highlighting`. (Ubuntu names
  `bat`/`fd`'s binaries `batcat`/`fdfind`; the script symlinks the familiar
  names into `~/.local/bin`.)
- **Apt first, official GitHub Release as fallback**: `eza`, `git-delta`, and
  `fastfetch` aren't guaranteed to be on every supported Ubuntu release's apt
  repo (`fastfetch` isn't on 24.04's at all). If apt doesn't have them, the
  script downloads the binary/`.deb` straight from the project's own GitHub
  Releases — never a third-party apt repo.
- **Official vendor install script**: `mise` and `starship` (when apt lacks
  the latter) come from `mise.jdx.dev`/`starship.rs`'s own first-party
  installer scripts.
- **Official apt repo added by the script**: `gh` (cli.github.com) and Docker
  Engine (docs.docker.com, Ubuntu repo) — both add a signed apt source the
  same way their own docs do.
- **Official release, no apt repo exists**: `glab` — GitLab doesn't publish
  an apt repo, and its GitHub mirror carries no Release assets either, so the
  script fetches the `.deb` straight from GitLab's own release API
  (`gitlab.com/gitlab-org/cli`).
- **Not packaged for Ubuntu at all**: `zsh-history-substring-search` is
  `git clone`d once from the upstream `zsh-users` repo (never auto-updated).
- **Community-maintained, not signed by upstream**: **Ghostty** has no
  official Ubuntu package, so the script runs the well-known
  `mkasberg/ghostty-ubuntu` installer. This is the one step that isn't from
  the tool's own maintainers — worth knowing before you run it.

Docker Engine on Ubuntu runs natively (no Colima); the script adds your user
to the `docker` group, so log out and back in (or run `newgrp docker`) once
before using `docker` without `sudo`.

---

## Install

```sh
# 1. Clone the repo (any location works; this is just a common choice)
git clone git@github.com:rizalord/dotfiles.git "$HOME/src/dotfiles"
cd "$HOME/src/dotfiles"

# 2. Preview what will change — nothing is written yet
./install.sh --dry-run

# 3. Create the symlinks (existing files are backed up first)
./install.sh

# 4. Install the CLI tools and apps (Homebrew on macOS, apt on Ubuntu)
./scripts/install-tools.sh

# 5. On Ubuntu, make zsh your login shell (macOS has defaulted to zsh
#    since Catalina, so this is a no-op there — skip it)
chsh -s "$(command -v zsh)"

# 6. Start a fresh login shell so the new PATH and plugins load
exec zsh -l

# 7. Verify everything
./scripts/check.sh --installed --strict-tools
```

**What each step does**

- `install.sh` only manages symlinks, backups, and one Git `include` line. It
  never installs software, logs in anywhere, or touches the network.
- `scripts/install-tools.sh` runs `brew bundle` against the
  [`Brewfile`](Brewfile) on macOS, or
  [`scripts/install-apt.sh`](scripts/install-apt.sh) on Ubuntu (see
  [Ubuntu/Linux notes](#ubuntulinux-notes)). Either way it sets up Node and
  Bun through `mise`, configures the Docker CLI plugins, and installs the
  optional Codex / Claude Code / opencode CLIs only if they are missing —
  never signs in to anything.
- Step 5 only matters on Ubuntu, where the default login shell is `bash`.
  Skipping it means every *new* terminal window keeps opening `bash` instead
  of `zsh` — the prompt, aliases, and the `fastfetch` greeting all live in
  the zsh config, so none of them would ever run. `chsh` asks for your
  account password and edits `/etc/passwd`; it only affects shells started
  after it runs, which is exactly what step 6 does for your current session.
- Step 6 matters because the installer runs in a child process — it cannot
  change your current shell's `PATH`. A new login shell re-reads the config
  and sees the tools.

The installer is safe to re-run. Links that already point at your checkout
are left alone; anything else in the way is moved to a timestamped backup
(see [Undo](#undo-restoring-from-a-backup)) before the symlink is created.

---

## What the installer links

| Repository file | Symlinked to |
| --- | --- |
| `zsh/.zshrc` | `~/.zshrc` |
| `zsh/.zprofile` | `~/.zprofile` |
| `git/.gitconfig` | `~/.config/git/dotfiles.gitconfig` (added via `include.path`) |
| `git/.gitignore_global` | `~/.config/git/ignore` |
| `starship/starship.toml` | `~/.config/starship.toml` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `fastfetch/config.jsonc` | `~/.config/fastfetch/config.jsonc` |
| `ssh/config` | `~/.ssh/config` (and `~/.ssh` is tightened to `700`) |

Your existing global Git config keeps its own identity and settings — the
shared preferences are pulled in through a single `include.path` line, so
`git config --global user.name` still wins.

If you set a custom `XDG_CONFIG_HOME`, the Git files and include move under
that directory. The shared `core.excludesFile` still points at
`~/.config/git/ignore`, so in that case set it explicitly once:

```sh
git config --global core.excludesFile "$XDG_CONFIG_HOME/git/ignore"
```

---

## First-run setup

The installer deliberately does **not** create keys or sign you in. Do these
once per machine.

### 1. SSH key

Use your existing `~/.ssh/id_ed25519`, or create one:

```sh
SSH_KEY="$HOME/.ssh/id_ed25519"
[ -f "$SSH_KEY" ] || { umask 077; ssh-keygen -t ed25519 -f "$SSH_KEY" -C "you@example.com"; }
```

On macOS, load it into the agent and Apple keychain, then copy the public key:

```sh
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain "$SSH_KEY"
pbcopy < "$SSH_KEY.pub"
```

The managed `~/.ssh/config` sets `AddKeysToAgent` and `UseKeychain` (guarded
by `IgnoreUnknown` so the file is still valid on Linux), keepalives, and
`HashKnownHosts`. It contains **no hosts and no secrets**. Put machine-specific
`Host` blocks and `IdentityFile` lines in `~/.ssh/config.local` — the managed
file `Include`s it and it is never tracked here.

Add the public key to your Git hosts, then test:

```sh
ssh -T git@github.com
ssh -T git@gitlab.com
```

### 2. Git identity

Kept out of the repo on purpose. Set it in your global config:

```sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

### 3. Sign in to CLIs (as needed)

```sh
gh auth login
glab auth login
codex login
claude login
opencode auth login
```

Tokens stay in each tool's own credential store.

### 4. VS Code `code` command

In VS Code, open the Command Palette and run
**Shell Command: Install 'code' command in PATH**. `check.sh` treats `code`
as optional.

---

## Living in the shell

After `exec zsh -l` you have:

- **Starship prompt** — two lines: path + Git status, then runtime versions
  and the `❯` character (green on success, red on failure).
- **Autosuggestions** — fish-style grey completion from history; press `→` to
  accept.
- **Syntax highlighting** as you type.
- **History-substring search** — type a prefix, then `↑` / `↓` (or
  `Ctrl-P` / `Ctrl-N`) to walk matching commands.
- **Smart completion** — case-insensitive, menu-selectable, cached (`compinit`
  runs its full security check at most once a day, so shells start fast).
- **`fzf`** — `Ctrl-T` (files), `Ctrl-R` (history), `Alt-C` (cd), backed by
  `fd`.
- **`eza` aliases** — `ls`, `ll`, `la`, `lt` (tree), with icons and Git status.
- **`bat`** as the man-page pager.
- **`Ctrl-X Ctrl-E`** — open the current command line in `$EDITOR`.
- **`fastfetch`** greeting on a new top-level shell. Skipped for nested and
  non-interactive shells; disable it with `DOTFILES_NO_FASTFETCH=1` in
  `~/.config/zsh/local.zsh`.

**Git** uses `delta` as its pager and diff filter, plus sensible defaults
(`pull.rebase`, `fetch.prune`, `push.autoSetupRemote`, `rerere`, `zdiff3`
conflict style, histogram diff) and short aliases (`co`, `ci`, `st`, `lg`,
`last`, `unstage`, `amend`).

**Containers** on macOS run through Colima:

```sh
colima start
docker run --rm hello-world
docker compose version
```

**Runtimes** are managed by `mise`. `scripts/install-tools.sh` already pins
Node and Bun globally to `latest`; add another language the same way:

```sh
mise use --global python@latest
```

---

## Local, per-machine overrides

Nothing machine-specific belongs in the repo. Three escape hatches:

| File (not tracked) | Use it for |
| --- | --- |
| `~/.config/zsh/local.zsh` | local `PATH`, env vars, aliases; sourced if present |
| `~/.ssh/config.local` | private hosts, jump boxes, per-host `IdentityFile` |
| global Git config | your name, email, signing key, credential helper |

---

## Optional: macOS system defaults

[`scripts/macos-defaults.sh`](scripts/macos-defaults.sh) is **opt-in** — the
installer never runs it. It applies developer-friendly `defaults`: fast key
repeat, no press-and-hold accent popup, disabled text substitutions, Finder
tweaks (extensions, path bar, list view, folders first), shadowless PNG
screenshots in `~/Screenshots`, and a faster auto-hiding Dock.

```sh
./scripts/macos-defaults.sh --dry-run   # show what would change
./scripts/macos-defaults.sh             # apply, then restart Finder/Dock
```

It refuses to run off macOS, and every setting is reversible with
`defaults delete` or the matching System Settings toggle.

---

## Optional: macOS-style GNOME desktop (Ubuntu)

[`scripts/gnome-macos-theme.sh`](scripts/gnome-macos-theme.sh) is **opt-in** —
the installer never runs it. It gives Ubuntu's GNOME desktop a macOS-like
look and feel: the [WhiteSur](https://github.com/vinceliuice/WhiteSur-gtk-theme)
GTK/icon/cursor themes; the User Themes and Blur my Shell GNOME Shell
extensions (installed straight from extensions.gnome.org); the Dash to Dock
extension too, unless a compatible dock is already present — stock Ubuntu
ships its own fork of it (`ubuntu-dock`) pre-enabled, so the script
configures that one instead of installing a conflicting second dock;
[Ulauncher](https://ulauncher.io) as a Spotlight-like launcher (`Ctrl+Space`
by default; set it to `Super+Space` in its preferences after first launch);
and the Inter font as a free SF Pro stand-in. It reads your current
light/dark preference and applies the matching WhiteSur variant.

```sh
./scripts/gnome-macos-theme.sh --dry-run   # show what would change
./scripts/gnome-macos-theme.sh             # apply
```

It refuses to run without GNOME Shell. Log out and back in afterwards so
GNOME Shell picks up the new extensions, then confirm all three are enabled
in the Extensions app. Everything it changes is reversible: `gsettings
reset-recursively org.gnome.desktop.interface`, disabling/removing the
extensions in the Extensions app, and deleting
`~/.local/share/dotfiles-gnome-theme-src`.

---

## Updating

```sh
cd "$HOME/src/dotfiles"
git pull --rebase origin main
./install.sh              # pick up any new managed files
./scripts/install-tools.sh   # pick up Brewfile changes
```

---

## Undo: restoring from a backup

When the installer replaces a file, the original is moved to:

```
~/.local/state/dotfiles-backups/<YYYYMMDD-HHMMSS>-<pid>-<attempt>/
```

Backups are never deleted automatically. To restore, for example, `~/.zshrc`:

```sh
# 1. Find the backup
find "$HOME/.local/state/dotfiles-backups" -name .zshrc -print

# 2. Restore it, but only if ~/.zshrc is still our symlink
BACKUP="$HOME/.local/state/dotfiles-backups/<dir>/.zshrc"
DOTFILES_ROOT="$HOME/src/dotfiles"   # adjust if cloned elsewhere
if [ -L "$HOME/.zshrc" ] && [ "$(readlink "$HOME/.zshrc")" = "$DOTFILES_ROOT/zsh/.zshrc" ]; then
  unlink "$HOME/.zshrc"
  mv "$BACKUP" "$HOME/.zshrc"
else
  echo "refusing to touch an unexpected ~/.zshrc" >&2
fi
```

To fully opt out, `unlink` each managed symlink listed
[above](#what-the-installer-links), restore the backups you want, and remove
the `include.path` line from your global Git config.

---

## How it stays safe

- **No secrets in the repo.** [`git/.gitconfig`](git/.gitconfig) has no
  identity, signing key, or credential helper. [`ssh/config`](ssh/config) has
  no hosts. There are no tokens or private keys anywhere.
- **`.gitignore`** blocks `.env*`, `*.pem`, `*.key`, SSH private keys,
  `*.local`, `*.secret(s)`, tool state dirs (`.claude/`, `.codex/`,
  `.docker/`, `.colima/`), and local Compose overrides.
- **`scripts/check.sh`** scans every tracked file for API-key patterns,
  private-key headers, and personal absolute paths, and fails if it finds
  one.
- **CI** runs `shellcheck` and the full test suite on every push and pull
  request.
- `install.sh` and the test runner never touch the network or sign in to
  anything; `scripts/install-tools.sh` does fetch packages (Homebrew/apt and
  the vendor installers listed in [Ubuntu/Linux notes](#ubuntulinux-notes)),
  but it never touches this repo's own Git remotes or logs in to a service on
  your behalf.

---

## Development

```sh
./scripts/check.sh                 # static checks: syntax, Git config, secret scan
./scripts/check.sh --installed     # also verify the live symlinks
./scripts/test.sh                  # full suite (temporary HOME, no network)
shellcheck install.sh scripts/*.sh tests/*.sh
```

- Tests live in [`tests/`](tests) and run against a throwaway `HOME`.
- [`.github/workflows/ci.yml`](.github/workflows/ci.yml): `shellcheck` on
  `ubuntu-latest`, then `./scripts/test.sh` on `macos-latest` (the suite
  exercises Homebrew, Docker, and zsh, so it targets macOS). The Ubuntu code
  paths in `install-tools.sh`/`install-apt.sh` are exercised by the same
  suite through a faked `uname`/`apt-get`/`dpkg` on the macOS runner, rather
  than a real `apt-get` run.
- [`.shellcheckrc`](.shellcheckrc) documents each repo-wide lint exception.

### Two-remote workflow

GitHub `origin` is primary; GitLab is an explicit mirror.

```sh
git remote add gitlab git@gitlab.com:rizalord/dotfiles.git   # one time
git push origin main
git push gitlab main
```

---

## License

[MIT](LICENSE) © Ahmad Khamdani
