/// The §5 notification seam — fenced-out clause (c)'s "stdout + flare".
///
/// The appender pushes every operator-relevant transition through one
/// injectable sink: fenced out, guarded-reconnect inert, corruption halt,
/// grant-belt refusals, and cadence-commit failures. Dependency-free by
/// design — a station composes its real flare transport here; the default
/// writes to stdout so a bare CLI wiring is never silent.
library;

import 'dart:io';

import 'package:meta/meta.dart';

/// What happened, wire-named for greppable output.
enum TrajectoryServiceEventKind {
  fencedOut('fenced_out'),
  reconnectInert('reconnect_inert'),
  corruptionHalt('corruption_halt'),
  grantRefused('grant_refused'),
  cadenceFailure('cadence_failure');

  const TrajectoryServiceEventKind(this.wire);

  final String wire;
}

/// One out-of-band notification from the append service.
@immutable
final class TrajectoryServiceEvent {
  const TrajectoryServiceEvent(this.kind, this.reason);

  final TrajectoryServiceEventKind kind;
  final String reason;

  @override
  String toString() => 'traj ${kind.wire}: $reason';
}

/// The seam the appender emits through.
typedef TrajectoryEventSink = void Function(TrajectoryServiceEvent event);

/// The default sink: stdout, one line per event — §5's clause (c) floor.
void stdoutTrajectoryEventSink(TrajectoryServiceEvent event) {
  stdout.writeln(event);
}
