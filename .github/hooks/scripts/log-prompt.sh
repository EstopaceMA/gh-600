#!/bin/bash
set -euo pipefail

INPUT="$(cat)"

TIMESTAMP_MS="$(echo "$INPUT" | jq -r '.timestamp // empty')"
CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"

# This example logs only metadata, not the full prompt, to avoid storing
# potentially sensitive data. Adjust to match your organization’s needs.
# Resolve from the script so every working directory reuses the same logs.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

jq -n \
  --arg ts "$TIMESTAMP_MS" \
  --arg cwd "$CWD" \
  '{event:"userPromptSubmitted", timestampMs:$ts, cwd:$cwd}' \
  >> "$LOG_DIR/audit.jsonl"

exit 0