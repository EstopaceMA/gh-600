#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(cd -- "$TEST_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/copilot-hook-logs.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

# Use a checkout with spaces and isolated logs; never alter real audit records.
REPO_DIR="$TEMP_DIR/repo with spaces"
FIXTURE_HOOKS="$REPO_DIR/.github/hooks"
LOG_FILE="$FIXTURE_HOOKS/logs/audit.jsonl"
mkdir -p "$FIXTURE_HOOKS/scripts" "$FIXTURE_HOOKS/logs" "$TEMP_DIR/elsewhere"
cp "$HOOKS_DIR/scripts/log-prompt.sh" "$HOOKS_DIR/scripts/pre-tool-policy.sh" \
  "$FIXTURE_HOOKS/scripts/"
printf '%s\n' '{"event":"existingRecord"}' > "$LOG_FILE"

assert_record_count() {
  local actual
  actual="$(jq -s 'length' "$LOG_FILE")"
  if [[ "$actual" != "$1" ]]; then
    printf 'FAIL: expected %s records in the existing log, found %s\n' "$1" "$actual" >&2
    exit 1
  fi
}

expected=1
for working_dir in "$REPO_DIR" "$FIXTURE_HOOKS" "$TEMP_DIR/elsewhere"; do
  # The payload cwd must not control the destination either.
  prompt_input="$(jq -cn --arg cwd "$TEMP_DIR/elsewhere" \
    '{timestamp: 1234567890, cwd: $cwd, prompt: "log path regression test"}')"
  tool_input='{"toolName":"bash","toolArgs":"{\"command\":\"git status --short\"}"}'

  (
    cd -- "$working_dir"
    printf '%s\n' "$prompt_input" | bash "$FIXTURE_HOOKS/scripts/log-prompt.sh"
    printf '%s\n' "$tool_input" | bash "$FIXTURE_HOOKS/scripts/pre-tool-policy.sh"
  )

  expected=$((expected + 2))
  assert_record_count "$expected"
  jq -se '.[0].event == "existingRecord" and
    .[-2].event == "userPromptSubmitted" and .[-1].event == "preToolUse"' \
    "$LOG_FILE" > /dev/null
done

log_files="$(find "$TEMP_DIR" -name audit.jsonl -type f)"
if [[ "$log_files" != "$LOG_FILE" ]]; then
  printf 'FAIL: unexpected audit log locations:\n%s\n' "$log_files" >&2
  exit 1
fi

printf 'PASS: both hooks reuse the existing log from all three working directories.\n'
