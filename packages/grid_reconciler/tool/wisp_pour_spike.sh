#!/usr/bin/env bash
# packages/grid_reconciler/tool/wisp_pour_spike.sh
#
# Track 0.2 (M2) — the wisp-pour verb spike. Proves, hermetically and offline,
# how bd 1.0.5 (the pinned version) instantiates a convergence wisp with the
# parent + idempotency surfaces gc's in-process `molecule.Cook` carries — and
# that it is reproducible from the CLI without a live server. Outcome recorded
# in ADR-0000 A15/A16. Re-run to re-verify against a new bd.
#
# Findings (see A15):
#   - `bd mol wisp <proto>` pours a vapor wisp but resolves only a *registered*
#     proto, exposes NO --parent and NO idempotency key, and is not batchable.
#   - The faithful, ATOMIC analog of gc's `PourWisp(parentID, key, vars)` is:
#       1. resolve : bd cook <formula> --mode=runtime --var k=v --json
#       2. pour    : bd create --graph <plan.json> --ephemeral --json
#     where the graph plan's root node carries parent_id + metadata.idempotency_key.
#   - Idempotency is the_grid's own concern: scan the convergence root's children
#     (a parent-child dependency edge) for metadata.idempotency_key before pouring.
# And (A16): `bd batch` CANNOT carry `metadata` or `mol wisp` — transition
# metadata writes use `bd update --metadata` instead.
set -euo pipefail

require_bd() { command -v bd >/dev/null || { echo "bd not on PATH"; exit 1; }; }
require_bd
echo "▶ bd: $(bd version 2>/dev/null | head -1)"

DEMO="$(mktemp -d "${TMPDIR:-/tmp}/wisp_pour_spike.XXXXXX")"
trap 'rm -rf "$DEMO"' EXIT
cd "$DEMO"
bd init --prefix spike >/dev/null 2>&1
echo "▶ hermetic workspace: $DEMO"

# A minimal vapor-phase convergence formula: work → evaluate (the gate's input).
cat > mol-converge-probe.formula.json <<'JSON'
{
  "formula": "mol-converge-probe",
  "description": "Track 0.2 spike — minimal convergence-style wisp",
  "version": 1,
  "type": "workflow",
  "phase": "vapor",
  "vars": { "target": { "description": "what to converge on", "default": "the I/O tower" } },
  "steps": [
    { "id": "work",     "title": "iterate on {{target}}", "type": "task", "priority": 1 },
    { "id": "evaluate", "title": "evaluate {{target}}",    "type": "task", "priority": 1, "needs": ["work"] }
  ]
}
JSON

# The convergence root bead (gc parents each iteration's wisp under it).
ROOT=$(BD_JSON_ENVELOPE=1 bd create "Convergence: mol-converge-probe" -t task -p 1 --json \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['data']['id'])")
KEY="converge:${ROOT}:iter:1"
echo "▶ convergence root=$ROOT  idempotency key=$KEY"

# 1) RESOLVE the formula (runtime mode substitutes vars), then 2) build a graph
# plan whose root wisp node is parented + idempotency-keyed.
BD_JSON_ENVELOPE=1 bd cook mol-converge-probe.formula.json --mode=runtime --var target=tron --json \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
nodes=[{'key':'wisp','title':'Convergence wisp iter 1','type':'epic',
        'parent_id':'$ROOT','metadata':{'idempotency_key':'$KEY'}}]
edges=[]
for s in d['steps']:
    nodes.append({'key':s['id'],'title':s['title'],'type':s.get('type','task'),
                  'priority':s.get('priority',2),'parent_key':'wisp'})
    for need in (s.get('needs') or s.get('depends_on') or []):
        edges.append({'from_key':s['id'],'to_key':need,'type':'blocks'})
print(json.dumps({'commit_message':'pour wisp $KEY','nodes':nodes,'edges':edges}))
" > plan.json

# 2) POUR atomically — one transaction, one DOLT_COMMIT.
WISP=$(BD_JSON_ENVELOPE=1 bd create --graph plan.json --ephemeral --json \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['data']['ids']['wisp'])")
echo "▶ poured wisp=$WISP"

echo "▶ verifying the wisp carries the gc-required properties …"
BD_JSON_ENVELOPE=1 bd show "$WISP" --json | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']; b=d[0] if isinstance(d,list) else d
assert b.get('ephemeral') is True, 'wisp must be ephemeral'
assert (b.get('metadata') or {}).get('idempotency_key')=='$KEY', 'idempotency_key must be set'
print('  ✓ ephemeral + metadata.idempotency_key =', b['metadata']['idempotency_key'])
"
BD_JSON_ENVELOPE=1 bd children "$ROOT" --json | python3 -c "
import json,sys
ids=[b.get('id') for b in (json.load(sys.stdin).get('data') or [])]
assert '$WISP' in ids, 'convergence root must resolve the wisp as a child'
print('  ✓ bd children <root> resolves the wisp (FindByIdempotencyKey works over this)')
"

echo "▶ confirming bd batch CANNOT carry metadata (A16) …"
if printf 'update %s metadata={\"x\":\"y\"}\n' "$ROOT" | bd batch >/dev/null 2>&1; then
  echo "  ! unexpected: bd batch accepted a metadata update — re-check A16"; exit 1
else
  echo "  ✓ bd batch rejects metadata updates (transition metadata uses bd update --metadata)"
fi

echo "✓ wisp-pour spike passed — pour is offline-reproducible and atomic (ADR-0000 A15)"
