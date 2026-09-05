import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'capability_failure.dart';
import 'step_signal.dart';

part 'process_session.freezed.dart';

/// One protocol-derived observation from a long-lived process session.
@freezed
sealed class ProcessSessionUpdate with _$ProcessSessionUpdate {
  const ProcessSessionUpdate._();

  /// Reports non-terminal protocol progress.
  const factory ProcessSessionUpdate.progress({
    @Default(<String, String>{}) Map<String, String> fields,
  }) = ProcessSessionProgress;

  /// Reports protocol completion and its structured result.
  const factory ProcessSessionUpdate.completed({
    required Map<String, String> result,
  }) = ProcessSessionCompleted;

  /// Reports a protocol or runtime failure.
  ///
  /// A null [kind] preserves the historical untyped failure. Protocol adapters
  /// may supply the existing capability-failure vocabulary when they can
  /// identify the result boundary without parsing [reason].
  const factory ProcessSessionUpdate.failed({
    required String reason,
    CapabilityFailureKind? kind,
  }) = ProcessSessionFailed;

  /// Cursor signal derived only from this protocol update.
  StepSignal get signal => switch (this) {
    ProcessSessionProgress() => StepSignal.none,
    ProcessSessionCompleted() => StepSignal.complete,
    ProcessSessionFailed() => StepSignal.failed,
  };
}

/// One durable, attempt-fenced command addressed to a live session.
@freezed
abstract class ProcessSessionCommand with _$ProcessSessionCommand {
  /// Creates a command with durable identity and live-incarnation fences.
  const factory ProcessSessionCommand({
    required String commandId,
    required String attemptId,
    required String instanceFence,
    required String body,
  }) = _ProcessSessionCommand;
}

/// The exact result of offering one command to a live session.
enum ProcessCommandDisposition {
  /// The command was encoded and written.
  delivered,

  /// This command id was already accepted.
  duplicate,

  /// The command names a different attempt.
  staleAttempt,

  /// The command carries a different instance fence.
  wrongFence,

  /// The session already observed a protocol or runtime terminal.
  terminal,
}

/// Protocol-neutral lifecycle and command surface owned by an Allocation.
abstract interface class ProcessSession {
  /// Protocol-derived updates for this session.
  Stream<ProcessSessionUpdate> get updates;

  /// Attaches protocol I/O and sends the initial command.
  Future<void> start();

  /// Offers one fenced command to the live session.
  Future<ProcessCommandDisposition> send(ProcessSessionCommand command);

  /// Supplies a supervised runtime observation to the protocol session.
  void onRuntimeEvent(RuntimeEvent event);

  /// Releases decoder and command subscriptions.
  Future<void> close();
}

/// Drives [session] until its first protocol or failure terminal.
Future<ProcessSessionUpdate> driveProcessSession({
  required ProcessSession session,
  required Stream<RuntimeEvent> runtimeEvents,
  RuntimeEvent? retainedTerminal,
}) async {
  final settled = Completer<ProcessSessionUpdate>();
  void settle(ProcessSessionUpdate update) {
    switch (update) {
      case ProcessSessionProgress():
        return;
      case ProcessSessionCompleted() || ProcessSessionFailed():
        if (!settled.isCompleted) settled.complete(update);
    }
  }

  final updateSub = session.updates.listen(
    settle,
    onError: (Object error, StackTrace stack) {
      if (!settled.isCompleted) {
        settled.complete(
          ProcessSessionUpdate.failed(reason: 'session update error: $error'),
        );
      }
    },
    onDone: () {
      if (!settled.isCompleted) {
        settled.complete(
          const ProcessSessionUpdate.failed(
            reason: 'session closed without a protocol terminal',
          ),
        );
      }
    },
  );
  final runtimeSub = runtimeEvents.listen(
    session.onRuntimeEvent,
    onError: (Object error, StackTrace stack) {
      if (!settled.isCompleted) {
        settled.complete(
          ProcessSessionUpdate.failed(reason: 'runtime event error: $error'),
        );
      }
    },
  );

  try {
    if (retainedTerminal case final terminal?) {
      session.onRuntimeEvent(terminal);
    }
    if (retainedTerminal == null && !settled.isCompleted) {
      await session.start();
    }
    return await settled.future;
  } on Object catch (error) {
    return ProcessSessionUpdate.failed(reason: 'session start error: $error');
  } finally {
    await runtimeSub.cancel();
    await updateSub.cancel();
    await session.close();
  }
}
