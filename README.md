# /edit

`/edit` helps Pi make small code changes without taking the keys away from you.

It reads a request, shows what it wants to do, asks for your approval, and changes only the files and actions you allowed. Then it checks the result and leaves a receipt.

## Why use it?

Use `/edit` when a change should be small, reviewable, and easy to undo.

- **You stay in charge.** Nothing changes until you approve the exact request.
- **Small steps.** The tool can only use the actions you grant it.
- **Safe paths.** It cannot wander outside the workspace.
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
./scripts/prove.sh
```

That live check needs an approved Jev provider. If the provider is unavailable, `/edit` stops instead of pretending that a review happened.

## What it does not do

`/edit` does not make broad changes, skip approval, invent a review, or call a successful run when its check failed.

## Evaluation and proof

| What to inspect | Link | What it tells you |
| --- | --- | --- |
| Evaluation guide | [`evals/README.md`](evals/README.md) | What is measured and what is not claimed |
| Evaluation tasks | [`evals/tasks.json`](evals/tasks.json) | The exact cases being run |
| Local evaluation receipt | [`evals/results-local.jsonl`](evals/results-local.jsonl) | A recorded baseline-versus-`/edit` run |
| Live evaluation receipt | [`evals/results-live-blocked.json`](evals/results-live-blocked.json) | A blocked live-provider result, without fake output |
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

The evaluation is deliberately modest: the current fixture checks mechanics, not coding quality or speed. Add more bug fixes, test changes, refactors, and failure cases before making a performance claim.

## Status

The local checks pass. The live Jev check is published as blocked because the current provider route returned `403`. See [`evals/results-live-blocked.json`](evals/results-live-blocked.json).
