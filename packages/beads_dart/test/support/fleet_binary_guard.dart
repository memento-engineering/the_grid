import 'dart:io';

import 'package:beads_dart/src/services/beads_workspace.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The reason the live tests skip with when the `bd` on PATH is not the binary
/// that wrote the store.
///
/// A harness whose binary-under-test can be FOREIGN must not touch a live
/// store: that is D-BD1's store-migration rule applied to tests. bd 1.3 refuses
/// a store a pre-upgrade proxy still holds — and creates a cooperative
/// `.beads/proxieddb.gate.lock` on its way out — so a compatibility run against
/// an arbitrary bd would mutate the fleet's own workspace.
const kForeignBinaryReason =
    "binary under test differs from the store's writer; live equivalence runs "
    'only under the fleet binary';

/// The reason used when the discovered store carries no writer stamp at all.
const kUnstampedStoreReason =
    'store carries no .beads/.local_version stamp; the writer binary cannot be '
    'proven';

/// The guard's PURE verdict: null means run, non-null is the skip reason.
String? foreignBinaryReason({
  required String? storeStamp,
  required String? binaryVersion,
}) {
  final stamp = storeStamp?.trim() ?? '';
  if (stamp.isEmpty) return kUnstampedStoreReason;
  final version = binaryVersion?.trim() ?? '';
  if (version.isEmpty || version != stamp) return kForeignBinaryReason;
  return null;
}

/// The version token `bd version` prints, or null when bd is absent, fails, or
/// prints another shape.
///
/// Observed shapes: `bd version HEAD-a45199a (Homebrew: HEAD@a45199a546f9)`
/// (the fleet binary) and `bd version 1.3.0-rc.1 (9c6a69ec1: ...)` (the rc),
/// yielding `HEAD-a45199a` and `1.3.0-rc.1` respectively. The fleet stamp in
/// `.beads/.local_version` is `HEAD-a45199a`, so the token compares directly.
String? bdVersionOnPath({String executable = 'bd'}) {
  final ProcessResult result;
  try {
    result = Process.runSync(executable, const ['version']);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) return null;
  final line = '${result.stdout}'.split('\n').first.trim();
  const prefix = 'bd version ';
  if (!line.startsWith(prefix)) return null;
  final rest = line.substring(prefix.length).trim();
  final space = rest.indexOf(' ');
  return space < 0 ? rest : rest.substring(0, space);
}

/// The `.beads/.local_version` stamp bd writes for the binary that owns the
/// store, or null when the store carries none.
String? storeWriterStamp(String workspaceRoot) {
  final file = File(p.join(workspaceRoot, '.beads', '.local_version'));
  return file.existsSync() ? file.readAsStringSync().trim() : null;
}

/// The live tests' OWN DEFAULT: skips and returns true when the `bd` on PATH is
/// not the store's writer. Returns false — run the test — otherwise, and for a
/// null [workspace] (the caller's own no-workspace skip then fires).
///
/// Deliberately NOT an invoker-selected mode: `tool/bd_compatibility/run.sh`
/// keeps its two-argument form and gains no third argument, so a foreign
/// binary can never be told to run the live tests anyway
/// (`the_grid#hermetic-guard-is-the-live-tests-own-default`).
bool skippedForForeignBinary(BeadsWorkspace? workspace) {
  if (workspace == null) return false;
  final reason = foreignBinaryReason(
    storeStamp: storeWriterStamp(workspace.root),
    binaryVersion: bdVersionOnPath(),
  );
  if (reason == null) return false;
  markTestSkipped(reason);
  return true;
}
