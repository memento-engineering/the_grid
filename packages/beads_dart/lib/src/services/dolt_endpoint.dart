/// Connection coordinates supplied by a workspace endpoint resolver.
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

  /// True when the endpoint carries a non-empty password.
  bool get hasCredential => password.isNotEmpty;

  /// Copies this endpoint with replacement credentials.
  DoltEndpoint withCredentials({String? user, String? password}) =>
      DoltEndpoint(
        host: host,
        port: port,
        database: database,
        user: user ?? this.user,
        password: password ?? this.password,
      );

  @override
  String toString() =>
      'DoltEndpoint($user@$host:$port/$database, credential: $hasCredential)';
}
