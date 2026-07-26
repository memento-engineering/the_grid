/// WebSocket subprotocol prefix used to present the station bearer in browsers.
const stationTreeBearerProtocolPrefix = 'grid.tree.bearer.';

/// The web-safe value stored in `.grid/station.lock`.
final class StationLockRecord {
  /// Creates a station lock record.
  const StationLockRecord({
    required this.pid,
    required this.pgid,
    required this.startedAt,
    this.controlUrl,
    this.token,
    this.vmServiceUri,
  });

  /// Parses a lock record, tolerating unknown keys.
  factory StationLockRecord.fromJson(Map<String, Object?> json) =>
      StationLockRecord(
        pid: json['pid'] as int,
        pgid: json['pgid'] as int,
        startedAt: DateTime.parse(json['startedAt'] as String),
        controlUrl: json['controlUrl'] as String?,
        token: json['token'] as String?,
        vmServiceUri: json['vmServiceUri'] as String?,
      );

  /// The station process id.
  final int pid;

  /// The station process group id.
  final int pgid;

  /// When the station acquired the lock.
  final DateTime startedAt;

  /// The station control endpoint.
  final String? controlUrl;

  /// The per-boot control bearer.
  final String? token;

  /// The optional development VM-service URI.
  final String? vmServiceUri;

  /// Serializes the record, omitting absent optional fields.
  Map<String, Object?> toJson() => <String, Object?>{
    'pid': pid,
    'pgid': pgid,
    'startedAt': startedAt.toIso8601String(),
    if (controlUrl != null) 'controlUrl': controlUrl,
    if (token != null) 'token': token,
    if (vmServiceUri != null) 'vmServiceUri': vmServiceUri,
  };

  /// Returns this identity with its control advertisement.
  StationLockRecord withControl({
    required String controlUrl,
    required String token,
  }) => StationLockRecord(
    pid: pid,
    pgid: pgid,
    startedAt: startedAt,
    controlUrl: controlUrl,
    token: token,
    vmServiceUri: vmServiceUri,
  );

  /// Returns this identity with its VM-service advertisement.
  StationLockRecord withVmService(String vmServiceUri) => StationLockRecord(
    pid: pid,
    pgid: pgid,
    startedAt: startedAt,
    controlUrl: controlUrl,
    token: token,
    vmServiceUri: vmServiceUri,
  );
}
