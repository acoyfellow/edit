# /edit

`/edit` helps Pi make small code changes without taking the keys away from you.

It reads a request, shows what it wants to do, asks for your approval, and changes only the files and actions you allowed. Then it checks the result and leaves a receipt.

## Why use it?

Use `/edit` when a change should be small, reviewable, and easy to undo.

- **You stay in charge.** Nothing changes until you approve the exact request.
- **Small steps.** The tool can only use the actions you grant it.
- **Safe paths.** It cannot wander outside the workspace, through `..`, absolute paths, symlinks, or extra hard links.
- **Folders you name.** Each request lists which folders may receive which commands. Anything else is refused.
- **Undo on failure.** If the check after a change fails, the original content is put back.
- **Proof after the change.** A check must pass before the run is called successful.
- **Clear receipts.** Each run records what happened.

## Try it

Install the Pi extension at `~/.pi/agent/extensions/edit.ts`, then reload Pi:

```text
/edit fixtures/approved_replace_text/request.json fixtures/approved_replace_text/approval.json
```

The sample changes `draft` to `published` in `note.txt`.

## Check it locally

```sh
mix deps.get
mix test
bun test
```

The full check also asks Jev to review the proposed change:

```sh
export AI_GATEWAY_TOKEN=...
export CLOUDFLARE_ACCOUNT_ID=...
export CLOUDFLARE_AI_GATEWAY_ID=default
./scripts/prove.sh
```

Jev runs as `typesafe/jev` on Cloudflare Workers AI through your AI Gateway. The token stays in your shell environment; it is never written to source, logs, or output. If the provider is unavailable, `/edit` stops instead of pretending that a review happened.

## What it does not do

`/edit` does not make broad changes, skip approval, invent a review, or call a successful run when its check failed.

## Evaluation and proof

| What to inspect | Link | What it tells you |
| --- | --- | --- |
| Evaluation guide | [`evals/README.md`](evals/README.md) | What is measured and what is not claimed |
| Evaluation tasks | [`evals/tasks.json`](evals/tasks.json) | The exact cases being run |
| Local evaluation receipt | [`evals/results-local.jsonl`](evals/results-local.jsonl) | A recorded baseline-versus-`/edit` run |
| Task matrix | [`evals/results-tasks.jsonl`](evals/results-tasks.jsonl) | Five tasks × 5 runs × two baseline models plus `/edit` |
| Escape suite | [`evals/results-escape-executor_only.json`](evals/results-escape-executor_only.json) | Eighteen requests that must be refused, run without Jev: 0 escapes |
| Labeled Jev set | [`evals/results-judgment.json`](evals/results-judgment.json) | Ten labeled requests: precision 0.71, recall 1.0 |
| Live Jev receipt | [`evals/results-live.json`](evals/results-live.json) | The recorded Jev decision, verification, and effects from the full proof |
| Reproducible evaluation command | [`scripts/eval.sh`](scripts/eval.sh) | The command that creates fresh workspaces and runs both paths |
| Full proof command | [`scripts/prove.sh`](scripts/prove.sh) | Tests, the fixture, and the live Jev-backed path |

Run the repeatable local checks from a clean checkout:

```sh
mix deps.get
mix test
bun test
./scripts/eval.sh
```

For the complete proof, configure an approved Jev provider and run:

```sh
./scripts/prove.sh
```

The evaluation now includes folder policy, an 18-case escape suite in both modes, five task workspaces, a 75-run task matrix, and a labeled Jev set. See [`evals/README.md`](evals/README.md).

## Status

Tests pass. Escape suite is 0/18 in both modes on the last successful proof. Folder policy is deny-by-default. A later live Jev call on this machine returned HTTP 401 and was not retried, so `./scripts/prove.sh` is not currently green.
