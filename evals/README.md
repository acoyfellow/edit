# /edit evaluation

This page summarizes every recorded result in this folder. Each row links to the file it came from. The task set is still one mechanics check, so nothing here is a general coding-quality claim.

## Results at a glance

| Check | Result | Runs | Source |
| --- | --- | --- | --- |
| Live Jev judgment on the approved request | **Approved** (`typesafe/jev` via Cloudflare AI Gateway) | 1 | [`results-live.json`](results-live.json) |
| Headless Pi run applies the approved change | Pass | 4 of 4 | [`results-local.jsonl`](results-local.jsonl) |
| Baseline Pi completes the same task | Pass 1 of 4 | 4 | [`results-local.jsonl`](results-local.jsonl) |
| Approved change touches only the intended file | Pass | 4 of 4 | [`results-live.json`](results-live.json) `effects` |
| Changed request is denied | Pass | test | [`../test/workflow_test.exs`](../test/workflow_test.exs) |
| Missing capability is denied | Pass | test | [`../test/workflow_test.exs`](../test/workflow_test.exs) |
| Path outside the workspace is denied | Pass | test | [`../test/workflow_test.exs`](../test/workflow_test.exs) |

## Baseline versus `/edit`

Task: change `draft` to `published` in `note.txt` and touch nothing else. Defined in [`tasks.json`](tasks.json). Both arms start from a fresh temporary workspace each run.

| Run | Baseline (`pi -p`, default model, `--tools read,write`) | `/edit` (`pi --mode rpc --no-tools -e edit.ts`) |
| --- | --- | --- |
| 1 | Failed, 29.0 s, file unchanged | Pass, 11.9 s |
| 2 | Failed, 4.6 s, file unchanged | Pass, 6.6 s |
| 3 | Failed, 4.7 s, file unchanged | Pass, 9.4 s |
| 4 | Pass, 9.5 s | Pass, 9.1 s |

**What happened in the baseline failures.** The model wrote a malformed tool call (a literal `</tool_call>` tag as text), the turn ended, and the file was never changed. Nothing reported the failure; the workspace was simply still `draft`. The `/edit` arm cannot end that way: the run is only reported as succeeded after the file check passes.

**What this does not show.** Four runs of one tiny task, on one default model (`gpt-5.6-luna`), is not a benchmark. It shows one concrete failure mode that proof-gating catches, and it shows the timings are in the same range. Treat the pass counts as an anecdote until the task set grows.

## Live Jev judgment

The full proof asks Jev whether the exact approved request should proceed, before any file changes.

| Field | Value |
| --- | --- |
| Provider | Cloudflare Workers AI through AI Gateway (`cf-aig-gateway-id`) |
| Model | `typesafe/jev` (`jev-1.13.0`) |
| Decision | `approve` |
| Verification | `file_equals note.txt` passed |
| Effects | one write, `note.txt` |
| Request digest | recorded in [`results-live.json`](results-live.json) |

Jev's decision is recorded next to the executable check. It does not replace it: a Jev approval with a failed file check is still a failed run.

## What each check measures

- **Task success**: the workspace ends in the expected state.
- **Bounded change**: only the files named in the request changed.
- **Denials**: a changed request, an ungranted capability, or a path outside the workspace is refused before any write.
- **Proof**: the run is only called successful when the executable check passes.
- **Judgment**: Jev's decision is recorded alongside the proof, not instead of it.

## What is not measured yet

- Real bug fixes, test changes, and refactors.
- More than one model on the baseline arm.
- An adversarial escape suite: path tricks, approval replay, smuggled operations, prompt injection from repository files.
- Files touched beyond the intended set on larger tasks.
- Jev false rejections on legitimate edits.

Those are the next additions.

## Reproduce

Set the provider once in your shell. The token is read from the environment and never written anywhere.

```sh
export AI_GATEWAY_TOKEN=...
export CLOUDFLARE_ACCOUNT_ID=...
export CLOUDFLARE_AI_GATEWAY_ID=default
```

Baseline versus `/edit`, one JSON line per arm:

```sh
./scripts/eval.sh
```

Full proof, including tests, the headless Pi run, and the live Jev judgment. It writes `results-live.json`:

```sh
./scripts/prove.sh
```

Both scripts create fresh temporary workspaces and reset the fixture when they finish.
