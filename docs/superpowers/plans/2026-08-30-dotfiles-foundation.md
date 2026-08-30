# Dotfiles Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mengubah repository minimal ini menjadi dotfiles macOS-first yang aman, portable, idempotent, terdokumentasi, dan dapat memasang serta memverifikasi tool developer termasuk GitHub CLI, GitLab CLI, Codex CLI, Claude Code CLI, dan VS Code CLI.

**Architecture:** Gunakan shell script native dengan symlink terkelola dan backup bertimestamp; tidak memakai framework dotfiles tambahan. Konfigurasi bersama dipisahkan dari override lokal, sedangkan Git identity dan seluruh kredensial tetap di luar repository. Homebrew menangani tool macOS, dan npm dengan prefix $HOME/.local menangani AI CLI yang belum tersedia.

**Tech Stack:** zsh, POSIX-compatible shell, Bash test harness, Git config, Homebrew Bundle, npm, macOS arm64, guard ringan untuk Linux.

**Spec:** docs/superpowers/specs/2026-08-30-dotfiles-foundation-design.md

## Global Constraints

- Target utama adalah macOS dengan zsh; bagian yang tidak spesifik macOS diberi guard agar tetap dapat dipakai di Linux.
- Menggunakan shell script native dan symlink terkelola, tanpa framework dotfiles tambahan seperti chezmoi atau GNU Stow.
- Installer harus idempotent dan aman dijalankan berulang kali.
- Jika tujuan sudah berisi file atau symlink lain, memindahkannya ke backup bertimestamp di ~/.local/state/dotfiles-backups/; tidak menghapus data.
- Menyediakan mode --dry-run untuk inspeksi tanpa perubahan.
- Tidak ada API key, token, hostname internal, atau path /Users/... yang ditulis di konfigurasi bersama.
- Installer tidak menjalankan login GitHub/GitLab, tidak membuat SSH key, dan tidak menyalin credential store.
- Codex CLI dan Claude Code CLI dipasang hanya jika belum ada; proses tidak pernah meminta atau menyimpan token.
- Test berjalan tanpa network dan tanpa mengubah home directory pengguna.
- Remote utama tetap origin (GitHub), sedangkan GitLab menjadi mirror eksplisit melalui git push gitlab main.
- Perubahan lokal yang sudah ada pada zsh/.zprofile harus dipertahankan maknanya dan diubah dari absolute path menjadi $HOME/.local/bin.

---

## File map

- Create .gitignore — mengecualikan secret, local override, cache, log, private key, dan artefak OS.
- Create Brewfile — daftar formula Homebrew macOS untuk tool developer dan dependency Node.
- Create git/.gitconfig — preference Git lintas mesin tanpa identity atau credential.
- Create git/.gitignore_global — global ignore untuk artefak editor dan OS yang aman diabaikan.
- Modify zsh/.zprofile — login environment yang portable dan guarded.
- Modify zsh/.zshrc — interactive shell, history, completion, alias, dan integrasi opsional.
- Create install.sh — entry point symlink, backup, Git include, dan dry-run.
- Create scripts/install-tools.sh — pemasangan Homebrew bundle dan AI CLI tanpa login.
- Create scripts/check.sh — pemeriksaan syntax, link, Git config, dan tool.
- Create scripts/test.sh — runner untuk seluruh test lokal.
- Create tests/test_repository.sh — test hygiene dan manifest.
- Create tests/test_zsh.sh — test syntax dan perilaku local override Zsh.
- Create tests/test_git.sh — test preference Git dan global ignore.
- Create tests/test_installer.sh — test dry-run, backup, symlink, dan idempotency di temporary HOME.
- Create tests/test_tools.sh — test syntax dan dry-run tool installer/checker.
- Create README.md — quick start, recovery, authentication manual, VS Code CLI, dan dual-remote workflow.

---

### Task 1: Repository hygiene dan test harness dasar

**Files:**
- Create .gitignore
- Create Brewfile
- Create git/.gitignore_global
- Create tests/test_repository.sh

**Interfaces:**
- Produces: daftar file dasar dan aturan ignore yang dipakai task berikutnya.
- Consumes: tidak ada file project selain struktur Git yang sudah ada.

- [ ] Step 1: Tulis failing test untuk manifest dan hygiene

Buat tests/test_repository.sh dengan isi berikut:

    #!/usr/bin/env bash
    set -euo pipefail

    ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

    assert_file() {
      test -f "$1" || { echo "missing file: $1" >&2; exit 1; }
    }

    assert_contains() {
      grep -Fq -- "$2" "$1" || { echo "missing text '$2' in $1" >&2; exit 1; }
    }

    assert_file "$ROOT_DIR/.gitignore"
    assert_file "$ROOT_DIR/Brewfile"
    assert_file "$ROOT_DIR/git/.gitignore_global"
    assert_contains "$ROOT_DIR/.gitignore" ".env"
    assert_contains "$ROOT_DIR/.gitignore" "*.pem"
    assert_contains "$ROOT_DIR/.gitignore" ".codex/"
    assert_contains "$ROOT_DIR/.gitignore" ".claude/"
    assert_contains "$ROOT_DIR/Brewfile" 'brew "gh"'
    assert_contains "$ROOT_DIR/Brewfile" 'brew "glab"'
    assert_contains "$ROOT_DIR/Brewfile" 'brew "node"'
    assert_contains "$ROOT_DIR/git/.gitignore_global" ".DS_Store"

    echo "repository hygiene: PASS"

- [ ] Step 2: Jalankan test untuk memastikan ia gagal sebelum implementasi

Run: bash tests/test_repository.sh

Expected: FAIL karena file manifest belum dibuat.

- [ ] Step 3: Buat file manifest dan aturan ignore minimal

.gitignore harus mengecualikan .env, .env.* kecuali .env.example, *.local,
*.secret, *.secrets, *.pem, *.key, private key SSH, .codex/, .claude/,
log, cache, .DS_Store, dan file swap editor.

Brewfile harus berisi formula berikut:

    brew "bat"
    brew "fd"
    brew "fzf"
    brew "gh"
    brew "glab"
    brew "git"
    brew "jq"
    brew "node"
    brew "ripgrep"
    brew "shellcheck"
    brew "starship"
    brew "zoxide"

git/.gitignore_global minimal berisi .DS_Store, .AppleDouble, .LSOverride,
._*, *.swp, *.swo, dan .idea/.

- [ ] Step 4: Jalankan test untuk memastikan ia lulus

Run: bash tests/test_repository.sh

Expected: PASS dengan output repository hygiene: PASS.

- [ ] Step 5: Commit perubahan task

    git add .gitignore Brewfile git/.gitignore_global tests/test_repository.sh
    git commit -m "chore: add repository hygiene and tool manifest"

---

### Task 2: Zsh portable, interactive, dan override lokal

**Files:**
- Modify zsh/.zprofile
- Modify zsh/.zshrc
- Create tests/test_zsh.sh

**Interfaces:**
- Produces: .zprofile aman untuk login shell dan .zshrc aman untuk interactive shell.
- Consumes: $HOME, XDG_CONFIG_HOME, dan command opsional brew, fzf, zoxide, starship.

- [ ] Step 1: Tulis failing test untuk syntax, guard, dan local override

Buat tests/test_zsh.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
    assert_contains() { grep -Fq -- "$2" "$1" || exit 1; }

    zsh -n "$ROOT_DIR/zsh/.zprofile"
    zsh -n "$ROOT_DIR/zsh/.zshrc"
    assert_contains "$ROOT_DIR/zsh/.zprofile" "brew shellenv"
    assert_contains "$ROOT_DIR/zsh/.zprofile" '$HOME/.local/bin'
    assert_contains "$ROOT_DIR/zsh/.zshrc" '[[ -o interactive ]] || return'
    assert_contains "$ROOT_DIR/zsh/.zshrc" 'local.zsh'

    TMP_HOME=$(mktemp -d)
    trap 'rm -rf -- "$TMP_HOME"' EXIT
    mkdir -p "$TMP_HOME/.config/zsh"
    printf 'export DOTFILES_TEST_MARKER=loaded\n' > "$TMP_HOME/.config/zsh/local.zsh"

    OUTPUT=$(HOME="$TMP_HOME" \
      XDG_CONFIG_HOME="$TMP_HOME/.config" \
      ZDOTDIR="$TMP_HOME" \
      DOTFILES_RC="$ROOT_DIR/zsh/.zshrc" \
      zsh -flic 'source "$DOTFILES_RC"; print -r -- "$DOTFILES_TEST_MARKER"; alias gs' 2>&1)

    grep -Fq loaded <<<"$OUTPUT"
    grep -Fq "git status" <<<"$OUTPUT"
    echo "zsh configuration: PASS"

- [ ] Step 2: Jalankan test untuk memastikan ia gagal

Run: bash tests/test_zsh.sh

Expected: FAIL karena .zshrc masih kosong dan .zprofile masih memakai
absolute Homebrew/Codex assumptions.

- [ ] Step 3: Implementasikan .zprofile portable

Gunakan pola berikut:

    if command -v brew >/dev/null 2>&1; then
      eval "$(brew shellenv)"
    fi

    typeset -U path PATH
    path=("$HOME/.local/bin" $path)

- [ ] Step 4: Implementasikan .zshrc interactive

Isi harus mencakup history yang aman, completion bawaan zsh, bindkey -e,
default EDITOR/VISUAL yang tidak menimpa environment user, alias gs, gd,
gco, gsw, dan glog, serta integrasi guarded:

    [[ -o interactive ]] || return

    if (( $+commands[zoxide] )); then
      eval "$(zoxide init zsh)"
    fi

    if (( $+commands[starship] )); then
      eval "$(starship init zsh)"
    fi

    local_zsh="$XDG_CONFIG_HOME/zsh/local.zsh"
    [[ -n "$XDG_CONFIG_HOME" ]] || local_zsh="$HOME/.config/zsh/local.zsh"
    [[ -r "$local_zsh" ]] && source "$local_zsh"
    unset local_zsh

Integrasi fzf hanya dicoba jika command tersedia dan kegagalannya tidak
membuat shell gagal start. Jangan menulis path /Users/rizalord.

- [ ] Step 5: Jalankan test untuk memastikan ia lulus

Run: bash tests/test_zsh.sh

Expected: PASS dengan output zsh configuration: PASS.

- [ ] Step 6: Commit perubahan task

    git add zsh/.zprofile zsh/.zshrc tests/test_zsh.sh
    git commit -m "feat: add portable zsh configuration"

---

### Task 3: Shared Git config tanpa identity atau credential

**Files:**
- Create git/.gitconfig
- Create tests/test_git.sh

**Interfaces:**
- Produces: shared Git preference yang dipasang melalui include path stabil.
- Consumes: Git config global pengguna tetap berada di luar repository.

- [ ] Step 1: Tulis failing test untuk shared Git config

Buat tests/test_git.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
    CONFIG="$ROOT_DIR/git/.gitconfig"

    test -f "$CONFIG"
    test "$(git config --file "$CONFIG" --get init.defaultBranch)" = main
    test "$(git config --file "$CONFIG" --get pull.rebase)" = true
    test "$(git config --file "$CONFIG" --get fetch.prune)" = true
    test "$(git config --file "$CONFIG" --get push.autoSetupRemote)" = true
    test "$(git config --file "$CONFIG" --get rerere.enabled)" = true
    test "$(git config --file "$CONFIG" --get core.excludesFile)" = "~/.config/git/ignore"
    git config --file "$CONFIG" --get-regexp "^alias\." | grep -Fq "alias.st "
    git config --file "$CONFIG" --get-regexp "^alias\." | grep -Fq "alias.lg "
    if git config --file "$CONFIG" --get-regexp "^user\." >/dev/null 2>&1; then
      echo "shared config must not contain user identity" >&2
      exit 1
    fi

    echo "git configuration: PASS"

- [ ] Step 2: Jalankan test untuk memastikan ia gagal

Run: bash tests/test_git.sh

Expected: FAIL karena shared .gitconfig belum dibuat.

- [ ] Step 3: Buat shared .gitconfig

Gunakan preference init.defaultBranch=main, pull.rebase=true,
fetch.prune=true, push.autoSetupRemote=true, push.followTags=true,
merge.conflictStyle=zdiff3, diff.algorithm=histogram,
diff.colorMoved=zebra, rerere.enabled=true, rerere.autoupdate=true,
branch sort -committerdate, tag sort version:refname, dan
core.excludesFile=~/.config/git/ignore.

Tambahkan alias aman co=switch, ci=commit, st=status --short --branch,
lg=log --oneline --decorate --graph, last=log -1 HEAD --stat,
unstage=restore --staged, dan amend=commit --amend --no-edit.

Jangan menambahkan user identity, signing key, credential helper, atau token.

- [ ] Step 4: Jalankan test untuk memastikan ia lulus

Run: bash tests/test_git.sh

Expected: PASS dengan output git configuration: PASS.

- [ ] Step 5: Commit perubahan task

    git add git/.gitconfig tests/test_git.sh
    git commit -m "feat: add shared git preferences"

---

### Task 4: Installer symlink, backup, Git include, dan dry-run

**Files:**
- Create install.sh
- Create tests/test_installer.sh

**Interfaces:**
- Consumes: repository root dari lokasi install.sh, $HOME, XDG_CONFIG_HOME,
  dan GIT_CONFIG_GLOBAL jika diberikan.
- Produces: symlink ~/.zshrc, ~/.zprofile,
  ~/.config/git/dotfiles.gitconfig, ~/.config/git/ignore, serta global Git
  include ~/.config/git/dotfiles.gitconfig.
- CLI: ./install.sh dan ./install.sh --dry-run; argumen lain keluar dengan
  status non-zero dan pesan usage.

- [ ] Step 1: Tulis integration test yang gagal

Buat tests/test_installer.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
    TMP_HOME=$(mktemp -d)
    trap 'rm -rf -- "$TMP_HOME"' EXIT

    run_installer() {
      HOME="$TMP_HOME" \
      XDG_CONFIG_HOME="$TMP_HOME/.config" \
      GIT_CONFIG_GLOBAL="$TMP_HOME/.gitconfig" \
      bash "$ROOT_DIR/install.sh" "$@"
    }

    run_installer --dry-run
    test ! -e "$TMP_HOME/.zshrc"
    test ! -e "$TMP_HOME/.config/git/dotfiles.gitconfig"

    mkdir -p "$TMP_HOME"
    printf 'legacy zsh\n' > "$TMP_HOME/.zshrc"
    run_installer

    test -L "$TMP_HOME/.zshrc"
    test "$(readlink "$TMP_HOME/.zshrc")" = "$ROOT_DIR/zsh/.zshrc"
    test -L "$TMP_HOME/.zprofile"
    test -L "$TMP_HOME/.config/git/dotfiles.gitconfig"
    test -L "$TMP_HOME/.config/git/ignore"
    test "$(git --no-pager config --global --get-all include.path)" = "~/.config/git/dotfiles.gitconfig"
    find "$TMP_HOME/.local/state/dotfiles-backups" -type f -name ".zshrc" -print -quit | grep -Fq .

    BACKUPS_BEFORE=$(find "$TMP_HOME/.local/state/dotfiles-backups" -type f | wc -l | tr -d " ")
    run_installer
    BACKUPS_AFTER=$(find "$TMP_HOME/.local/state/dotfiles-backups" -type f | wc -l | tr -d " ")
    test "$BACKUPS_BEFORE" = "$BACKUPS_AFTER"

    echo "installer: PASS"

- [ ] Step 2: Jalankan test untuk memastikan ia gagal

Run: bash tests/test_installer.sh

Expected: FAIL karena install.sh belum ada.

- [ ] Step 3: Implementasikan installer minimal yang idempotent

Gunakan set -euo pipefail, resolve ROOT_DIR dari lokasi script, dan fungsi
terpisah log, backup_existing, link_managed_file, ensure_directory,
ensure_git_include, serta parser --dry-run.

link_managed_file harus no-op jika destination sudah benar, membuat parent
directory, memindahkan destination lama ke
$HOME/.local/state/dotfiles-backups/<timestamp>/<basename>, membuat symlink,
dan tidak memanggil operasi recursive delete.

ensure_git_include harus menambahkan include path hanya jika belum ada:

    GIT_INCLUDE="~/.config/git/dotfiles.gitconfig"
    if ! git config --global --get-all include.path 2>/dev/null \
        | grep -Fxq "$GIT_INCLUDE"; then
      git config --global --add include.path "$GIT_INCLUDE"
    fi

Pada --dry-run, semua perubahan filesystem dan Git config hanya dicetak.

- [ ] Step 4: Jalankan integration test untuk memastikan ia lulus

Run: bash tests/test_installer.sh

Expected: PASS dengan output installer: PASS; run kedua tidak membuat backup
tambahan.

- [ ] Step 5: Commit perubahan task

    git add install.sh tests/test_installer.sh
    git commit -m "feat: add safe idempotent dotfiles installer"

---

### Task 5: Tool installer dan checker

**Files:**
- Create scripts/install-tools.sh
- Create scripts/check.sh
- Create tests/test_tools.sh

**Interfaces:**
- scripts/install-tools.sh --dry-run --skip-brew — mencetak tindakan tanpa
  network atau perubahan.
- scripts/install-tools.sh — menjalankan brew bundle pada macOS, lalu
  memasang package npm AI yang belum ada dengan prefix $HOME/.local.
- scripts/check.sh — memeriksa repository; --installed menambah check
  symlink/Git include; --strict-tools mengubah tool opsional yang hilang
  menjadi failure.

- [ ] Step 1: Tulis failing test untuk interface tools

Buat tests/test_tools.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

    bash -n "$ROOT_DIR/scripts/install-tools.sh"
    bash -n "$ROOT_DIR/scripts/check.sh"

    OUTPUT=$(bash "$ROOT_DIR/scripts/install-tools.sh" --dry-run --skip-brew 2>&1)
    grep -Fq "@openai/codex" <<<"$OUTPUT"
    grep -Fq "@anthropic-ai/claude-code" <<<"$OUTPUT"
    grep -Fq "NPM_CONFIG_PREFIX" <<<"$OUTPUT"

    CHECK_OUTPUT=$(bash "$ROOT_DIR/scripts/check.sh" 2>&1)
    grep -Fq "check:" <<<"$CHECK_OUTPUT"

    echo "tool scripts: PASS"

- [ ] Step 2: Jalankan test untuk memastikan ia gagal

Run: bash tests/test_tools.sh

Expected: FAIL karena script tool belum dibuat.

- [ ] Step 3: Implementasikan install-tools.sh

Script harus resolve repository root, menerima --dry-run dan --skip-brew,
menolak argumen tidak dikenal, menjalankan brew bundle --file=$ROOT_DIR/Brewfile
pada macOS dengan brew, dan melewati command yang sudah ada gh, glab,
codex, serta claude.

Jika codex belum ada, gunakan npm install --global @openai/codex. Jika
claude belum ada, gunakan npm install --global @anthropic-ai/claude-code.
Sebelum npm install, tetapkan NPM_CONFIG_PREFIX="$HOME/.local" dan pastikan
$HOME/.local/bin ada di PATH proses. Jangan memakai sudo, menjalankan login,
atau menulis credential. Beri pesan jelas jika npm atau brew belum tersedia.
Dry-run hanya mencetak command.

- [ ] Step 4: Implementasikan check.sh

Check harus melakukan zsh -n pada dua konfigurasi, bash -n pada semua script,
memeriksa manifest, dan mencari pola yang dilarang: /Users/rizalord,
OPENAI_API_KEY=, ANTHROPIC_API_KEY=, gho_, glpat-, BEGIN .* PRIVATE KEY,
serta file *.pem yang terlacak.

Command git, zsh, dan file repository adalah required. brew, gh, glab,
codex, claude, code, fzf, zoxide, dan starship dicetak sebagai
available/missing; --strict-tools mengembalikan failure bila tool tersebut
missing. --installed memeriksa link dan Git include pada $HOME.

- [ ] Step 5: Jalankan test untuk memastikan ia lulus

Run: bash tests/test_tools.sh

Expected: PASS dengan output tool scripts: PASS.

- [ ] Step 6: Commit perubahan task

    git add scripts/install-tools.sh scripts/check.sh tests/test_tools.sh
    git commit -m "feat: add tool installation and environment checks"

---

### Task 6: Test runner dan dokumentasi operasional

**Files:**
- Create scripts/test.sh
- Create README.md

**Interfaces:**
- scripts/test.sh menjalankan seluruh test dengan working directory repository,
  tanpa network dan tanpa real HOME mutation.
- README menjadi entry point setup, recovery, authentication manual, dan
  dual-remote workflow.

- [ ] Step 1: Tulis runner test

Buat scripts/test.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
    for test_file in "$ROOT_DIR"/tests/test_*.sh; do
      echo "==> $test_file"
      bash "$test_file"
    done

- [ ] Step 2: Jalankan seluruh test

Run: bash scripts/test.sh

Expected: seluruh test PASS dan setiap test file tercetak sebagai section.

- [ ] Step 3: Tulis README quick start

README harus memuat:

    git clone git@github.com:rizalord/dotfiles.git "$HOME/src/dotfiles"
    cd "$HOME/src/dotfiles"
    ./install.sh --dry-run
    ./install.sh
    ./scripts/install-tools.sh
    ./scripts/check.sh --installed --strict-tools

README juga menjelaskan default SSH key ~/.ssh/id_ed25519, login GitHub/GitLab
CLI manual, login Codex/Claude Code manual setelah install, VS Code CLI melalui
Command Palette, local override ~/.config/zsh/local.zsh, identity Git di
global config lokal, lokasi backup, dan workflow:

    git pull --rebase origin main
    git push origin main
    git push gitlab main

- [ ] Step 4: Commit perubahan task

    git add scripts/test.sh README.md
    git commit -m "docs: add dotfiles setup and recovery guide"

---

### Task 7: Verifikasi pada mesin ini, install tool, dan sinkronisasi remote

**Files:**
- Modify only if verification exposes a defect in files from Tasks 1–6.

**Interfaces:**
- Produces: working local setup, verified tools, clean commits, dan main
  branch tersinkron ke GitHub serta GitLab.

- [ ] Step 1: Jalankan semua test dan static checks

    bash scripts/test.sh
    git diff --check
    ./install.sh --dry-run

Expected: semua test PASS, diff check tanpa output, dry-run tidak membuat
symlink atau backup di $HOME.

- [ ] Step 2: Jalankan installer nyata dan verifikasi link

    ./install.sh
    ./scripts/check.sh --installed

Expected: .zshrc, .zprofile, Git shared config, dan global ignore
terpasang sebagai symlink; file yang sudah ada hanya dipindah ke backup.

- [ ] Step 3: Install/verifikasi tool developer

    ./scripts/install-tools.sh
    ./scripts/check.sh --installed --strict-tools

Expected: git, gh, glab, codex, claude, dan code terdeteksi. Jika VS Code
app atau network belum tersedia, proses memberi pesan actionable tanpa
membuat credential otomatis.

- [ ] Step 4: Verifikasi workflow shell dan Git

    zsh -lic 'command -v code; command -v codex; command -v claude; alias gs'
    git config --global --get-all include.path
    git status --short --branch

Buka shell baru bila command baru belum terlihat. Pastikan identity Git yang
sebelumnya sudah ada tetap terbaca dari config lokal.

- [ ] Step 5: Scan keamanan sebelum commit final

    git ls-files -z | xargs -0 rg -n 'OPENAI_API_KEY=|ANTHROPIC_API_KEY=|glpat-|gho_|/Users/rizalord|BEGIN .*PRIVATE KEY' || true
    git status --short

Expected: scan tidak menemukan secret atau absolute path user. Perubahan
lokal yang bukan bagian dotfiles tetap ditinjau dan tidak dibuang otomatis.

- [ ] Step 6: Commit hanya perubahan project

    git add .gitignore Brewfile git zsh install.sh scripts tests README.md docs/superpowers/plans
    git commit -m "feat: build portable dotfiles foundation"

- [ ] Step 7: Push ke dua remote dan verifikasi commit sama

    git push origin main
    git push gitlab main
    git ls-remote origin refs/heads/main
    git ls-remote gitlab refs/heads/main
    git branch -vv

Expected: kedua remote menunjuk commit main yang sama dan local upstream tetap
origin/main.
