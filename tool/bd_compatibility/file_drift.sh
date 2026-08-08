#!/usr/bin/env bash
set -euo pipefail
sha="${1:-}"
run_url="${2:-}"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'upstream SHA must be 40 lowercase hex characters' >&2; exit 64; }
[[ "$run_url" == https://* ]] || { echo 'run URL must use https' >&2; exit 64; }
bd_bin="${BD_BIN:-bd}"
description="Scheduled bd drift rail failed against gastownhall/beads@$sha. CI: $run_url"
BD_JSON_ENVELOPE=1 BD_NON_INTERACTIVE=1 "$bd_bin" create \
  "bd drift alarm: $sha" \
  --type task --priority 1 --status open \
  --labels bd-drift,ready \
  --external-ref "bd-upstream:$sha" \
  --description "$description" \
  --actor grid-controller --json
