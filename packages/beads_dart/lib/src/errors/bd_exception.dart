import 'dart:convert';

/// Base of the bd failure hierarchy. Sealed so callers can switch exhaustively.
sealed class BdException implements Exception {
  const BdException();

  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A `bd` command exited non-zero.
///
/// Under `BD_JSON_ENVELOPE=1`, bd emits the error **enveloped on stdout**
/// (`{"data": {"error": "..."}, "schema_version": 1}`) with empty stderr and a
/// non-zero exit (ADR-0001 Decision 4, promoted from ADR-0000 A3). [fromOutput]
/// honors that channel order: stdout error envelope first, then stderr, then
/// raw stdout/stderr text.
class BdCommandFailed extends BdException {
  const BdCommandFailed({
    required this.command,
    required this.exitCode,
    required this.message,
    this.stdout = '',
    this.stderr = '',
  });

  factory BdCommandFailed.fromOutput({
    required List<String> command,
    required int exitCode,
    required String stdout,
    required String stderr,
  }) {
    final fromStdout = _errorFromEnvelope(stdout);
    final message =
        fromStdout ??
        (stderr.trim().isNotEmpty
            ? stderr.trim()
            : (stdout.trim().isNotEmpty
                  ? stdout.trim()
                  : 'bd exited $exitCode with no output'));
    return BdCommandFailed(
      command: command,
      exitCode: exitCode,
      message: message,
      stdout: stdout,
      stderr: stderr,
    );
  }

  final List<String> command;
  final int exitCode;
  @override
  final String message;
  final String stdout;
  final String stderr;

  /// Extracts `data.error` from a bd envelope, or null if [source] is not a
  /// JSON object carrying a string error.
  static String? _errorFromEnvelope(String source) {
    if (source.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is String && error.isNotEmpty) return error;
    }
    final topError = decoded['error'];
    if (topError is String && topError.isNotEmpty) return topError;
    return null;
  }
}

/// A `bd` invocation exceeded its timeout and was killed.
class BdTimeoutException extends BdException {
  const BdTimeoutException({required this.command, required this.timeout});

  final List<String> command;
  final Duration timeout;

  @override
  String get message =>
      'bd timed out after ${timeout.inMilliseconds}ms: ${command.join(' ')}';
}

/// bd output (or a SQL row payload) could not be parsed.
class BdParseException extends BdException {
  const BdParseException(this.message, [this.source = '']);

  @override
  final String message;
  final String source;
}

/// Upstream drift the client refuses to guess through.
///
/// Two shapes, one catch site: the default constructor is the envelope
/// `schema_version` mismatch; [BdSchemaDriftException.sqlShape] is the Dolt SQL
/// read path finding a store whose column shape it cannot serve. Both are the
/// signal to fall back to the bd CLI (ADR-0001 Decision 4).
class BdSchemaDriftException extends BdException {
  const BdSchemaDriftException({
    required this.found,
    required this.expected,
    this.source = '',
  }) : missing = const [];

  /// The SQL read path cannot run against this store: [missing] names each
  /// required `table` / `table.column` the connect-time probe did not find, and
  /// [found] carries the store's migration version for diagnostics only.
  const BdSchemaDriftException.sqlShape({
    required this.missing,
    required this.found,
    this.source = 'information_schema',
  }) : expected = 0;

  final Object? found;
  final int expected;
  final String source;

  /// The required tables/columns the store is missing (SQL-shape drift only;
  /// empty for the envelope-version case).
  final List<String> missing;

  @override
  String get message => missing.isEmpty
      ? 'bd envelope schema_version $found != expected $expected (upstream drift)'
      : 'Dolt SQL read path unsupported at migration $found: missing '
            '${missing.join(', ')} (probed via $source) — falling back to the '
            'bd CLI';
}
