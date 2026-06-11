#!/usr/bin/env bash
# tool/grid_demo.sh
#
# Self-contained reactivity demo — no credentials, no live server. Spins up a
# hermetic `bd init` workspace, starts `grid watch` against it, and drives a few
# mutations so the typed event stream (BeadCreated / ReadySetChanged /
# BeadUpdated / BeadClosed, each with measured reaction latency) scrolls past.
#
# This is the zero-setup proof that the reactive kernel works. To watch the
# REAL factory instead, run `grid watch` in a workspace backed by the live Dolt
# server with GC_DOLT_PASSWORD set (see the VS Code "grid watch (live factory)"
# target).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$(mktemp -d "${TMPDIR:-/tmp}/grid_demo.XXXXXX")"
cleanup() { rm -rf "$DEMO"; }
trap cleanup EXIT
cd "$DEMO"

bd init --prefix demo >/dev/null 2>&1
echo "▶ hermetic workspace: $DEMO"
echo "▶ grid watch starts now; mutations begin in ~3s …"
echo

# Drive mutations in the background once the watcher has taken its baseline.
(
  jid() { BD_JSON_ENVELOPE=1 bd create "$1" -t "$2" -p "${3:-1}" --json \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['id'])"; }
  sleep 3
  jid "tron lives" molecule 1 >/dev/null
  sleep 1.6
  task=$(jid "reach the I/O tower" task 1)
  sleep 1.6
  BD_JSON_ENVELOPE=1 bd update "$task" --status in_progress >/dev/null 2>&1 || true
  sleep 1.6
  BD_JSON_ENVELOPE=1 bd close "$task" --reason "end of line" >/dev/null 2>&1 || true
) &

dart run "$ROOT/packages/grid_cli/bin/grid.dart" watch --for-seconds 11
wait || true
echo
echo "▶ demo complete — workspace cleaned up"
