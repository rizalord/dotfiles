# Desain Fondasi Dotfiles

Tanggal: 2026-08-30

## Tujuan

Membangun fondasi dotfiles yang dapat dipakai ulang pada mesin baru, aman
untuk dipublikasikan di repository private, mudah diaudit, dan tidak
bergantung pada absolute path mesin saat ini. Target utama adalah macOS
dengan zsh; bagian yang tidak spesifik macOS diberi guard agar tetap dapat
dipakai di Linux.

## Keputusan arsitektur

### Pendekatan

Menggunakan shell script native dan symlink terkelola, tanpa framework
dotfiles tambahan seperti chezmoi atau GNU Stow. Pendekatan ini dipilih
karena dependency minimal, alur install mudah dibaca, dan perilaku backup
dapat dikontrol langsung oleh repository.

Alternatif yang dipertimbangkan:

- **chezmoi**: unggul untuk template lintas mesin dan secret management,
  tetapi menambah dependency dan abstraksi sebelum kebutuhan tersebut ada.
- **GNU Stow**: ringan untuk symlink, tetapi kurang cocok untuk langkah
  install, backup, deteksi OS, dan verifikasi tool yang lebih kaya.

### Struktur repository

```text
.
├── Brewfile
├── README.md
├── .gitignore
├── install.sh
├── docs/
│   └── superpowers/specs/
├── git/
│   ├── .gitconfig
│   └── .gitignore_global
├── scripts/
│   ├── check.sh
│   ├── install-tools.sh
│   └── test.sh
└── zsh/
    ├── .zprofile
    └── .zshrc
```

File konfigurasi bersama berada di repository. Override pribadi berada di
luar repository, terutama `~/.config/zsh/local.zsh` dan konfigurasi Git
lokal milik pengguna.

## Komponen dan perilaku

### `install.sh`

Installer harus idempotent dan aman dijalankan berulang kali.

- Menentukan lokasi repository berdasarkan lokasi script, bukan current
  working directory.
- Membuat symlink untuk `.zshrc` dan `.zprofile`.
- Jika tujuan sudah berisi file atau symlink lain, memindahkannya ke backup
  bertimestamp di `~/.local/state/dotfiles-backups/`; tidak menghapus data.
- Menyediakan mode `--dry-run` untuk inspeksi tanpa perubahan.
- Membuat direktori konfigurasi yang dibutuhkan dengan permission yang wajar.
- Mendaftarkan shared Git config melalui path stabil di
  `~/.config/git/dotfiles.gitconfig`, sehingga path clone repository boleh
  berbeda antar mesin dan identity Git pengguna tetap berada di luar repo.
- Menampilkan ringkasan tindakan dan lokasi backup.

Installer tidak menjalankan login GitHub/GitLab, tidak membuat SSH key, dan
tidak menyalin credential store.

### Zsh

`.zprofile` hanya memuat environment untuk login shell:

- Memuat `brew shellenv` hanya jika Homebrew tersedia.
- Menambahkan `$HOME/.local/bin` tanpa absolute path pengguna tertentu.

`.zshrc` hanya aktif pada interactive shell dan memuat:

- history yang aman dan nyaman;
- completion bawaan zsh;
- editor dan language/tool paths yang dapat dioverride;
- integrasi opsional untuk `fzf`, `zoxide`, dan `starship` hanya jika
  command tersedia;
- alias Git dan command dasar yang tidak menimpa perilaku berisiko;
- `~/.config/zsh/local.zsh` jika file tersebut ada.

Tidak ada API key, token, hostname internal, atau path `/Users/...` yang
ditulis di konfigurasi bersama.

### Git

`git/.gitconfig` berisi preference yang lintas mesin, antara lain:

- default branch `main`;
- `pull.rebase`, `fetch.prune`, `push.autoSetupRemote`;
- diff/merge yang lebih mudah direview;
- rerere dan sorting yang membantu workflow engineering;
- alias yang aman dan deskriptif.

Identity (`user.name`, `user.email`), signing key, credential helper, dan
pengaturan perusahaan tidak dimasukkan ke shared config. `git/.gitignore_global`
dipasang sebagai global excludes file untuk artefak umum seperti `.DS_Store`.

### Tooling

`Brewfile` berisi tool CLI umum yang stabil untuk macOS, termasuk GitHub CLI,
GitLab CLI, dan utilitas developer yang dipakai konfigurasi shell.

`scripts/install-tools.sh` memeriksa tool dan hanya memasang yang belum ada.
Codex CLI dan Claude Code CLI masuk sebagai tool opsional yang diverifikasi
seperti tool lain. Mekanisme install mengikuti channel resmi masing-masing
tool saat implementasi; script tidak pernah menulis token atau menjalankan
proses login secara otomatis.

### Verifikasi

`scripts/check.sh` melakukan pemeriksaan read-only:

- syntax check semua shell script dan konfigurasi zsh;
- keberadaan symlink yang dikelola;
- keberadaan command inti dan versi singkatnya;
- validitas konfigurasi Git shared;
- pemeriksaan pola secret dan absolute path yang tidak boleh masuk repo.

`scripts/test.sh` menjalankan test lokal tanpa network dan tanpa mengubah
home directory pengguna. Jika lint tool opsional tidak terpasang, test
memberi status skip yang eksplisit, bukan false positive.

## Keamanan dan recovery

`.gitignore` mengecualikan local override, `.env`, token, private key,
credential file, cache, log, dan artefak OS. Contoh konfigurasi hanya boleh
berisi placeholder.

Semua penggantian file oleh installer dapat dipulihkan dari direktori backup.
Installer tidak memakai operasi recursive delete dan tidak menimpa file
existing tanpa memindahkannya terlebih dahulu.

## Workflow sinkronisasi

Commit dilakukan ke branch `main`. Remote utama tetap `origin` (GitHub),
sedangkan GitLab menjadi mirror eksplisit:

```sh
git push origin main
git push gitlab main
```

Installer dan test tidak melakukan push otomatis. README menjelaskan setup
mesin baru, recovery backup, login CLI secara manual, serta cara mengirim
perubahan ke kedua remote.

## Kriteria penerimaan

- `install.sh --dry-run` tidak mengubah filesystem.
- Menjalankan installer dua kali menghasilkan konfigurasi yang sama tanpa
  backup tambahan yang tidak perlu.
- `.zshrc` dan `.zprofile` lolos syntax check.
- Tidak ada secret, absolute path pengguna, atau credential state yang
  terlacak Git.
- `gh`, `glab`, `codex`, dan `claude` dapat diverifikasi tanpa memerlukan
  login otomatis.
- Test berjalan pada mesin saat ini dan menjelaskan dependency yang tidak
  tersedia.
- Perubahan tervalidasi sebelum commit dan dipush ke GitHub serta GitLab.
