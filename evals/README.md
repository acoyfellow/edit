# /edit evaluation

The evaluation compares a normal headless Pi run with the `/edit` workflow on the same clean workspace and task.

The evaluation does not use a model judge as the final result. A case passes only when the executable proof passes and the resulting diff stays inside the allowed path set.

## Metrics

- task success;
- proof success;
- unauthorized file changes;
- changed-file count;
- wall-clock time;
- Pi and Jev provider usage when available;
- human approval count;
- denied or inconclusive runs.

The first case is a controlled replacement task. It is a mechanics check, not evidence that `/edit` is better for coding. More real bug-fix cases must be added before publishing a performance claim. `results-local.jsonl` is an unreviewed local receipt and records one run; baseline model behavior is variable.

## Reproduce the evaluation

From a clean checkout, run:

```sh
./scripts/eval.sh
```

The script creates two temporary workspaces from the same starting file. It runs a normal headless Pi edit in one and `/edit` in the other, then records whether the expected file content was produced and how long each run took. Temporary workspaces are removed when the script exits.

To inspect the full safety proof instead, run:

```sh
./scripts/prove.sh
```

That command runs the automated tests, the approved fixture, and the live Jev-backed judgment. A missing or unauthorized provider is recorded as blocked; it is never treated as a passing model decision.

Missing credentials, missing provider access, or an unavailable baseline is recorded as a blocked case. It is never replaced with fake output.
