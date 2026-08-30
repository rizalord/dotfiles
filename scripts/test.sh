#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf -- "$TEST_HOME"' EXIT

# Keep every test process away from the user's real home and Git config.
export HOME="$TEST_HOME"
export XDG_CONFIG_HOME="$TEST_HOME/.config"
export XDG_STATE_HOME="$TEST_HOME/.local/state"
export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"

cd -- "$ROOT_DIR"

for test_file in "$ROOT_DIR"/tests/test_*.sh; do
  echo "==> $test_file"
  bash "$test_file"
done
