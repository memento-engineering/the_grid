import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'dolt_endpoint.dart';

/// How a workspace's beads store is reached by bd.
enum DoltMode { proxiedServer, direct, unknown }

/// Workspace-local inputs supplied to an [EndpointResolver].
final class EndpointResolutionRequest {
  /// Creates a request for one discovered workspace.
  const EndpointResolutionRequest({
    required this.root,
    required this.doltMode,
    required this.database,
  });

  /// The absolute directory containing `.beads/`.
  final String root;

  /// The raw `metadata.json` `dolt_mode` value.
  final String doltMode;

  /// The raw `metadata.json` `dolt_database` value, when present.
  final String? database;

  /// The workspace's `.beads/` directory.
  String get beadsDir => p.join(root, '.beads');
}

/// The observable outcome of resolving a workspace's SQL endpoint.
final class EndpointResolution {
  /// A successfully resolved [endpoint].
  // Keep the public parameter non-null even though the stored field is nullable.
  const EndpointResolution.resolved(DoltEndpoint endpoint)
    // ignore: prefer_initializing_formals
    : endpoint = endpoint,
      diagnostic = null;

  /// An unavailable SQL path with an operator-facing [diagnostic].
  // Keep the public parameter non-null even though the stored field is nullable.
  const EndpointResolution.unavailable(String diagnostic)
    : endpoint = null,
      // ignore: prefer_initializing_formals
      diagnostic = diagnostic;

  /// The resolved endpoint, or null when the CLI read path must be used.
  final DoltEndpoint? endpoint;

  /// Why resolution was unavailable, or null after successful resolution.
  final String? diagnostic;
}

/// Resolves a SQL endpoint from one discovered workspace.
abstract interface class EndpointResolver {
  /// Resolves [request] without consulting process-global endpoint state.
  EndpointResolution resolve(EndpointResolutionRequest request);
}

/// Resolves bd's workspace-local experimental proxied-server artifacts.
final class ProxiedServerEndpointResolver implements EndpointResolver {
  /// Creates the built-in bd proxied-server resolver.
  const ProxiedServerEndpointResolver();

  @override
  EndpointResolution resolve(EndpointResolutionRequest request) {
    if (request.doltMode != 'proxied-server') {
      final renderedMode = request.doltMode.isEmpty
          ? '<missing>'
          : request.doltMode;
      return EndpointResolution.unavailable(
        'No built-in SQL endpoint resolver for dolt_mode "$renderedMode"; '
        'inject an EndpointResolver for this workspace or use the bd CLI '
        'read path.',
      );
    }

    final database = request.database;
    if (database == null || database.trim().isEmpty) {
      return const EndpointResolution.unavailable(
        'Cannot resolve proxied-server SQL endpoint: metadata.json has no '
        'non-empty dolt_database; repair the workspace metadata or use the '
        'bd CLI read path.',
      );
    }

    var proxyRoot = p.join(request.beadsDir, 'dolt');
    final sidecar = File(
      p.join(request.beadsDir, 'proxied_server_client_info.json'),
    );
    if (sidecar.existsSync()) {
      Object? decoded;
      try {
        decoded = jsonDecode(sidecar.readAsStringSync());
      } on Object catch (error) {
        return EndpointResolution.unavailable(
          'Cannot resolve proxied-server SQL endpoint: ${sidecar.path} '
          'is not readable JSON (${error.runtimeType}).',
        );
      }
      if (decoded is! Map<String, Object?>) {
        return EndpointResolution.unavailable(
          'Cannot resolve proxied-server SQL endpoint: ${sidecar.path} '
          'must contain a JSON object.',
        );
      }
      final rootPath = decoded['root_path'];
      if (rootPath is String && rootPath.trim().isNotEmpty) {
        final configuredRoot = rootPath.trim();
        proxyRoot = p.normalize(
          p.isAbsolute(configuredRoot)
              ? configuredRoot
              : p.join(request.beadsDir, configuredRoot),
        );
      } else if (rootPath != null && rootPath is! String) {
        return EndpointResolution.unavailable(
          'Cannot resolve proxied-server SQL endpoint: ${sidecar.path} '
          'root_path must be a string.',
        );
      }
    }

    final pidFile = File(p.join(proxyRoot, 'proxy.pid'));
    if (!pidFile.existsSync()) {
      return EndpointResolution.unavailable(
        'Cannot resolve proxied-server SQL endpoint: ${pidFile.path} is '
        'missing; start bd\'s proxy for this workspace.',
      );
    }

    Object? pidPayload;
    try {
      pidPayload = jsonDecode(pidFile.readAsStringSync());
    } on Object catch (error) {
      return EndpointResolution.unavailable(
        'Cannot resolve proxied-server SQL endpoint: ${pidFile.path} is not '
        'readable JSON (${error.runtimeType}).',
      );
    }
    if (pidPayload is! Map<String, Object?>) {
      return EndpointResolution.unavailable(
        'Cannot resolve proxied-server SQL endpoint: ${pidFile.path} must '
        'contain a JSON object.',
      );
    }
    final rawPort = pidPayload['port'];
    if (rawPort is! int || rawPort < 1 || rawPort > 65535) {
      return EndpointResolution.unavailable(
        'Cannot resolve proxied-server SQL endpoint: ${pidFile.path} has no '
        'TCP port between 1 and 65535.',
      );
    }

    final secretFile = File(p.join(proxyRoot, 'beads_dart.secret'));
    if (!secretFile.existsSync()) {
      return EndpointResolution.unavailable(
        'Cannot resolve proxied-server SQL endpoint: ${secretFile.path} is '
        'missing; provision a non-empty 0600 secret for the read-only '
        'beads_dart SQL user.',
      );
    }

    String secret;
    try {
      secret = secretFile.readAsStringSync().trim();
    } on Object catch (error) {
      return EndpointResolution.unavailable(
        'Cannot resolve proxied-server SQL endpoint: ${secretFile.path} '
        'cannot be read (${error.runtimeType}).',
      );
    }
    if (secret.isEmpty) {
      return EndpointResolution.unavailable(
        'Cannot resolve proxied-server SQL endpoint: ${secretFile.path} is '
        'empty; provision a non-empty 0600 secret for the read-only '
        'beads_dart SQL user.',
      );
    }

    return EndpointResolution.resolved(
      DoltEndpoint(
        host: '127.0.0.1',
        port: rawPort,
        database: database,
        user: 'beads_dart',
        password: secret,
      ),
    );
  }
}

/// Discovers and parses a beads workspace and resolves its optional SQL path.
///
/// Service layer (stateless I/O): all reads, no caching beyond the parsed
/// result. [endpointResolution] makes CLI fallback observable to consumers.
class BeadsWorkspace {
  /// Creates one parsed workspace value.
  BeadsWorkspace({
    required this.root,
    required this.mode,
    required this.database,
    required this.endpointResolution,
  });

  /// The workspace root (the directory containing `.beads/`).
  final String root;

  /// The normalized bd storage mode.
  final DoltMode mode;

  /// The Dolt database name from `metadata.json`.
  final String? database;

  /// The resolver outcome, including the CLI-fallback diagnostic.
  final EndpointResolution endpointResolution;

  /// The resolved SQL endpoint, or null when consumers use the bd CLI.
  DoltEndpoint? get endpoint => endpointResolution.endpoint;

  /// The resolver's CLI-fallback reason, or null after successful resolution.
  String? get endpointDiagnostic => endpointResolution.diagnostic;

  /// The workspace's `.beads/` directory.
  String get beadsDir => p.join(root, '.beads');

  /// Walks up from [start] (default: cwd) to find the nearest `.beads/`
  /// directory, then parses it. Returns null if none is found.
  static BeadsWorkspace? discover({
    String? start,
    EndpointResolver endpointResolver = const ProxiedServerEndpointResolver(),
  }) {
    var dir = Directory(start ?? Directory.current.path).absolute;
    for (var i = 0; i < 12; i++) {
      final beads = Directory(p.join(dir.path, '.beads'));
      if (beads.existsSync()) {
        return _parse(dir.path, endpointResolver: endpointResolver);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static BeadsWorkspace _parse(
    String root, {
    required EndpointResolver endpointResolver,
  }) {
    final metadata = _readJson(p.join(root, '.beads', 'metadata.json'));
    final rawMode = metadata?['dolt_mode'];
    final modeString = rawMode is String ? rawMode : '';
    final mode = switch (modeString) {
      'proxied-server' => DoltMode.proxiedServer,
      'direct' || 'embedded' => DoltMode.direct,
      _ => DoltMode.unknown,
    };
    final rawDatabase = metadata?['dolt_database'];
    final database = rawDatabase is String ? rawDatabase : null;
    final endpointResolution = endpointResolver.resolve(
      EndpointResolutionRequest(
        root: root,
        doltMode: modeString,
        database: database,
      ),
    );

    return BeadsWorkspace(
      root: root,
      mode: mode,
      database: database,
      endpointResolution: endpointResolution,
    );
  }

  static Map<String, dynamic>? _readJson(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }
}
