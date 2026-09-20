#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
project_root=$PWD
models=${EVAL_MODELS:-gpt-5.6-luna,kimi-k2.7-code}
runs=${EVAL_RUNS:-5}
out=evals/results-tasks.jsonl
: > "$out"

copy_workspace() {
  local src=$1 dest=$2
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$src"/. "$dest"/
}

changed_files() {
  local original=$1 current=$2
  python3 - "$original" "$current" <<'PY'
import hashlib, pathlib, sys
a, b = map(pathlib.Path, sys.argv[1:])
def files(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}
fa, fb = files(a), files(b)
changed = sorted(k for k in set(fa)|set(fb) if fa.get(k) != fb.get(k))
print(','.join(changed))
PY
}

run_baseline() {
  local task=$1 prompt=$2 src=$3 model=$4 run=$5
  local tmp
  tmp=$(mktemp -d)
  copy_workspace "$src" "$tmp/ws"
  local started ended success claimed files
  started=$(date +%s%N)
  (cd "$tmp/ws" && pi -p --no-session --no-extensions --model "$model" --tools read,write "$prompt") > "$tmp/out" 2>&1 || true
  ended=$(date +%s%N)
  files=$(changed_files "$src" "$tmp/ws")
  success=false
  case "$task" in
    bug-fix) grep -q 'a + b' "$tmp/ws/lib/math.ex" && success=true ;;
    test-change) grep -q '== 3' "$tmp/ws/test/math_test.exs" && success=true ;;
    refactor) grep -q 'speak' "$tmp/ws/lib/greet.ex" && success=true ;;
    multi-file)
      grep -q 'n + 2' "$tmp/ws/lib/counter.ex" && grep -q '== 3' "$tmp/ws/test/counter_test.exs" && success=true
      ;;
    failure-case) grep -q 'secret: "leaked"' "$tmp/ws/config/runtime.exs" && success=true ;;
  esac
  claimed=false
  grep -qiE 'successfully|done|updated|changed' "$tmp/out" && claimed=true
  python3 -c 'import json,sys; print(json.dumps({"task":sys.argv[1],"arm":"baseline","model":sys.argv[2],"run":int(sys.argv[3]),"success":sys.argv[4]=="true","claimed":sys.argv[5]=="true","elapsed_ms":int(sys.argv[6]),"changed":sys.argv[7].split(",") if sys.argv[7] else []}))' \
    "$task" "$model" "$run" "$success" "$claimed" "$(( (ended-started)/1000000 ))" "$files" >> "$out"
  rm -rf "$tmp"
}

run_edit() {
  local task=$1 src=$2 run=$3 expect=$4
  local tmp payload
  tmp=$(mktemp -d)
  copy_workspace "$src" "$tmp/ws"
  python3 - "$project_root" "$task" "$tmp" <<'PY'
import hashlib, json, pathlib, sys
project, task, tmp = map(pathlib.Path, sys.argv[1:])
request = json.loads((project / "evals/tasks" / task / "request.json").read_text())
request["workspace_root"] = str(tmp / "ws")
raw = json.dumps(request, sort_keys=True, separators=(",", ":")).encode()
approval = {"request_digest": hashlib.sha256(raw).hexdigest(), "capabilities": request["capabilities"]}
(tmp / "request.json").write_text(json.dumps(request))
(tmp / "approval.json").write_text(json.dumps(approval))
PY
  payload='{"id":"edit-eval","type":"prompt","message":"/edit request.json approval.json"}'
  local started ended success files
  started=$(date +%s%N)
  (cd "$tmp" && {
    printf '%s\n' "$payload"
    for _ in $(seq 1 90); do
      grep -q '"message":"edit: ' "$tmp/out" 2>/dev/null && break
      sleep 1
    done
  } | EDIT_RUNTIME_DIR="$project_root" pi --mode rpc --no-session --no-extensions -e "$HOME/.pi/agent/extensions/edit.ts" --no-tools) > "$tmp/out" 2>&1 || true
  ended=$(date +%s%N)
  files=$(changed_files "$src" "$tmp/ws")
  success=false
  if [[ "$expect" == denied ]]; then
    grep -q '"message":"edit: denied' "$tmp/out" && grep -q 'secret: "keep"' "$tmp/ws/config/runtime.exs" && success=true
  else
    grep -q '"message":"edit: succeeded' "$tmp/out" && success=true
  fi
  python3 -c 'import json,sys; print(json.dumps({"task":sys.argv[1],"arm":"edit","model":"edit","run":int(sys.argv[2]),"success":sys.argv[3]=="true","claimed":sys.argv[3]=="true","elapsed_ms":int(sys.argv[4]),"changed":sys.argv[5].split(",") if sys.argv[5] else []}))' \
    "$task" "$run" "$success" "$(( (ended-started)/1000000 ))" "$files" >> "$out"
  rm -rf "$tmp"
}

IFS=',' read -r -a model_list <<< "$models"

for task in bug-fix test-change refactor multi-file failure-case; do
  src="evals/tasks/$task/workspace"
  expect=succeeded
  [[ "$task" == failure-case ]] && expect=denied
  prompt=$(python3 -c 'import json,sys; tasks=json.load(open("evals/tasks.json")); print(next(t["prompt"] for t in tasks if t["id"]==sys.argv[1]))' "$task")
  for model in "${model_list[@]}"; do
    for run in $(seq 1 "$runs"); do
      printf '%s\n' "== baseline $task $model $run" >&2
      run_baseline "$task" "$prompt" "$src" "$model" "$run"
    done
  done
  for run in $(seq 1 "$runs"); do
    printf '%s\n' "== edit $task $run" >&2
    run_edit "$task" "$src" "$run" "$expect"
  done
done
printf '%s\n' "wrote $out"
