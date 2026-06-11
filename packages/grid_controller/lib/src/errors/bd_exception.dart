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

/// The envelope's `schema_version` was not the pinned value — a hard signal
/// of upstream drift. The SQL read path uses this to fall back to bd CLI.
class BdSchemaDriftException extends BdException {
  const BdSchemaDriftException({
    required this.found,
    required this.expected,
    this.source = '',
  });

  final Object? found;
  final int expected;
  final String source;

  @override
  String get message =>
      'bd envelope schema_version $found != expected $expected (upstream drift)';
}
