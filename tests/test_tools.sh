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
