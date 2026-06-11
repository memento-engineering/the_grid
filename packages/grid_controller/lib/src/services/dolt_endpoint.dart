import 'dart:io';

/// Connection coordinates for a Dolt sql-server, resolved from the workspace's
/// beads config plus the documented credential env contract.
///
/// Credentials follow ADR-0000 A8 / CLAUDE.md: [user] from `GC_DOLT_USER`
/// (default `root`), [password] from `GC_DOLT_PASSWORD`. The gc-managed server
/// offers no SSL, so connections use `secure: false`. [password] is empty when
/// the env var is unset — live-SQL callers self-skip in that case and the bd
/// CLI read path is the guaranteed fallback.
class DoltEndpoint {
  const DoltEndpoint({
    required this.host,
    required this.port,
    required this.database,
    this.user = 'root',
    this.password = '',
  });

  final String host;
  final int port;
  final String database;
  final String user;
  final String password;

  /// True when a password was resolved (from `GC_DOLT_PASSWORD`); live SQL is
  /// only attempted when this holds.
  bool get hasCredential => password.isNotEmpty;

  DoltEndpoint withCredentials({String? user, String? password}) =>
      DoltEndpoint(
        host: host,
        port: port,
        database: database,
        user: user ?? this.user,
        password: password ?? this.password,
      );

  /// Resolves [user]/[password] from environment overrides, leaving the
  /// host/port/database fixed.
  factory DoltEndpoint.withEnvCredentials({
    required String host,
    required int port,
    required String database,
    Map<String, String>? env,
  }) {
    final environment = env ?? Platform.environment;
    return DoltEndpoint(
      host: host,
      port: port,
      database: database,
      user: (environment['GC_DOLT_USER'] ?? '').trim().isEmpty
          ? 'root'
          : environment['GC_DOLT_USER']!.trim(),
      password: environment['GC_DOLT_PASSWORD'] ?? '',
    );
  }

  @override
  String toString() =>
      'DoltEndpoint($user@$host:$port/$database, credential: $hasCredential)';
}
