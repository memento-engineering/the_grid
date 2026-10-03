/// WebSocket subprotocol prefix used to present the station bearer in browsers.
const stationTreeBearerProtocolPrefix = 'grid.tree.bearer.';

/// The resident station's declared lifecycle phase.
///
/// This is independent of posture such as dry-run versus live operation, and
/// of optional transport or development advertisements on the lock record.
enum StationLifecyclePhase {
  /// The station owns the lock but has not advertised its control surface.
  acquired,

  /// The station has advertised the control surface and can serve clients.
  live,

  /// The station is shutting down and is about to release the lock.
  releasing,
}

/// The resident's current terminal-unwind state.
final class StationUnwindRecord {
  /// Creates an unwind record.
  StationUnwindRecord({
    required this.step,
    required DateTime startedAt,
    required List<String> outstanding,
  }) : startedAt = startedAt.toUtc(),
       outstanding = List<String>.unmodifiable(outstanding);

  /// Parses an unwind record, tolerating unknown keys.
  factory StationUnwindRecord.fromJson(Map<String, Object?> json) {
    final outstanding = json['outstanding'] as List<Object?>;
    return StationUnwindRecord(
      step: json['step'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      outstanding: outstanding.cast<String>(),
    );
  }

  /// The unwind step the resident most recently entered.
  final String step;

  /// When the resident entered [step], normalized to UTC.
  final DateTime startedAt;

  /// Work the resident stopped awaiting, in shutdown order.
  final List<String> outstanding;

  /// Serializes the unwind record.
  Map<String, Object?> toJson() => <String, Object?>{
    'step': step,
    'startedAt': startedAt.toIso8601String(),
    'outstanding': outstanding,
  };
}

/// The web-safe value stored in `.grid/station.lock`.
final class StationLockRecord {
  /// Creates a station lock record.
  const StationLockRecord({
    required this.pid,
    required this.pgid,
    required this.startedAt,
    this.phase = StationLifecyclePhase.live,
    this.controlUrl,
    this.token,
    this.vmServiceUri,
    this.unwind,
  });

  /// Parses a lock record, tolerating unknown keys.
  factory StationLockRecord.fromJson(Map<String, Object?> json) =>
      StationLockRecord(
        pid: json['pid'] as int,
        pgid: json['pgid'] as int,
        startedAt: DateTime.parse(json['startedAt'] as String),
        phase: _phaseFromJson(json),
        controlUrl: json['controlUrl'] as String?,
        token: json['token'] as String?,
        vmServiceUri: json['vmServiceUri'] as String?,
        unwind: _unwindFromJson(json['unwind']),
      );

  /// The station process id.
  final int pid;

  /// The station process group id.
  final int pgid;

  /// When the station acquired the lock.
  final DateTime startedAt;

  /// The station's declared lifecycle phase.
  final StationLifecyclePhase phase;

  /// The station control endpoint.
  final String? controlUrl;

  /// The per-boot control bearer.
  final String? token;

  /// The optional development VM-service URI.
  final String? vmServiceUri;

  /// The optional terminal-unwind state published for a stopping client.
  final StationUnwindRecord? unwind;

  /// Serializes the record, omitting absent optional fields.
  Map<String, Object?> toJson() => <String, Object?>{
    'pid': pid,
    'pgid': pgid,
    'startedAt': startedAt.toIso8601String(),
    'phase': phase.name,
    if (controlUrl != null) 'controlUrl': controlUrl,
    if (token != null) 'token': token,
    if (vmServiceUri != null) 'vmServiceUri': vmServiceUri,
    if (unwind != null) 'unwind': unwind!.toJson(),
  };

  /// Returns this record in [phase], preserving every other field.
  StationLockRecord withPhase(StationLifecyclePhase phase) => StationLockRecord(
    pid: pid,
    pgid: pgid,
    startedAt: startedAt,
    phase: phase,
    controlUrl: controlUrl,
    token: token,
    vmServiceUri: vmServiceUri,
    unwind: unwind,
  );

  /// Returns this identity with its control advertisement.
  StationLockRecord withControl({
    required String controlUrl,
    required String token,
  }) => StationLockRecord(
    pid: pid,
    pgid: pgid,
    startedAt: startedAt,
    phase: phase,
    controlUrl: controlUrl,
    token: token,
    vmServiceUri: vmServiceUri,
    unwind: unwind,
  );

  /// Returns this identity with its VM-service advertisement.
  StationLockRecord withVmService(String vmServiceUri) => StationLockRecord(
    pid: pid,
    pgid: pgid,
    startedAt: startedAt,
    phase: phase,
    controlUrl: controlUrl,
    token: token,
    vmServiceUri: vmServiceUri,
    unwind: unwind,
  );

  /// Returns this identity with its terminal-unwind advertisement.
  StationLockRecord withUnwind(StationUnwindRecord unwind) => StationLockRecord(
    pid: pid,
    pgid: pgid,
    startedAt: startedAt,
    phase: phase,
    controlUrl: controlUrl,
    token: token,
    vmServiceUri: vmServiceUri,
    unwind: unwind,
  );
}

StationUnwindRecord? _unwindFromJson(Object? value) {
  if (value == null) return null;
  try {
    return StationUnwindRecord.fromJson(value as Map<String, Object?>);
  } on Object {
    return null;
  }
}

StationLifecyclePhase _phaseFromJson(Map<String, Object?> json) {
  if (!json.containsKey('phase')) return StationLifecyclePhase.live;
  return switch (json['phase']) {
    'acquired' => StationLifecyclePhase.acquired,
    'live' => StationLifecyclePhase.live,
    'releasing' => StationLifecyclePhase.releasing,
    final value => throw FormatException(
      'Unknown station lifecycle phase: $value',
    ),
  };
}
