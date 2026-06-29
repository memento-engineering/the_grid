/// The lessee side of the bus — the **pluggable transport seam**. [StationClient]
/// is the abstract bus (the operations a peer performs); [HttpStationClient] is
/// impl #1 over HTTP (this pass). A future MQTT/WS bus implements the same
/// interface, so nothing above the seam changes (Nico, 2026-06-29).
library;

import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// The cross-station bus, lessee view: presence, lease, dispatch, release.
abstract interface class StationClient {
  /// The peer's presence + free capacity.
  Future<Presence> presence();

  /// Requests one slot; throws [LeaseDeniedException] on refusal.
  Future<LeaseGrant> requestLease(LeaseRequest req);

  /// Runs [cmd] on the leased slot [leaseId]; throws [LeaseInvalidException] if
  /// the lease is gone.
  Future<CommandResult> dispatch(String leaseId, DispatchCommand cmd);

  /// Releases the leased slot (idempotent).
  Future<void> release(String leaseId);

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
      LeaseGrant.fromJson(await _call('POST', '/lease', req.toJson()));

  @override
  Future<CommandResult> dispatch(String leaseId, DispatchCommand cmd) async =>
      CommandResult.fromJson(
        await _call('POST', '/lease/$leaseId/dispatch', cmd.toJson()),
      );

  @override
  Future<void> release(String leaseId) async {
    await _call('POST', '/lease/$leaseId/release');
  }

  @override
  Future<void> close() async => _http.close(force: true);

  /// One JSON request/response, mapping status codes to typed exceptions.
  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: path);
    final req = await _http.openUrl(method, uri);
    if (token != null) req.headers.set('X-Grid-Token', token!);
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
