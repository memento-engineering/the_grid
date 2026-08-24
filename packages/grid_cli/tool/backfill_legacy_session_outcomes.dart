import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';

typedef LegacySessionBackfillReceipt = ({
  int scanned,
  int stamped,
  int skippedMissingCreatedAt,
});

typedef _Options = ({String store, String before});

/// One-time A59 migration for a single state store.
abstract final class LegacySessionOutcomeBackfill {
  /// Stamps unmarked, closed sessions created strictly before [before].
  static Future<LegacySessionBackfillReceipt> run({
    required BdCliService bd,
    required DateTime before,
  }) async {
    final scope = await bd.listScope(
      type: GridIssueTypes.session,
      status: BeadStatus.closed,
    );
    var stamped = 0;
    var skippedMissingCreatedAt = 0;
    for (final session in scope.beads) {
      if (session.metadata.containsKey(SessionBeadKeys.outcome)) continue;
      final createdAt = session.createdAt;
      if (createdAt == null) {
        skippedMissingCreatedAt += 1;
        continue;
      }
      if (!createdAt.toUtc().isBefore(before.toUtc())) continue;
      await bd.update(
        session.id,
        mergeMetadata: const {SessionBeadKeys.outcome: kSessionOutcomeLegacy},
      );
      stamped += 1;
    }
    return (
      scanned: scope.beads.length,
      stamped: stamped,
      skippedMissingCreatedAt: skippedMissingCreatedAt,
    );
  }
}

_Options _parseOptions(List<String> arguments) {
  String? store;
  String? before;
  for (var index = 0; index < arguments.length; index += 2) {
    final flag = arguments[index];
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw ArgumentError('missing value for $flag');
    }
    final value = arguments[index + 1];
    switch (flag) {
      case '--store':
        if (store != null) throw ArgumentError('duplicate --store');
        store = value;
      case '--before':
        if (before != null) throw ArgumentError('duplicate --before');
        before = value;
      default:
        throw ArgumentError.value(flag, 'option', 'unknown option');
    }
  }
  if (store == null) throw ArgumentError('missing --store');
  if (before == null) throw ArgumentError('missing --before');
  return (store: store, before: before);
}

Future<void> main(List<String> arguments) async {
  final options = _parseOptions(arguments);
  final storeInput = Directory(options.store);
  if (storeInput.path != storeInput.absolute.path) {
    throw ArgumentError.value(options.store, '--store', 'must be absolute');
  }
  final receipt = await LegacySessionOutcomeBackfill.run(
    bd: BdCliService(ProcessBdRunner(workspaceRoot: storeInput.path)),
    before: DateTime.parse(options.before).toUtc(),
  );
  stdout.writeln(
    jsonEncode({
      'scanned': receipt.scanned,
      'stamped': receipt.stamped,
      'skipped_missing_created_at': receipt.skippedMissingCreatedAt,
    }),
  );
}
