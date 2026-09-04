import 'dart:convert';
import 'dart:io';

import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLifecyclePhase, StationLockRecord;

import 'station_attach.dart' show HttpClientFactory;
import 'station_lock.dart';

/// The result of sending a command to the resident station.
sealed class StationCommandResult {
  const StationCommandResult();
}

/// A command accepted and completed by the resident station.
final class StationCommandCompleted extends StationCommandResult {
  /// Creates a completed result with its JSON-safe [value].
  const StationCommandCompleted(this.value);

  /// The resident command result value.
  final Map<String, Object?> value;
}

/// A reachable resident station refused the command.
final class StationCommandRefused extends StationCommandResult {
  /// Creates a refusal carrying its operator-facing [message].
  const StationCommandRefused(this.message);

  /// The refusal explanation.
  final String message;
}

/// No usable resident station could be reached through `station.lock`.
final class StationCommandUnavailable extends StationCommandResult {
  /// Creates an unavailable result carrying its operator-facing [message].
  const StationCommandUnavailable(this.message);

  /// The availability explanation.
  final String message;
}

/// Sends authenticated, fenced, idempotent commands through StationControl.
class StationCommandClient {
  /// Creates a client with injectable HTTP and clock seams.
  StationCommandClient({
    HttpClientFactory? httpClientFactory,
    DateTime Function()? clock,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _clock = clock ?? DateTime.now;

  final HttpClientFactory _httpClientFactory;
  final DateTime Function() _clock;

  /// Sends [method] and [params] to the resident advertised by [gridRoot].
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    final lockPath = StationLockService.lockPath(gridRoot);
    final file = File(lockPath);
    if (!await file.exists()) {
      return StationCommandUnavailable(
        'station.lock is absent at $lockPath; no resident station is UP.',
      );
    }
    final StationLockRecord record;
    try {
      record = StationLockRecord.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
    } on Object {
      return StationCommandUnavailable(
        'station.lock at $lockPath is unreadable; no resident station is UP.',
      );
    }
    switch (record.phase) {
      case StationLifecyclePhase.acquired:
        return StationCommandUnavailable(
          'station.lock at $lockPath names a STARTING resident station.',
        );
      case StationLifecyclePhase.releasing:
        return StationCommandUnavailable(
          'station.lock at $lockPath names a RELEASING resident station.',
        );
      case StationLifecyclePhase.live:
        break;
    }
    final controlUrl = record.controlUrl;
    final token = record.token;
    if (controlUrl == null || token == null) {
      return StationCommandUnavailable(
        'station.lock at $lockPath declares a live station but has an '
        'unusable control transport advertisement.',
      );
    }
    final fence = _clock().toUtc().microsecondsSinceEpoch;
    final id = '${record.pid}-$fence';
    final client = _httpClientFactory()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.postUrl(
        Uri.parse('${controlUrl.replaceFirst(RegExp(r'/$'), '')}/command'),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set('X-Grid-Fence', '$fence')
        ..set('Idempotency-Key', id)
        ..contentType = ContentType.json;
      request.write(jsonEncode({'id': id, 'method': method, 'params': params}));
      final response = await request.close();
      final decoded = jsonDecode(
        await response.transform(const Utf8Decoder()).join(),
      );
      final body = (decoded as Map).cast<String, Object?>();
      if (response.statusCode == HttpStatus.ok && !body.containsKey('error')) {
        final result = body['result'];
        return StationCommandCompleted(
          result is Map
              ? result.cast<String, Object?>()
              : const <String, Object?>{},
        );
      }
      final error = body['error'];
      final message = error is Map
          ? '${error['message'] ?? error}'
          : '${error ?? 'resident station refused the command'}';
      return StationCommandRefused(message);
    } on Object catch (error) {
      return StationCommandUnavailable(
        'station.lock at $lockPath names an unreachable resident station: '
        '$error',
      );
    } finally {
      client.close(force: true);
    }
  }
}
