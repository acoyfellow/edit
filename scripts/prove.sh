#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${TYPESAFE_API_KEY:-}" && ( -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" ) ]]; then
  printf '%s\n' 'A Jev credential is required: TYPESAFE_API_KEY or CLOUDFLARE_API_TOKEN plus CLOUDFLARE_ACCOUNT_ID.' >&2
  exit 2
fi

mix test
bun test
printf 'draft\n' > fixtures/approved_replace_text/workspace/note.txt

payload=$(python3 -c 'import json,sys; print(json.dumps({"id":"edit-proof","type":"prompt","message":"/edit fixtures/approved_replace_text/request.json fixtures/approved_replace_text/approval.json"}))')

printf '%s\n' "$payload" | {
  cat
  sleep 5
} | EDIT_RUNTIME_DIR="$PWD" pi --mode rpc --no-session --no-extensions -e "$HOME/.pi/agent/extensions/edit.ts" --no-tools > /tmp/edit-proof-rpc.jsonl

if ! grep -q '"message":"edit: succeeded"' /tmp/edit-proof-rpc.jsonl; then
  cat /tmp/edit-proof-rpc.jsonl >&2
  exit 1
fi
test "$(cat fixtures/approved_replace_text/workspace/note.txt)" = published
printf '%s\n' 'edit proof passed'
