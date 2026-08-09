/// Exact-root state workspace resolution for resident attach verbs.
library;

import 'package:beads_dart/beads_dart.dart' show BeadsWorkspace, DoltMode;
import 'package:grid_sdk/grid_sdk.dart' show GridStateStore, StoreRefusal;
import 'package:path/path.dart' as p;

import 'station_stores.dart';

/// Help for the resident attach root.
const String stateWorkspaceHelp =
    'The grid home whose .grid/station.lock this verb attaches to. Required; '
    'the state store is never guessed.';

/// Exhaustive result of resolving a resident state workspace.
sealed class StateWorkspaceResult {
  const StateWorkspaceResult();
}

/// The exact state workspace opened beneath [home].
final class StateWorkspaceFound extends StateWorkspaceResult {
  /// Creates a successful exact-root result.
  const StateWorkspaceFound({required this.home, required this.workspace});

  /// The canonical grid home.
  final String home;

  /// The exact workspace rooted beneath `<home>/.grid`.
  final BeadsWorkspace workspace;
}

/// A usage or store-opening refusal rendered by a resident verb.
final class StateWorkspaceRefusal extends StateWorkspaceResult {
  /// Creates a refusal.
  const StateWorkspaceRefusal(this.message, {required this.code});

  /// The user-facing message.
  final String message;

  /// The process exit code.
  final int code;
}

/// Opens `<home>/.grid/.beads` through [openStateStore], never by walk-up.
StateWorkspaceResult resolveStateWorkspace({
  required String stationName,
  required String verb,
  required String? stateWorkspacePath,
}) {
  if (stateWorkspacePath == null || stateWorkspacePath.trim().isEmpty) {
    return StateWorkspaceRefusal(
      '$stationName $verb: --state-workspace is required',
      code: 64,
    );
  }
  final home = p.canonicalize(stateWorkspacePath.trim());
  try {
    final workspace = openStateStore(GridStateStore.forGridRoot(home));
    if (workspace.mode == DoltMode.unknown) {
      throw const FormatException('malformed or missing store metadata');
    }
    return StateWorkspaceFound(home: home, workspace: workspace);
  } on ArgumentError catch (error) {
    return StateWorkspaceRefusal(
      '$stationName $verb: ${error.message}',
      code: 1,
    );
  } on StoreRefusal catch (error) {
    return StateWorkspaceRefusal('$stationName $verb: $error', code: 1);
  } on Object catch (error) {
    return StateWorkspaceRefusal(
      '$stationName $verb: could not open the exact grid state store: $error',
      code: 1,
    );
  }
}
