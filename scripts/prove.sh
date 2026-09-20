#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${TYPESAFE_API_KEY:-}" && ( -z "${AI_GATEWAY_TOKEN:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" ) ]]; then
  printf '%s\n' 'A Jev credential is required: TYPESAFE_API_KEY or AI_GATEWAY_TOKEN plus CLOUDFLARE_ACCOUNT_ID.' >&2
  exit 2
fi

fixture_note=fixtures/approved_replace_text/workspace/note.txt
reset_fixture() { printf 'draft\n' > "$fixture_note"; }
trap reset_fixture EXIT

mix test
bun test
./scripts/escape.sh

reset_fixture
payload=$(python3 -c 'import json; print(json.dumps({"id":"edit-proof","type":"prompt","message":"/edit fixtures/approved_replace_text/request.json fixtures/approved_replace_text/approval.json"}))')
rpc_output=$(mktemp)
{
  printf '%s\n' "$payload"
  for _ in $(seq 1 90); do
    grep -q '"message":"edit: ' "$rpc_output" 2>/dev/null && break
    sleep 1
  done
} | EDIT_RUNTIME_DIR="$PWD" pi --mode rpc --no-session --no-extensions -e "$HOME/.pi/agent/extensions/edit.ts" --no-tools > "$rpc_output"

if ! grep -q '"message":"edit: succeeded (jev: approved)"' "$rpc_output"; then
  cat "$rpc_output" >&2
  exit 1
fi
test "$(cat "$fixture_note")" = published

reset_fixture
printf '{"request":%s,"approval":%s}\n' "$(cat fixtures/approved_replace_text/request.json)" "$(cat fixtures/approved_replace_text/approval.json)" \
  | mix run --no-start -e 'Application.ensure_all_started(:edit_runtime); IO.read(:stdio, :line) |> Jason.decode!() |> EditRuntime.Workflow.run() |> Map.take([:status, :jev, :verification, :effects, :request_digest]) |> Map.put(:recorded_at, DateTime.utc_now() |> DateTime.to_iso8601()) |> Map.put(:provider, "cloudflare-ai-gateway") |> Map.put(:model, "typesafe/jev") |> Jason.encode!(pretty: true) |> IO.puts()' 2>/dev/null \
  | sed -n '/^{/,$p' > evals/results-live.json
test "$(cat "$fixture_note")" = published
grep -q '"status": "approved"' evals/results-live.json
printf '%s\n' 'edit proof passed: headless Pi run succeeded and Jev approved the request'
