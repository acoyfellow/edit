#!/usr/bin/env bash
set -euo pipefail

printf 'GitHub CLI: '
if gh auth status >/dev/null 2>&1; then printf '%s\n' ready; else printf '%s\n' missing; fi
printf 'Wrangler: '
if wrangler whoami >/dev/null 2>&1; then printf '%s\n' ready; else printf '%s\n' missing; fi
printf 'Jev provider: '
if [[ -n "${TYPESAFE_API_KEY:-}" || ( -n "${AI_GATEWAY_TOKEN:-}" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" ) ]]; then printf '%s\n' ready; else printf '%s\n' missing; fi
