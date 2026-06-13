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
#
# ⚠ A15 CORRECTION (2026-06-13): this script pours with `--ephemeral` to assert
# the mechanism, but the Track-E actuator must pour PERSISTENT (drop
# `--ephemeral`) — gc's convergence iterations are committed `issues` beads
# (molecule.Cook → store.Create sets no Ephemeral), not vapor wisps. This file
# proves the atomic graph-apply mechanism, not the durability flag.
#
# Track A verifier follow-ups (2026-06-12), pinned below against bd 1.0.5:
#   - `bd update --metadata` MERGES into existing metadata (keys carried
#     overwrite; keys absent from the update are preserved) — source:
#     beads/cmd/bd/update.go:546-573 `mergeMetadata`; verified empirically
#     in section ▶ metadata-semantics. So a MetadataWrite sequence maps to
#     updates carrying ONLY the named keys — no read-modify-write of the
#     whole map, no clobber of agent-owned `convergence.agent_verdict*`.
#   - `bd update --metadata` WORKS on a CLOSED bead — required by trap 1
#     (`last_processed_wisp` written AFTER CloseBead, handler.go:699-704).
#   - Burn = `bd delete` (post-order subtree), NEVER close — closing a
#     speculative wisp permanently inflates deriveIterationCount (trap 2).
#   - Speculative pour (gc PourSpeculativeWisp) = the same graph plan with
#     each actionable node poured as type `gate` (ready-excluded) and its
#     real type/assignee/routing stashed under `gc.deferred_type` /
#     `gc.deferred_assignee` / `gc.deferred_routed_to` /
#     `gc.deferred_execution_routed_to` (molecule.go:1009-1026,
#     graph_apply.go:268-287). ActivateWisp = per-node `bd update` promoting
#     the deferred values back (cmd/gc/convergence_store.go:204-246).
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

echo "▶ metadata-semantics: merge-vs-replace (mergeMetadata, beads update.go:546-573) …"
BD_JSON_ENVELOPE=1 bd update "$ROOT" --json \
  --metadata '{"convergence.state":"active","convergence.agent_verdict":"approve"}' >/dev/null
BD_JSON_ENVELOPE=1 bd update "$ROOT" --json \
  --metadata '{"convergence.state":"waiting_manual"}' >/dev/null
BD_JSON_ENVELOPE=1 bd show "$ROOT" --json | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']; b=d[0] if isinstance(d,list) else d
m=b.get('metadata') or {}
assert m.get('convergence.state')=='waiting_manual', m
assert m.get('convergence.agent_verdict')=='approve', \
    'REPLACE semantics detected — agent_verdict clobbered: %r' % m
print('  ✓ bd update --metadata MERGES: untouched keys survive a partial update')
"

echo "▶ metadata-semantics: write on a CLOSED bead (trap 1 — lpw after CloseBead) …"
# Close the wisp's steps first (mirrors reality: a terminating root has only
# closed/burned children), then the wisp itself.
BD_JSON_ENVELOPE=1 bd children "$WISP" --json | python3 -c "
import json,sys
print('\n'.join(b['id'] for b in (json.load(sys.stdin).get('data') or [])))
" | while read -r child; do
  [ -n "$child" ] && BD_JSON_ENVELOPE=1 bd close "$child" \
    --reason "convergence: iteration closed by manual approve" --json >/dev/null
done
BD_JSON_ENVELOPE=1 bd close "$WISP" --reason "convergence: workflow handler closing root after terminate" --json >/dev/null
BD_JSON_ENVELOPE=1 bd update "$WISP" --json \
  --metadata '{"convergence.last_processed_wisp":"probe-after-close"}' >/dev/null
BD_JSON_ENVELOPE=1 bd show "$WISP" --json | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']; b=d[0] if isinstance(d,list) else d
assert b.get('status')=='closed', b.get('status')
m=b.get('metadata') or {}
assert m.get('convergence.last_processed_wisp')=='probe-after-close', m
print('  ✓ bd update --metadata succeeds on a closed bead (terminal commit marker is writable)')
"

echo "▶ speculative pour (gc PourSpeculativeWisp analog): deferred type/assignee/routing …"
KEY2="converge:${ROOT}:iter:2"
BD_JSON_ENVELOPE=1 bd cook mol-converge-probe.formula.json --mode=runtime --var target=tron --json \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
# Speculative deferral per molecule.go:1009-1026 / graph_apply.go:268-287:
# actionable nodes pour as ready-excluded type 'gate'; the real type,
# assignee, and routing are stashed under gc.deferred_* for activation.
nodes=[{'key':'wisp','title':'Convergence wisp iter 2','type':'epic',
        'parent_id':'$ROOT','metadata':{'idempotency_key':'$KEY2'}}]
edges=[]
for s in d['steps']:
    nodes.append({'key':s['id'],'title':s['title'],'type':'gate',
                  'priority':s.get('priority',2),'parent_key':'wisp',
                  'metadata':{'gc.deferred_type':s.get('type','task'),
                              'gc.deferred_assignee':'rig/polisher',
                              'gc.deferred_routed_to':'rig/polisher'}})
    for need in (s.get('needs') or s.get('depends_on') or []):
        edges.append({'from_key':s['id'],'to_key':need,'type':'blocks'})
print(json.dumps({'commit_message':'pour speculative wisp $KEY2','nodes':nodes,'edges':edges}))
" > plan2.json
IDS2=$(BD_JSON_ENVELOPE=1 bd create --graph plan2.json --ephemeral --json \
  | python3 -c "import json,sys;d=json.load(sys.stdin)['data']['ids'];print(d['wisp'],d['work'],d['evaluate'])")
WISP2=$(echo "$IDS2" | cut -d' ' -f1)
STEP2=$(echo "$IDS2" | cut -d' ' -f2)
STEP2B=$(echo "$IDS2" | cut -d' ' -f3)
BD_JSON_ENVELOPE=1 bd show "$STEP2" --json | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']; b=d[0] if isinstance(d,list) else d
m=b.get('metadata') or {}
assert b.get('issue_type')=='gate' and not b.get('assignee'), b
assert m.get('gc.deferred_type')=='task' and m.get('gc.deferred_assignee')=='rig/polisher', m
print('  ✓ speculative step poured unassigned as type=gate with gc.deferred_* stashed')
"
# ⚠ Pinned observation: bd children EXCLUDES gate-typed children entirely —
# a speculative wisp's steps are invisible to bd children (and bd ready).
# Enumeration for activation/burn must come from the pour's returned id map
# or the GraphSnapshot, never from bd children.
BD_JSON_ENVELOPE=1 bd children "$WISP2" --json | python3 -c "
import json,sys
kids=json.load(sys.stdin).get('data') or []
assert kids==[], 'bd children unexpectedly surfaces gate-typed steps: %r' % kids
print('  ✓ bd children hides gate-typed (speculative) steps — enumerate via snapshot/id map')
"
# ActivateWisp analog: promote deferred type/assignee/routing per node.
BD_JSON_ENVELOPE=1 bd update "$STEP2" --json -t task --assignee rig/polisher \
  --metadata '{"gc.routed_to":"rig/polisher"}' >/dev/null
BD_JSON_ENVELOPE=1 bd show "$STEP2" --json | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']; b=d[0] if isinstance(d,list) else d
m=b.get('metadata') or {}
assert b.get('issue_type')=='task' and b.get('assignee')=='rig/polisher', b
assert m.get('gc.routed_to')=='rig/polisher', m
print('  ✓ activation promotes deferred type/assignee/routing via bd update')
"

echo "▶ burn verb: post-order subtree bd delete (trap 2 — never close) …"
# Post-order: steps first, wisp root last — ids from the pour's id map
# (bd children cannot enumerate the gate-typed steps, see above).
bd delete "$STEP2B" --force >/dev/null 2>&1
bd delete "$STEP2" --force >/dev/null 2>&1
bd delete "$WISP2" --force >/dev/null 2>&1
if BD_JSON_ENVELOPE=1 bd show "$WISP2" --json >/dev/null 2>&1; then
  echo "  ! burned wisp still resolvable — delete did not remove it"; exit 1
fi
echo "  ✓ bd delete burns the speculative subtree (it can never inflate deriveIterationCount)"

echo "✓ wisp-pour spike passed — pour is offline-reproducible and atomic (ADR-0000 A15)"
