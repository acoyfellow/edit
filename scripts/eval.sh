#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
project_root=$PWD
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

run_case() {
  local mode=$1
  local workspace="$root/$mode"
  mkdir -p "$workspace"
  printf 'draft\n' > "$workspace/note.txt"
  local started=$(date +%s%N)

  if [[ "$mode" == baseline ]]; then
    (cd "$workspace" && pi -p --no-session --no-extensions --tools read,write 'Change the word draft to published in note.txt. Do not change any other file. Read the file, edit it, and verify it.') > "$root/$mode.out" 2>&1
  else
    python3 - "$workspace" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
request = {
    "version": 1,
    "workspace_root": str(root),
    "operations": [{"type": "replace_text", "path": "note.txt", "expected": "draft\n", "replacement": "published\n"}],
    "verification": {"type": "file_equals", "path": "note.txt", "expected": "published\n"},
    "capabilities": ["workspace.read", "workspace.write"],
}
raw = json.dumps(request, sort_keys=True, separators=(",", ":")).encode()
approval = {"request_digest": hashlib.sha256(raw).hexdigest(), "capabilities": request["capabilities"]}
(root / "request.json").write_text(json.dumps(request))
(root / "approval.json").write_text(json.dumps(approval))
PY
    payload='{"id":"edit-eval","type":"prompt","message":"/edit request.json approval.json"}'
    (cd "$root/$mode" && {
      printf '%s\n' "$payload"
      for _ in $(seq 1 90); do
        grep -q '"message":"edit: ' "$root/$mode.out" 2>/dev/null && break
        sleep 1
      done
    } | EDIT_RUNTIME_DIR="$project_root" pi --mode rpc --no-session --no-extensions -e "$HOME/.pi/agent/extensions/edit.ts" --no-tools) > "$root/$mode.out" 2>&1
  fi

  local ended=$(date +%s%N)
  local content
  content=$(cat "$workspace/note.txt")
  local success=false
  [[ "$content" == published ]] && success=true
  printf '{"mode":"%s","success":%s,"elapsed_ms":%s,"content":"%s"}\n' "$mode" "$success" "$(( (ended - started) / 1000000 ))" "$content"
}

run_case baseline
run_case edit
