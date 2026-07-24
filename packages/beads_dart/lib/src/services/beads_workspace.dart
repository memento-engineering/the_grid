import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dolt_endpoint.dart';

/// How a workspace's beads store is reached.
enum DoltMode { server, proxiedServer, direct, unknown }

/// Discovers and parses a beads workspace: locates `.beads/`, reads
/// `metadata.json` (mode + database), `.env` (`GT_ROOT`), and — in server mode
/// — the gc dolt pack's `dolt-config.yaml` for the host/port, producing a
/// [DoltEndpoint] with credentials resolved from the environment.
///
/// Service layer (stateless I/O): all reads, no caching beyond the parsed
/// result. Throws nothing for a missing endpoint — [endpoint] is simply null
/// in direct/embedded mode, and the controller falls back to the bd CLI.
class BeadsWorkspace {
  BeadsWorkspace({
    required this.root,
    required this.mode,
    required this.database,
    required this.gtRoot,
    required this.endpoint,
  });

  /// The workspace root (the directory containing `.beads/`).
  final String root;
  final DoltMode mode;

  /// The Dolt database name (`metadata.json` `dolt_database`), e.g. `tg`.
  final String? database;

  /// `GT_ROOT` from `.beads/.env`, the gc city root that hosts the server.
  final String? gtRoot;

  /// Server endpoint, or null in direct/embedded mode.
  final DoltEndpoint? endpoint;

  String get beadsDir => p.join(root, '.beads');

  /// Walks up from [start] (default: cwd) to find the nearest `.beads/`
  /// directory, then parses it. Returns null if none is found.
  static BeadsWorkspace? discover({String? start, Map<String, String>? env}) {
    var dir = Directory(start ?? Directory.current.path).absolute;
    for (var i = 0; i < 12; i++) {
      final beads = Directory(p.join(dir.path, '.beads'));
      if (beads.existsSync()) {
        return _parse(dir.path, env: env);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static BeadsWorkspace _parse(String root, {Map<String, String>? env}) {
    final environment = env ?? Platform.environment;
    final metadata = _readJson(p.join(root, '.beads', 'metadata.json'));
    final modeString = (metadata?['dolt_mode'] as String?) ?? '';
    final mode = switch (modeString) {
      'server' => DoltMode.server,
      'proxied-server' => DoltMode.proxiedServer,
      'direct' || 'embedded' => DoltMode.direct,
      _ => DoltMode.unknown,
    };
    final database = metadata?['dolt_database'] as String?;
    final gtRoot =
        _readEnvValue(p.join(root, '.beads', '.env'), 'GT_ROOT') ??
        environment['GT_ROOT'];

    DoltEndpoint? endpoint;
    if (mode == DoltMode.server && gtRoot != null && database != null) {
      endpoint = _resolveEndpoint(gtRoot, database, environment);
    } else if (mode == DoltMode.proxiedServer && database != null) {
      endpoint = _resolveProxiedEndpoint(root, database);
    }

    return BeadsWorkspace(
      root: root,
      mode: mode,
      database: database,
      gtRoot: gtRoot,
      endpoint: endpoint,
    );
  }

  /// Resolves the endpoint of a proxied-server workspace (bd's experimental
  /// `dolt_mode: proxied-server`): the bd-managed proxy writes a JSON pidfile
  /// at `.beads/dolt/proxy.pid` (`{pid, port, upstream_id?}`) — clients
  /// connect to the PROXY's loopback port, never the child dolt directly.
  ///
  /// Credentials: the Dart `mysql_client` cannot complete an EMPTY-password
  /// handshake (bd's own Go client connects as `root`/`""`), so live SQL
  /// rides a dedicated read-only `beads_dart` SQL user whose secret is
  /// provisioned at `.beads/dolt/beads_dart.secret` (0600, operator-managed).
  /// Missing pidfile or secret → null endpoint → the caller falls back to the
  /// bd CLI read path.
  static DoltEndpoint? _resolveProxiedEndpoint(String root, String database) {
    final doltDir = p.join(root, '.beads', 'dolt');
    final pidFile = File(p.join(doltDir, 'proxy.pid'));
    if (!pidFile.existsSync()) return null;
    int? port;
    try {
      final decoded = jsonDecode(pidFile.readAsStringSync());
      if (decoded is Map<String, Object?>) {
        final rawPort = decoded['port'];
        if (rawPort is int) port = rawPort;
      }
    } on Object {
      return null; // Malformed pidfile: CLI fallback.
    }
    if (port == null || port < 1 || port > 65535) return null;

    final secretFile = File(p.join(doltDir, 'beads_dart.secret'));
    if (!secretFile.existsSync()) return null;
    final secret = secretFile.readAsStringSync().trim();
    if (secret.isEmpty) return null;

    return DoltEndpoint(
      host: '127.0.0.1',
      port: port,
      database: database,
      user: 'beads_dart',
      password: secret,
    );
  }

  /// Reads `$GT_ROOT/.gc/runtime/packs/dolt/dolt-config.yaml` for the listener
  /// host/port. Honors `GC_DOLT_HOST`/`GC_DOLT_PORT` env overrides.
  static DoltEndpoint? _resolveEndpoint(
    String gtRoot,
    String database,
    Map<String, String> env,
  ) {
    var host = (env['GC_DOLT_HOST'] ?? '').trim();
    var port = int.tryParse((env['GC_DOLT_PORT'] ?? '').trim());

    final configPath = p.join(
      gtRoot,
      '.gc',
      'runtime',
      'packs',
      'dolt',
      'dolt-config.yaml',
    );
    final configFile = File(configPath);
    if (configFile.existsSync()) {
      try {
        final yaml = loadYaml(configFile.readAsStringSync());
        final listener = yaml is YamlMap ? yaml['listener'] : null;
        if (listener is YamlMap) {
          host = host.isEmpty ? (listener['host'] as String? ?? host) : host;
          port ??= listener['port'] as int?;
        }
      } on Object {
        // Malformed config: fall through to defaults/overrides below.
      }
    }

    if (port == null) return null;
    // 0.0.0.0 is the server's bind address; clients connect via loopback.
    if (host.isEmpty || host == '0.0.0.0') host = '127.0.0.1';

    return DoltEndpoint.withEnvCredentials(
      host: host,
      port: port,
      database: database,
      env: env,
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

  /// Reads a single `KEY=value` from a simple `.env` (supports `export ` and
  /// surrounding quotes), mirroring gc's `readSimpleEnvValue`.
  static String? _readEnvValue(String path, String key) {
    final file = File(path);
    if (!file.existsSync()) return null;
    for (var line in file.readAsLinesSync()) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trim();
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      if (line.substring(0, eq).trim() != key) continue;
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2) {
        final first = value[0], last = value[value.length - 1];
        if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
          value = value.substring(1, value.length - 1);
        }
      }
      return value;
    }
    return null;
  }
}
