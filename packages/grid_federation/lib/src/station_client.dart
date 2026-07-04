/// The lessee side of the bus — impl #1 of the [StationClient] transport seam
/// (ADR-0011; the seam itself + the wire value types now live in
/// `grid_engine`'s SDK, the honesty-pass D-A9/D-B5 split, 2026-07-03: the
/// engine knows federation in CONCEPT only). [HttpStationClient] is the HTTP
/// impl (this pass). A future MQTT/WS bus implements the same [StationClient]
/// interface, so nothing above the seam changes (Nico, 2026-06-29).
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_engine/grid_engine.dart';

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
