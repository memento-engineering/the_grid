import 'dart:convert';
import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_engine/grid_engine.dart'
    show DoneSession, ExplorationTransport, HeldSession, SessionDisposition;

part 'station_event_log.freezed.dart';

/// Consumer-side typed interpretation of one accepted station flare.
@Freezed(copyWith: false)
sealed class StationEvent with _$StationEvent {
  /// A session bead completed its durable birth stamp.
  const factory StationEvent.sessionMinted({
    required String sessionId,
    required String workBeadId,
  }) = SessionMintedEvent;

  /// A new gate was minted or an existing open gate was refreshed.
  const factory StationEvent.gateOpened({
    required String gateId,
    required String sessionId,
    required String nodePath,
    required String reason,
    required bool reused,
  }) = GateOpenedEvent;

  /// A session closed with its disposition.
  const factory StationEvent.sessionClosed({
    required String sessionId,
    required SessionDisposition disposition,
  }) = SessionClosedEvent;

  /// A flare whose name has no typed decoder in this sink version.
  const factory StationEvent.generic({
    required String name,
    required Map<String, String> data,
  }) = GenericStationEvent;
}

/// One timestamped, monotonically cursored durable log record.
@Freezed(copyWith: false)
abstract class StationEventRecord with _$StationEventRecord {
  /// Creates a record at [cursor] and [timestamp].
  const factory StationEventRecord({
    required int cursor,
    required DateTime timestamp,
    required StationEvent event,
  }) = _StationEventRecord;
}

/// Append-only JSON-lines sink over the existing exploration flare seam.
final class DurableStationEventLog implements ExplorationTransport {
  DurableStationEventLog._(this._file, this._handle, this._cursor, this._now);

  /// The log filename within the directory passed to [open].
  static const fileName = 'station-events.jsonl';

  /// Opens or creates a log, refusing corrupt or non-contiguous history.
  static Future<DurableStationEventLog> open(
    Directory directory, {
    DateTime Function()? now,
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/$fileName');
    if (!await file.exists()) await file.create();
    final lines = await file.readAsLines();
    var cursor = 0;
    for (final line in lines) {
      final record = _decodeRecord(line);
      if (record.cursor != cursor + 1) {
        throw FormatException(
          'station event cursor ${record.cursor} follows $cursor',
        );
      }
      cursor = record.cursor;
    }
    final handle = await file.open(mode: FileMode.append);
    return DurableStationEventLog._(file, handle, cursor, now ?? DateTime.now);
  }

  final File _file;
  final RandomAccessFile _handle;
  final DateTime Function() _now;
  int _cursor;
  bool _closed = false;

  /// Appends and flushes one accepted flare without throwing to the caller.
  @override
  void flare(String name, Map<String, String> data) {
    if (_closed) return;
    try {
      final record = StationEventRecord(
        cursor: _cursor + 1,
        timestamp: _now().toUtc(),
        event: _decodeEvent(name, Map<String, String>.unmodifiable(data)),
      );
      _handle.writeStringSync('${jsonEncode(_encodeRecord(record))}\n');
      _handle.flushSync();
      _cursor = record.cursor;
    } catch (_) {
      // A fire-and-continue sink cannot break the protected transition.
    }
  }

  /// Replays records whose cursor is strictly greater than [after].
  Future<List<StationEventRecord>> replay({required int after}) async {
    final records = <StationEventRecord>[];
    for (final line in await _file.readAsLines()) {
      final record = _decodeRecord(line);
      if (record.cursor > after) records.add(record);
    }
    return records;
  }

  /// Closes the file handle and makes later flares inert.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _handle.close();
  }
}

StationEvent _decodeEvent(String name, Map<String, String> data) =>
    switch (name) {
      'session.minted' => StationEvent.sessionMinted(
        sessionId: _required(data, 'sessionId'),
        workBeadId: _required(data, 'workBeadId'),
      ),
      'gate.opened' => StationEvent.gateOpened(
        gateId: _required(data, 'gateId'),
        sessionId: _required(data, 'sessionId'),
        nodePath: _required(data, 'nodePath'),
        reason: _required(data, 'reason'),
        reused: switch (_required(data, 'reused')) {
          'true' => true,
          'false' => false,
          final value => throw FormatException('invalid reused value: $value'),
        },
      ),
      'session.closed' => StationEvent.sessionClosed(
        sessionId: _required(data, 'sessionId'),
        disposition: _decodeDisposition(data),
      ),
      _ => StationEvent.generic(name: name, data: data),
    };

SessionDisposition _decodeDisposition(Map<String, String> data) =>
    switch (_required(data, 'disposition')) {
      'done' => const SessionDisposition.done(),
      'held' => SessionDisposition.held(reason: _required(data, 'reason')),
      final value => throw FormatException(
        'unknown session disposition: $value',
      ),
    };

String _required(Map<String, String> data, String key) {
  final value = data[key];
  if (value == null) throw FormatException('missing station event field: $key');
  return value;
}

Map<String, Object> _encodeRecord(StationEventRecord record) {
  final encoded = _encodeEvent(record.event);
  return {
    'cursor': record.cursor,
    'timestamp': record.timestamp.toUtc().toIso8601String(),
    'name': encoded.name,
    'data': encoded.data,
  };
}

({String name, Map<String, String> data}) _encodeEvent(StationEvent event) =>
    switch (event) {
      SessionMintedEvent(:final sessionId, :final workBeadId) => (
        name: 'session.minted',
        data: {'sessionId': sessionId, 'workBeadId': workBeadId},
      ),
      GateOpenedEvent(
        :final gateId,
        :final sessionId,
        :final nodePath,
        :final reason,
        :final reused,
      ) =>
        (
          name: 'gate.opened',
          data: {
            'gateId': gateId,
            'sessionId': sessionId,
            'nodePath': nodePath,
            'reason': reason,
            'reused': '$reused',
          },
        ),
      SessionClosedEvent() => (
        name: 'session.closed',
        data: _closedData(event),
      ),
      GenericStationEvent(:final name, :final data) => (name: name, data: data),
    };

Map<String, String> _closedData(SessionClosedEvent event) =>
    switch (event.disposition) {
      DoneSession() => {'sessionId': event.sessionId, 'disposition': 'done'},
      HeldSession(:final reason) => {
        'sessionId': event.sessionId,
        'disposition': 'held',
        'reason': reason,
      },
      _ => throw FormatException(
        'session.closed requires a terminal done or held disposition',
      ),
    };

StationEventRecord _decodeRecord(String line) {
  try {
    if (line.isEmpty) throw const FormatException('empty station event line');
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('station event record is not an object');
    }
    final cursor = decoded['cursor'];
    if (cursor is! int || cursor <= 0) {
      throw const FormatException('station event cursor must be positive');
    }
    final timestampValue = decoded['timestamp'];
    if (timestampValue is! String) {
      throw const FormatException('station event timestamp must be a string');
    }
    final timestamp = DateTime.parse(timestampValue);
    if (!timestamp.isUtc) {
      throw const FormatException('station event timestamp must be UTC');
    }
    final name = decoded['name'];
    if (name is! String) {
      throw const FormatException('station event name must be a string');
    }
    final rawData = decoded['data'];
    if (rawData is! Map<String, dynamic>) {
      throw const FormatException('station event data must be an object');
    }
    final data = <String, String>{};
    for (final entry in rawData.entries) {
      if (entry.value is! String) {
        throw const FormatException(
          'station event data values must be strings',
        );
      }
      data[entry.key] = entry.value as String;
    }
    return StationEventRecord(
      cursor: cursor,
      timestamp: timestamp,
      event: _decodeEvent(name, Map<String, String>.unmodifiable(data)),
    );
  } on FormatException {
    rethrow;
  } catch (error) {
    throw FormatException('invalid station event record: $error');
  }
}
