/// The lessee side of the bus — the **pluggable, kind-agnostic transport seam**.
/// [StationClient] is the abstract bus (the coordination operations a peer
/// performs); [HttpStationClient] is impl #1 over HTTP (this pass). A future
/// MQTT/WS bus implements the same interface, so nothing above the seam changes
/// (Nico, 2026-06-29).
///
/// The seam carries only bus-level coordination types ([Presence], [LeaseRequest],
/// [LeaseGrant]) plus an OPAQUE dispatch envelope ([Map]) — no compute/command
/// specifics leak in (ADR-0011 D3). The lessee holds the [LeaseGrant], so the
/// fencing token rides every dispatch/release automatically.
library;

import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// The cross-station bus, lessee view: presence, lease, dispatch, release.
abstract interface class StationClient {
  /// Reads the peer's presence + free capacity. (An observation.)
  Future<Presence> presence();

  /// Requests one slot; throws [LeaseDeniedException] on refusal. (An act.)
  Future<LeaseGrant> requestLease(LeaseRequest req);

  /// Runs an opaque [payload] on the slot held by [lease], propagating its
  /// fencing token. Returns the opaque result envelope. Throws
  /// [LeaseInvalidException] if the lease is gone or the token is stale.
  ///
  /// [idempotencyKey] (when set) lets the owner dedup retries: the same key
  /// returns the SAME result, never a second run.
  Future<Map<String, dynamic>> dispatch(
    LeaseGrant lease,
    Map<String, dynamic> payload, {
    String idempotencyKey,
  });

  /// Sends a liveness HEARTBEAT for [lease], propagating its fencing token, so the
  /// owner does not reap the held slot as disconnected. Throws
  /// [LeaseInvalidException] if the lease is gone or the token is stale. (An act.)
  Future<void> heartbeat(LeaseGrant lease);

  /// Releases the slot held by [lease] (idempotent), propagating its fencing
  /// token so a stale holder cannot free a reissued slot.
  Future<void> release(LeaseGrant lease);

  /// Releases any held transport resources.
  Future<void> close();
}

/// HTTP implementation of [StationClient] (impl #1).
class HttpStationClient implements StationClient {
  /// Creates a client targeting `http://[host]:[port]`, optionally sending the
  /// shared [token] as `X-Grid-Token`.
  HttpStationClient({required this.host, required this.port, this.token});

  /// The peer host.
  final String host;

  /// The peer port.
  final int port;

  /// The optional shared secret (LAN trust, this pass).
  final String? token;

  final HttpClient _http = HttpClient();

  @override
  Future<Presence> presence() async =>
      Presence.fromJson(await _call('GET', '/presence'));

  @override
  Future<LeaseGrant> requestLease(LeaseRequest req) async =>
      LeaseGrant.fromJson(await _call('POST', '/lease', body: req.toJson()));

  @override
  Future<Map<String, dynamic>> dispatch(
    LeaseGrant lease,
    Map<String, dynamic> payload, {
    String idempotencyKey = '',
  }) async => _call(
    'POST',
    '/lease/${lease.leaseId}/dispatch',
    body: payload,
    fencingToken: lease.fencingToken,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<void> heartbeat(LeaseGrant lease) async {
    await _call(
      'POST',
      '/lease/${lease.leaseId}/heartbeat',
      fencingToken: lease.fencingToken,
    );
  }

  @override
  Future<void> release(LeaseGrant lease) async {
    await _call(
      'POST',
      '/lease/${lease.leaseId}/release',
      fencingToken: lease.fencingToken,
    );
  }

  @override
  Future<void> close() async => _http.close(force: true);

  /// One JSON request/response, mapping status codes to typed exceptions.
  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    int? fencingToken,
    String idempotencyKey = '',
  }) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: path);
    final req = await _http.openUrl(method, uri);
    if (token != null) req.headers.set('X-Grid-Token', token!);
    if (fencingToken != null) {
      req.headers.set('X-Grid-Fence', '$fencingToken');
    }
    if (idempotencyKey.isNotEmpty) {
      req.headers.set('X-Grid-Idem', idempotencyKey);
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    final code = resp.statusCode;
    if (code == 200) {
      return text.isEmpty ? const {} : jsonDecode(text) as Map<String, dynamic>;
    }
    final reason = _reasonOf(text);
    switch (code) {
      case 409:
        throw LeaseDeniedException(reason);
      case 404:
      case 410:
        throw LeaseInvalidException(reason);
      case 401:
        throw const FederationException('unauthorized (bad or missing token)');
      default:
        throw FederationException('HTTP $code: $reason');
    }
  }

  String _reasonOf(String text) {
    if (text.isEmpty) return '(no body)';
    try {
      final j = jsonDecode(text);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } on FormatException {
      // fall through — return the raw text
    }
    return text;
  }
}
