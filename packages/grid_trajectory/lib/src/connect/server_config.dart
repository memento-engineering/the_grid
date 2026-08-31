/// Endpoint resolution for the UNDERLYING dolt sql-server.
///
/// The service dials the server's own listener, never bd's read-only proxy
/// (decision: trajectory-direct-sql-scope) — bd's proxy pid/lock/secret files
/// are bd's alone and are never read here. Two on-disk layouts exist:
///
///   * plain: `<gridHome>/.grid/.beads/dolt/config.yaml` is the server config;
///   * proxied: `<gridHome>/.grid/.beads/proxied_server_client_info.json`
///     names a `root_path`, and the server bd actually spawned reads
///     `<gridHome>/.grid/.beads/<root_path>/config.yaml` — the outer
///     `dolt/config.yaml` can be stale there, so the proxy root's config wins
///     whenever the client-info file exists.
///
/// Resolution is conservative: only a config that yields both listener host
/// and port is accepted, and failure names every path probed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The one listener the trajectory service is allowed to dial.
@immutable
class DoltServerListener {
  const DoltServerListener({
    required this.host,
    required this.port,
    required this.configPath,
  });

  final String host;
  final int port;

  /// The config.yaml this listener was read from — kept for diagnostics.
  final String configPath;
}

class TrajectoryConfigException implements Exception {
  TrajectoryConfigException(this.message, {this.probed = const []});

  final String message;
  final List<String> probed;

  @override
  String toString() => probed.isEmpty
      ? 'TrajectoryConfigException: $message'
      : 'TrajectoryConfigException: $message\n  probed:\n'
            '${probed.map((path) => '    $path').join('\n')}';
}

/// Resolves the underlying server's listener for [gridHome].
DoltServerListener resolveDoltServerListener(String gridHome) {
  final beadsDir = p.join(gridHome, '.grid', '.beads');
  final probed = <String>[];

  final candidates = <String>[];
  final clientInfoPath = p.join(beadsDir, 'proxied_server_client_info.json');
  final clientInfo = File(clientInfoPath);
  if (clientInfo.existsSync()) {
    probed.add(clientInfoPath);
    final rootPath = _rootPathFrom(clientInfo, clientInfoPath);
    if (rootPath != null) {
      candidates.add(p.join(beadsDir, rootPath, 'config.yaml'));
    }
  }
  candidates.add(p.join(beadsDir, 'dolt', 'config.yaml'));

  for (final candidate in candidates) {
    probed.add(candidate);
    final file = File(candidate);
    if (!file.existsSync()) continue;
    final listener = _parseListener(file.readAsStringSync());
    final host = listener['host'];
    final port = int.tryParse(listener['port'] ?? '');
    if (host == null || port == null) {
      throw TrajectoryConfigException(
        'config exists but carries no complete listener host/port: $candidate',
        probed: probed,
      );
    }
    return DoltServerListener(host: host, port: port, configPath: candidate);
  }

  throw TrajectoryConfigException(
    'no dolt sql-server config found under $beadsDir',
    probed: probed,
  );
}

String? _rootPathFrom(File clientInfo, String path) {
  final Object? decoded;
  try {
    decoded = jsonDecode(clientInfo.readAsStringSync());
  } on FormatException catch (error) {
    throw TrajectoryConfigException(
      'unparseable $path: $error',
      probed: [path],
    );
  }
  return decoded is Map<String, Object?>
      ? decoded['root_path'] as String?
      : null;
}

/// Extracts `listener: {host, port}` from a dolt server config.yaml. The file
/// shape is machine-written and shallow, so a targeted block scan beats a
/// yaml dependency; both nested-block and inline `key: value` forms parse.
Map<String, String> _parseListener(String yaml) {
  final result = <String, String>{};
  var inListener = false;
  var listenerIndent = 0;
  for (final rawLine in const LineSplitter().convert(yaml)) {
    final line = rawLine.replaceFirst(RegExp(r'#.*$'), '');
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    final trimmed = line.trim();
    if (!inListener) {
      if (trimmed == 'listener:' || trimmed.startsWith('listener:')) {
        inListener = true;
        listenerIndent = indent;
      }
      continue;
    }
    if (indent <= listenerIndent) break; // dedent ends the block
    final colon = trimmed.indexOf(':');
    if (colon < 0) continue;
    final key = trimmed.substring(0, colon).trim();
    final value = trimmed
        .substring(colon + 1)
        .trim()
        .replaceAll(RegExp('''^["']|["']\$'''), '');
    if (key == 'host' || key == 'port') result[key] = value;
  }
  return result;
}
