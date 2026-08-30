#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INSTALLER="$ROOT_DIR/scripts/install-tools.sh"
CHECKER="$ROOT_DIR/scripts/check.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TMP_ROOT"' EXIT

PATH_MARKER="/Users/"'rizalord'
OPENAI_MARKER="OPENAI_API_KEY"'='
ANTHROPIC_MARKER="ANTHROPIC_API_KEY"'='
GH_MARKER='gho''_'
GLAB_MARKER='glpat''-'
PRIVATE_KEY_MARKER='BEGIN '
PRIVATE_KEY_MARKER="${PRIVATE_KEY_MARKER}.* PRIVATE KEY"

assert_contains() {
  local text="$1"
  local expected="$2"
  grep -Fq -- "$expected" <<<"$text" || {
    printf 'missing text: %s\n' "$expected" >&2
    exit 1
  }
}

assert_not_contains() {
  local text="$1"
  local unexpected="$2"
  if grep -Fq -- "$unexpected" <<<"$text"; then
    printf 'unexpected text: %s\n' "$unexpected" >&2
    exit 1
  fi
}

write_fake() {
  local bin_dir="$1"
  local command_name="$2"
  local body="$3"

  printf '%s\n' '#!/usr/bin/env bash' "$body" > "$bin_dir/$command_name"
  chmod +x "$bin_dir/$command_name"
}

expect_failure() {
  local output_file="$1"
  shift

  if "$@" >"$output_file" 2>&1; then
    printf 'command unexpectedly succeeded: %s\n' "$*" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

# Syntax remains a direct interface contract for both scripts.
bash -n "$INSTALLER"
bash -n "$CHECKER"

# --dry-run --skip-brew must report the plan without creating anything or
# probing a real user's tool installation.
DRY_HOME="$TMP_ROOT/dry-home"
DRY_BIN="$TMP_ROOT/dry-bin"
DRY_DOCKER_LOG="$TMP_ROOT/dry-docker.log"
mkdir -p "$DRY_HOME" "$DRY_BIN"
write_fake "$DRY_BIN" docker 'printf "dry-run invoked docker\n" >> "$DRY_DOCKER_LOG"; exit 99'
DRY_OUTPUT=$(HOME="$DRY_HOME" PATH="$DRY_BIN:/usr/bin:/bin" \
  DRY_DOCKER_LOG="$DRY_DOCKER_LOG" bash "$INSTALLER" --dry-run --skip-brew 2>&1)
assert_contains "$DRY_OUTPUT" 'Homebrew bundle skipped by --skip-brew.'
assert_contains "$DRY_OUTPUT" 'docker buildx version'
assert_contains "$DRY_OUTPUT" 'NPM_CONFIG_PREFIX='
assert_contains "$DRY_OUTPUT" '@openai/codex'
assert_contains "$DRY_OUTPUT" '@anthropic-ai/claude-code'
assert_contains "$DRY_OUTPUT" 'mise use --global node@lts'
assert_contains "$DRY_OUTPUT" 'mise exec -- npm --version'
test ! -e "$DRY_HOME/.local"

# Invalid installer flags must fail before doing any work.
INVALID_OUTPUT="$TMP_ROOT/invalid-output"
expect_failure "$INVALID_OUTPUT" env HOME="$DRY_HOME" PATH="$DRY_BIN:/usr/bin:/bin" \
  bash "$INSTALLER" --not-a-real-flag
assert_contains "$(<"$INVALID_OUTPUT")" 'Usage: install-tools.sh [--dry-run] [--skip-brew]'

# Existing AI CLIs are reported as skips during dry-run and real execution.
SKIP_HOME="$TMP_ROOT/skip-home"
SKIP_BIN="$TMP_ROOT/skip-bin"
mkdir -p "$SKIP_HOME" "$SKIP_BIN"
for command_name in mise colima docker gh glab codex claude; do
  write_fake "$SKIP_BIN" "$command_name" 'exit 0'
done
SKIP_OUTPUT=$(HOME="$SKIP_HOME" PATH="$SKIP_BIN:/usr/bin:/bin" \
  bash "$INSTALLER" --dry-run --skip-brew 2>&1)
assert_contains "$SKIP_OUTPUT" 'codex already available; @openai/codex installation is skipped.'
assert_contains "$SKIP_OUTPUT" 'claude already available; @anthropic-ai/claude-code installation is skipped.'
assert_not_contains "$SKIP_OUTPUT" 'npm install --global @openai/codex'
assert_not_contains "$SKIP_OUTPUT" 'npm install --global @anthropic-ai/claude-code'
SKIP_OUTPUT=$(HOME="$SKIP_HOME" PATH="$SKIP_BIN:/usr/bin:/bin" \
  bash "$INSTALLER" --skip-brew 2>&1)
assert_contains "$SKIP_OUTPUT" 'codex already available; npm package installation is skipped.'
assert_contains "$SKIP_OUTPUT" 'claude already available; npm package installation is skipped.'

# Non-dry-run AI installation must use mise's environment for npm. An ambient
# npm executable is supplied only to prove it is never called.
AI_HOME="$TMP_ROOT/ai-home"
AI_BIN="$TMP_ROOT/ai-bin"
AMBIENT_BIN="$TMP_ROOT/ambient-bin"
TOOL_LOG="$TMP_ROOT/mise.log"
mkdir -p "$AI_HOME" "$AI_BIN" "$AMBIENT_BIN"
for command_name in colima docker gh glab; do
  write_fake "$AI_BIN" "$command_name" 'exit 0'
done
write_fake "$AI_BIN" mise 'printf "mise %s NPM_CONFIG_PREFIX=%s PATH=%s\n" "$*" "$NPM_CONFIG_PREFIX" "$PATH" >> "$TOOL_LOG"; if [ "${1:-}" = exec ] && [ "${3:-}" = npm ] && [ "${4:-}" = --version ]; then printf "10.0.0\n"; fi; exit 0'
write_fake "$AMBIENT_BIN" npm 'printf "ambient npm was called\n" >> "$TOOL_LOG"; exit 99'
AI_OUTPUT=$(HOME="$AI_HOME" TOOL_LOG="$TOOL_LOG" \
  PATH="$AI_BIN:$AMBIENT_BIN:/usr/bin:/bin" \
  bash "$INSTALLER" --skip-brew 2>&1)
assert_contains "$AI_OUTPUT" 'NPM_CONFIG_PREFIX='
assert_contains "$(<"$TOOL_LOG")" 'mise use --global node@lts'
assert_contains "$(<"$TOOL_LOG")" 'mise exec -- npm --version'
assert_contains "$(<"$TOOL_LOG")" 'mise exec -- npm install --global @openai/codex'
assert_contains "$(<"$TOOL_LOG")" 'mise exec -- npm install --global @anthropic-ai/claude-code'
assert_contains "$(<"$TOOL_LOG")" "NPM_CONFIG_PREFIX=$AI_HOME/.local"
assert_contains "$(<"$TOOL_LOG")" "PATH=$AI_HOME/.local/bin:$AI_BIN:$AMBIENT_BIN:/usr/bin:/bin"
assert_not_contains "$(<"$TOOL_LOG")" 'ambient npm was called'
test -d "$AI_HOME/.local/bin"

# Brew Bundle is guarded by the host OS: macOS invokes brew, Linux skips it.
for platform in Darwin Linux; do
  PLATFORM_PREFIX=$(printf '%s' "$platform" | tr '[:upper:]' '[:lower:]')
  PLATFORM_HOME="$TMP_ROOT/${PLATFORM_PREFIX}-home"
  PLATFORM_BIN="$TMP_ROOT/${PLATFORM_PREFIX}-bin"
  PLATFORM_LOG="$TMP_ROOT/${PLATFORM_PREFIX}-brew.log"
  mkdir -p "$PLATFORM_HOME" "$PLATFORM_BIN"
  write_fake "$PLATFORM_BIN" uname "printf '%s\\n' '$platform'"
  write_fake "$PLATFORM_BIN" brew 'printf "brew %s\n" "$*" >> "$PLATFORM_LOG"'
  for command_name in mise colima docker gh glab codex claude; do
    write_fake "$PLATFORM_BIN" "$command_name" 'exit 0'
  done
  PLATFORM_OUTPUT=$(HOME="$PLATFORM_HOME" PLATFORM_LOG="$PLATFORM_LOG" \
    PATH="$PLATFORM_BIN:/usr/bin:/bin" bash "$INSTALLER" 2>&1)
  if [ "$platform" = Darwin ]; then
    assert_contains "$(<"$PLATFORM_LOG")" "brew bundle --file=$ROOT_DIR/Brewfile"
  else
    assert_contains "$PLATFORM_OUTPUT" 'Homebrew bundle skipped: this installer only uses Brewfile on macOS.'
    test ! -e "$PLATFORM_LOG"
  fi
done

# Default and custom XDG installs must both validate the installer's exact
# include spelling and every managed symlink target.
check_installed() {
  local home_dir="$1"
  local config_dir="$2"
  local global_config="$3"
  shift 3
  HOME="$home_dir" XDG_CONFIG_HOME="$config_dir" GIT_CONFIG_GLOBAL="$global_config" \
    PATH="/usr/bin:/bin" bash "$CHECKER" --installed "$@"
}

check_installed_default() {
  local home_dir="$1"
  local global_config="$2"
  shift 2
  env -u XDG_CONFIG_HOME HOME="$home_dir" GIT_CONFIG_GLOBAL="$global_config" \
    PATH="/usr/bin:/bin" bash "$CHECKER" --installed "$@"
}

assert_exact_links() {
  local home_dir="$1"
  local config_dir="$2"
  test -L "$home_dir/.zshrc"
  test "$(readlink "$home_dir/.zshrc")" = "$ROOT_DIR/zsh/.zshrc"
  test -L "$home_dir/.zprofile"
  test "$(readlink "$home_dir/.zprofile")" = "$ROOT_DIR/zsh/.zprofile"
  test -L "$config_dir/git/dotfiles.gitconfig"
  test "$(readlink "$config_dir/git/dotfiles.gitconfig")" = "$ROOT_DIR/git/.gitconfig"
  test -L "$config_dir/git/ignore"
  test "$(readlink "$config_dir/git/ignore")" = "$ROOT_DIR/git/.gitignore_global"
}

DEFAULT_HOME="$TMP_ROOT/default-home"
DEFAULT_CONFIG="$DEFAULT_HOME/.config"
DEFAULT_GLOBAL="$TMP_ROOT/default-global"
mkdir -p "$DEFAULT_HOME"
env -u XDG_CONFIG_HOME HOME="$DEFAULT_HOME" GIT_CONFIG_GLOBAL="$DEFAULT_GLOBAL" \
  PATH="/usr/bin:/bin" bash "$ROOT_DIR/install.sh" >/dev/null
check_installed_default "$DEFAULT_HOME" "$DEFAULT_GLOBAL"
assert_exact_links "$DEFAULT_HOME" "$DEFAULT_CONFIG"
DEFAULT_INCLUDE=$(env -u XDG_CONFIG_HOME HOME="$DEFAULT_HOME" \
  GIT_CONFIG_GLOBAL="$DEFAULT_GLOBAL" git config --global --get-all include.path)
test "$DEFAULT_INCLUDE" = '~/.config/git/dotfiles.gitconfig'

WRONG_TARGET="$DEFAULT_HOME/wrong-target"
printf '%s\n' wrong > "$WRONG_TARGET"
rm "$DEFAULT_HOME/.zshrc"
ln -s "$WRONG_TARGET" "$DEFAULT_HOME/.zshrc"
WRONG_OUTPUT="$TMP_ROOT/wrong-link-output"
expect_failure "$WRONG_OUTPUT" check_installed "$DEFAULT_HOME" "$DEFAULT_CONFIG" "$DEFAULT_GLOBAL"
assert_contains "$(<"$WRONG_OUTPUT")" 'managed link target mismatch: '
rm "$DEFAULT_HOME/.zshrc"
ln -s "$ROOT_DIR/zsh/.zshrc" "$DEFAULT_HOME/.zshrc"

rm "$DEFAULT_HOME/.zprofile"
ln -s "$DEFAULT_HOME/missing-zprofile" "$DEFAULT_HOME/.zprofile"
DANGLING_OUTPUT="$TMP_ROOT/dangling-link-output"
expect_failure "$DANGLING_OUTPUT" check_installed "$DEFAULT_HOME" "$DEFAULT_CONFIG" "$DEFAULT_GLOBAL"
assert_contains "$(<"$DANGLING_OUTPUT")" 'managed link target mismatch: '
rm "$DEFAULT_HOME/.zprofile"
ln -s "$ROOT_DIR/zsh/.zprofile" "$DEFAULT_HOME/.zprofile"

CUSTOM_HOME="$TMP_ROOT/custom-home"
CUSTOM_CONFIG="$TMP_ROOT/custom-config"
CUSTOM_GLOBAL="$TMP_ROOT/custom-global"
mkdir -p "$CUSTOM_HOME"
HOME="$CUSTOM_HOME" XDG_CONFIG_HOME="$CUSTOM_CONFIG" GIT_CONFIG_GLOBAL="$CUSTOM_GLOBAL" \
  PATH="/usr/bin:/bin" bash "$ROOT_DIR/install.sh" >/dev/null
check_installed "$CUSTOM_HOME" "$CUSTOM_CONFIG" "$CUSTOM_GLOBAL"
assert_exact_links "$CUSTOM_HOME" "$CUSTOM_CONFIG"
CUSTOM_INCLUDE=$(HOME="$CUSTOM_HOME" XDG_CONFIG_HOME="$CUSTOM_CONFIG" \
  GIT_CONFIG_GLOBAL="$CUSTOM_GLOBAL" git config --global --get-all include.path)
test "$CUSTOM_INCLUDE" = "$CUSTOM_CONFIG/git/dotfiles.gitconfig"

# Optional tools are warnings normally and failures in strict mode.
STRICT_HOME="$TMP_ROOT/strict-home"
STRICT_GLOBAL="$TMP_ROOT/strict-global"
mkdir -p "$STRICT_HOME"
STRICT_OUTPUT="$TMP_ROOT/strict-output"
HOME="$STRICT_HOME" GIT_CONFIG_GLOBAL="$STRICT_GLOBAL" PATH="/usr/bin:/bin" \
  bash "$CHECKER" > "$STRICT_OUTPUT" 2>&1
assert_contains "$(<"$STRICT_OUTPUT")" 'check: MISSING:'
expect_failure "$STRICT_OUTPUT" env HOME="$STRICT_HOME" GIT_CONFIG_GLOBAL="$STRICT_GLOBAL" \
  PATH="/usr/bin:/bin" bash "$CHECKER" --strict-tools
assert_contains "$(<"$STRICT_OUTPUT")" 'check: FAIL: tool missing:'

# Docker Buildx and Compose are checked independently; Buildx participates in
# strict mode just like the other optional tools.
DOCKER_AVAILABLE_HOME="$TMP_ROOT/docker-available-home"
DOCKER_AVAILABLE_BIN="$TMP_ROOT/docker-available-bin"
DOCKER_AVAILABLE_GLOBAL="$TMP_ROOT/docker-available-global"
mkdir -p "$DOCKER_AVAILABLE_HOME" "$DOCKER_AVAILABLE_BIN"
write_fake "$DOCKER_AVAILABLE_BIN" docker 'if [ "${1:-}" = buildx ] && [ "${2:-}" = version ]; then printf "github.com/docker/buildx v0.0.0\n"; elif [ "${1:-}" = compose ] && [ "${2:-}" = version ]; then printf "Docker Compose version v0.0.0\n"; else exit 1; fi'
DOCKER_AVAILABLE_OUTPUT=$(HOME="$DOCKER_AVAILABLE_HOME" GIT_CONFIG_GLOBAL="$DOCKER_AVAILABLE_GLOBAL" \
  PATH="$DOCKER_AVAILABLE_BIN:/usr/bin:/bin" bash "$CHECKER" 2>&1)
assert_contains "$DOCKER_AVAILABLE_OUTPUT" 'check: PASS: tool available: docker buildx'
assert_contains "$DOCKER_AVAILABLE_OUTPUT" 'check: PASS: tool available: docker compose'

DOCKER_MISSING_HOME="$TMP_ROOT/docker-missing-home"
DOCKER_MISSING_BIN="$TMP_ROOT/docker-missing-bin"
DOCKER_MISSING_GLOBAL="$TMP_ROOT/docker-missing-global"
mkdir -p "$DOCKER_MISSING_HOME" "$DOCKER_MISSING_BIN"
write_fake "$DOCKER_MISSING_BIN" docker 'if [ "${1:-}" = compose ] && [ "${2:-}" = version ]; then printf "Docker Compose version v0.0.0\n"; else exit 1; fi'
DOCKER_MISSING_OUTPUT=$(HOME="$DOCKER_MISSING_HOME" GIT_CONFIG_GLOBAL="$DOCKER_MISSING_GLOBAL" \
  PATH="$DOCKER_MISSING_BIN:/usr/bin:/bin" bash "$CHECKER" 2>&1)
assert_contains "$DOCKER_MISSING_OUTPUT" 'check: MISSING: docker buildx'
DOCKER_STRICT_OUTPUT="$TMP_ROOT/docker-strict-output"
expect_failure "$DOCKER_STRICT_OUTPUT" env HOME="$DOCKER_MISSING_HOME" \
  GIT_CONFIG_GLOBAL="$DOCKER_MISSING_GLOBAL" PATH="$DOCKER_MISSING_BIN:/usr/bin:/bin" \
  bash "$CHECKER" --strict-tools
assert_contains "$(<"$DOCKER_STRICT_OUTPUT")" 'check: FAIL: tool missing: docker buildx'

# The unchanged policy examples are allowed for every forbidden marker.
BASE_CHECK_OUTPUT=$(HOME="$STRICT_HOME" GIT_CONFIG_GLOBAL="$STRICT_GLOBAL" \
  PATH="/usr/bin:/bin" bash "$CHECKER" 2>&1)
for marker in "$PATH_MARKER" "$OPENAI_MARKER" "$ANTHROPIC_MARKER" "$GH_MARKER" \
  "$GLAB_MARKER" "$PRIVATE_KEY_MARKER"; do
  assert_contains "$BASE_CHECK_OUTPUT" "security pattern absent: $marker"
done

# Moving an allowed line must not invalidate it: the allowlist is content-based.
SHIFT_REPO="$TMP_ROOT/shifted-policy-repo"
SHIFT_HOME="$TMP_ROOT/shifted-policy-home"
SHIFT_GLOBAL="$TMP_ROOT/shifted-policy-global"
git clone --quiet "$ROOT_DIR" "$SHIFT_REPO"
cp "$CHECKER" "$SHIFT_REPO/scripts/check.sh"
SHIFT_MARKER='OPENAI_API_KEY'
awk -v marker="$SHIFT_MARKER" 'index($0, marker) { print ""; print "" } { print }' \
  "$SHIFT_REPO/docs/superpowers/plans/2026-08-30-dotfiles-foundation.md" \
  > "$TMP_ROOT/shifted-policy.md"
mv "$TMP_ROOT/shifted-policy.md" "$SHIFT_REPO/docs/superpowers/plans/2026-08-30-dotfiles-foundation.md"
mkdir -p "$SHIFT_HOME"
SHIFT_OUTPUT=$(HOME="$SHIFT_HOME" GIT_CONFIG_GLOBAL="$SHIFT_GLOBAL" \
  PATH="/usr/bin:/bin" bash "$SHIFT_REPO/scripts/check.sh" 2>&1)
for marker in "$PATH_MARKER" "$OPENAI_MARKER" "$ANTHROPIC_MARKER" "$GH_MARKER" \
  "$GLAB_MARKER" "$PRIVATE_KEY_MARKER"; do
  assert_contains "$SHIFT_OUTPUT" "security pattern absent: $marker"
done

# Tampering with one allowed line must make every marker on that line fail.
TAMPER_REPO="$TMP_ROOT/tampered-policy-repo"
TAMPER_HOME="$TMP_ROOT/tampered-policy-home"
TAMPER_GLOBAL="$TMP_ROOT/tampered-policy-global"
git clone --quiet "$ROOT_DIR" "$TAMPER_REPO"
cp "$CHECKER" "$TAMPER_REPO/scripts/check.sh"
TAMPER_MARKER='OPENAI_API_KEY'
awk -v marker="$TAMPER_MARKER" 'index($0, marker) { print $0 " tampered"; next } { print }' \
  "$TAMPER_REPO/docs/superpowers/plans/2026-08-30-dotfiles-foundation.md" \
  > "$TMP_ROOT/tampered-policy.md"
mv "$TMP_ROOT/tampered-policy.md" "$TAMPER_REPO/docs/superpowers/plans/2026-08-30-dotfiles-foundation.md"
mkdir -p "$TAMPER_HOME"
TAMPER_OUTPUT="$TMP_ROOT/tampered-policy-output"
expect_failure "$TAMPER_OUTPUT" env HOME="$TAMPER_HOME" GIT_CONFIG_GLOBAL="$TAMPER_GLOBAL" \
  PATH="/usr/bin:/bin" bash "$TAMPER_REPO/scripts/check.sh"
for marker in "$PATH_MARKER" "$OPENAI_MARKER" "$ANTHROPIC_MARKER" "$GH_MARKER" \
  "$GLAB_MARKER" "$PRIVATE_KEY_MARKER"; do
  assert_contains "$(<"$TAMPER_OUTPUT")" "forbidden tracked content matches: $marker"
done

# Security scanning must still inspect an ordinary tracked file under docs;
# only the exact, unchanged policy-example lines may be ignored.
SECURITY_REPO="$TMP_ROOT/security-repo"
SECURITY_HOME="$TMP_ROOT/security-home"
SECURITY_GLOBAL="$TMP_ROOT/security-global"
git clone --quiet "$ROOT_DIR" "$SECURITY_REPO"
cp "$CHECKER" "$SECURITY_REPO/scripts/check.sh"
git -C "$SECURITY_REPO" config user.name 'Task 5 Test'
git -C "$SECURITY_REPO" config user.email task-5@example.test
SECURITY_MARKER="OPENAI_API_KEY"'='
printf '%s\n' "${SECURITY_MARKER}fixture" > "$SECURITY_REPO/docs/ordinary.md"
git -C "$SECURITY_REPO" add docs/ordinary.md
git -C "$SECURITY_REPO" commit -qm 'add security fixture'
mkdir -p "$SECURITY_HOME"
SECURITY_OUTPUT="$TMP_ROOT/security-output"
expect_failure "$SECURITY_OUTPUT" env HOME="$SECURITY_HOME" \
  GIT_CONFIG_GLOBAL="$SECURITY_GLOBAL" PATH="/usr/bin:/bin" \
  bash "$SECURITY_REPO/scripts/check.sh"
SECURITY_FAILURE_TEXT='forbidden tracked content matches: OPENAI_API_KEY''='
assert_contains "$(<"$SECURITY_OUTPUT")" "$SECURITY_FAILURE_TEXT"

echo "tool scripts: PASS"
