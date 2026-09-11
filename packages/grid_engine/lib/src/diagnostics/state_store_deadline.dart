library;

import 'dart:async';

import 'package:beads_dart/beads_dart.dart';

/// Durable disposition reason for a session retired after a mint-path timeout.
const String kMintTimeoutVoidReason = 'mint-timeout';

/// Names the deadline carried by [error], or returns no fields for a
/// non-timeout error.
Map<String, String> stateStoreDeadlineMetadata(Object error) => switch (error) {
  TimeoutException() => <String, String>{
    'deadlineConstant': 'DoltQueryService.queryTimeout',
    'deadlineMs': DoltQueryService.queryTimeout.inMilliseconds.toString(),
  },
  BdTimeoutException(:final command, :final timeout)
      when _isMoleculePourCommand(command) =>
    <String, String>{
      'deadlineConstant': 'BdCliService.pourTimeout',
      'deadlineMs': timeout.inMilliseconds.toString(),
    },
  BdTimeoutException(:final timeout) => <String, String>{
    'deadlineConstant': 'BdRunner.run(timeout)',
    'deadlineMs': timeout.inMilliseconds.toString(),
  },
  _ => const <String, String>{},
};

bool _isMoleculePourCommand(List<String> command) =>
    command.length > 1 && command[0] == 'create' && command[1] == '--graph' ||
    command.length > 2 &&
        command[0] == 'bd' &&
        command[1] == 'create' &&
        command[2] == '--graph';
