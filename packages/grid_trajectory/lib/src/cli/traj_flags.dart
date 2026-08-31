/// The `traj` verbs' shared flag surface.
///
/// Grid-home resolution follows the resident verbs' rule exactly (grid_cli's
/// `state_workspace.dart`, which this leaf package cannot import): the root is
/// REQUIRED, used EXACTLY as given after canonicalization, and never found by
/// walking up from the cwd.
library;

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const String gridHomeHelp =
    'The grid home whose .grid/.beads dolt sql-server hosts the trajectory '
    'database. Required; the store is never guessed.';

/// Adds `--state-workspace` (with the `--grid-home` spelling the station
/// verbs use) to [parser].
void addGridHomeOption(ArgParser parser) {
  parser.addOption(
    'state-workspace',
    aliases: const ['grid-home'],
    help: gridHomeHelp,
  );
}

/// The canonical grid home, or null after writing the refusal to [writeErr].
String? gridHomeFrom(
  ArgResults args,
  void Function(String) writeErr,
  String verb,
) {
  final value = args.option('state-workspace');
  if (value == null || value.trim().isEmpty) {
    writeErr('traj $verb: --state-workspace is required.');
    return null;
  }
  return p.canonicalize(value.trim());
}

/// A positive integer flag, or null after writing the refusal.
int? positiveIntFrom(
  ArgResults args,
  String option,
  void Function(String) writeErr,
  String verb, {
  required int fallback,
}) {
  final raw = args.option(option);
  if (raw == null) return fallback;
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    writeErr('traj $verb: --$option must be a positive integer (got "$raw").');
    return null;
  }
  return value;
}
