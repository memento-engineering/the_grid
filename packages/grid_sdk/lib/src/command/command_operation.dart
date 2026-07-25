import 'package:freezed_annotation/freezed_annotation.dart';

part 'command_operation.freezed.dart';

/// One operator command for the resident station.
@freezed
sealed class GridCommandRequest with _$GridCommandRequest {
  /// Retires the current session round for [beadId].
  const factory GridCommandRequest.rework({
    required String beadId,
    String? note,
  }) = GridRework;

  /// Resolves [gateId], optionally correcting persisted lane grades first.
  const factory GridCommandRequest.resolveGate({
    required String gateId,
    @Default(<String, String>{}) Map<String, String> grades,
    String? rationale,
  }) = GridGateResolve;
}

/// The typed outcome consumed by the control-surface adapter.
@freezed
sealed class GridCommandResult with _$GridCommandResult {
  /// The command completed and [value] is safe to place under `result`.
  const factory GridCommandResult.completed({
    required String message,
    @Default(<String, Object?>{}) Map<String, Object?> value,
  }) = GridCommandCompleted;

  /// The command was refused without throwing across the control surface.
  const factory GridCommandResult.refused({
    required String code,
    required String message,
  }) = GridCommandRefused;
}

/// A composable extension implemented by a running station.
///
/// Calls are requests serviced inside the resident event/reconcile loop. They
/// never acquire the station lock, start a process, or create work. This is the
/// scoped command-channel amendment to ADR-0014 D-C4 ratified by Nico in epic
/// `tg-wisp-1jt`'s GATE CLEARED note (2026-07-24); `bd` remains the only
/// work-intake surface. The matching ADR text is delegated to `tg-wisp-sgd`.
abstract interface class GridCommandHandler {
  /// Executes [request] in this resident station's event/reconcile loop.
  Future<GridCommandResult> call(GridCommandRequest request);
}
