#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'usage: run.sh <upstream-checkout> <absolute-bd-executable>' >&2; exit 64; }
upstream_dir="$1"
bd_bin="$2"
[[ "$upstream_dir" = /* && -d "$upstream_dir" ]] || { echo 'upstream checkout must be an absolute directory' >&2; exit 64; }
[[ "$bd_bin" = /* && -x "$bd_bin" ]] || { echo 'bd executable must be an absolute executable' >&2; exit 64; }
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="$(dirname "$bd_bin"):$PATH"
export BD_JSON_ENVELOPE=1
export BD_NON_INTERACTIVE=1
cd "$repo_root/packages/beads_dart"
dart pub get
dart test \
  test/integration/cross_workspace_probe_test.dart \
  test/integration/no_sql_no_hooks_test.dart \
  test/integration/reactive_lifecycle_test.dart \
  test/integration/sql_cli_equivalence_test.dart \
  test/integration/wisp_snapshot_test.dart
corpus_test=test/tool/upstream_protocol_replay_test.dart
corpus_dir="$upstream_dir/cmd/bd/protocol/testdata/corpus"
if [[ ! -d "$corpus_dir" ]]; then
  # The protocol corpus landed upstream after v1.2.2; released tags before it
  # (the release rail's floor v1.0.5 and latest v1.2.2) carry no corpus. Say so
  # loudly and pass — the replay is a main-rail check until a tag carries it.
  echo "CORPUS REPLAY SKIPPED: $corpus_dir is absent at this bd ref" >&2
elif [[ -f "$corpus_test" ]]; then
  BD_PROTOCOL_ROOT="$upstream_dir/cmd/bd/protocol" dart test "$corpus_test"
else
  echo 'A2 corpus replay not landed; tg-7ukf owns this test seam.' >&2
fi
