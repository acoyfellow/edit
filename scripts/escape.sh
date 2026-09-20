#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

printf '%s\n' '== escape suite: executor only (no Jev)'
env -u AI_GATEWAY_TOKEN -u CLOUDFLARE_ACCOUNT_ID -u TYPESAFE_API_KEY mix run --no-start evals/escape_suite.exs 2>/dev/null

if [[ -n "${TYPESAFE_API_KEY:-}" || ( -n "${AI_GATEWAY_TOKEN:-}" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" ) ]]; then
  printf '\n%s\n' '== escape suite: with Jev'
  mix run --no-start evals/escape_suite.exs 2>/dev/null
fi
