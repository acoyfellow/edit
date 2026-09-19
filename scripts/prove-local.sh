#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mix test
bun test
printf 'draft\n' > fixtures/approved_replace_text/workspace/note.txt
payload='{"id":"edit-local-proof","type":"prompt","message":"/edit fixtures/approved_replace_text/request.json fixtures/approved_replace_text/approval.json"}'
printf '%s\n' "$payload" | {
  cat
  sleep 5
} | EDIT_RUNTIME_DIR="$PWD" pi --mode rpc --no-session --no-extensions -e "$HOME/.pi/agent/extensions/edit.ts" --no-tools > /tmp/edit-local-proof-rpc.jsonl
grep -q '"message":"edit: succeeded"' /tmp/edit-local-proof-rpc.jsonl
test "$(cat fixtures/approved_replace_text/workspace/note.txt)" = published
printf 'draft\n' > fixtures/approved_replace_text/workspace/note.txt
grep -q '"jev":{"status":"blocked_missing_credentials"}' <(cd "$PWD" && mix run -e 'r=File.read!("fixtures/approved_replace_text/request.json")|>Jason.decode!(); a=File.read!("fixtures/approved_replace_text/approval.json")|>Jason.decode!(); IO.puts(Jason.encode!(EditRuntime.Workflow.run(%{"request"=>r,"approval"=>a})))')
printf '%s\n' 'local edit proof passed; Jev live proof remains blocked on provider credentials'
