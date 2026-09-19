# edit

`/edit` is a Pi extension for bounded, evidence-backed code changes.

The Pi extension is the control surface. A local Elixir runtime uses Jido to coordinate an approved workflow and Jev to judge the proposed edit when a live provider credential is available.

The runtime accepts newline-delimited JSON on standard input and emits one JSON receipt per request. It does not accept ambient credentials other than the configured Jev provider credential.

## Local verification

```sh
mix deps.get
mix test
bun test
```

The full proof requires a live Jev provider credential:

```sh
./scripts/prove.sh
```

The proof refuses to continue when `TYPESAFE_API_KEY` is missing and no `CLOUDFLARE_API_TOKEN` plus `CLOUDFLARE_ACCOUNT_ID` pair is present. It does not substitute fake model output.

## Pi installation

The extension is installed at `~/.pi/agent/extensions/edit.ts` during local development. Reload Pi with `/reload` after changing it.

Use the command with a request and approval fixture:

```text
/edit fixtures/approved_replace_text/request.json fixtures/approved_replace_text/approval.json
```

The approval digest binds the exact request. The runtime rejects a changed request, unsupported operation, path escape, or failed verification.

## Current boundary

The local fixture proves Jido coordination, bounded file replacement, approval binding, verification, and a receipt. A live Jev judgment and baseline evaluation remain required before release.
