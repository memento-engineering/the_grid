import 'dart:convert';

/// Base of the bd failure hierarchy. Sealed so callers can switch exhaustively.
sealed class BdException implements Exception {
  const BdException();

  /// Classifies a non-zero `bd` result using its exit code, command, and
  /// machine-readable output contracts.
  static BdException fromOutput({
    required List<String> command,
    required int exitCode,
    required String stdout,
    required String stderr,
  }) {
    final stdoutData = _envelopeData(stdout);
    if (exitCode == 13 && stdoutData?['guard_mismatch'] == true) {
      return BdGuardMismatch(
        command: command,
        message: _messageFromOutput(exitCode, stdout, stderr),
        stdout: stdout,
        stderr: stderr,
      );
    }

    if (exitCode == 14) {
      // bd 1.3 `ExitMigrationFrozen`: a write refused because a
      // MIGRATION-FREEZE marker is active. The refusal is plain text on
      // stderr with an empty stdout, so the dedicated, stable exit code IS the
      // discriminator (ADR-0000 A3's stdout envelope does not apply). A frozen
      // store must read as "frozen", never as a crash.
      return BdMigrationFrozen(
        command: command,
        message: _messageFromOutput(exitCode, stdout, stderr),
        markerPath: _freezeMarkerPath(stderr),
        stdout: stdout,
        stderr: stderr,
      );
    }

    if (command.length > 1 && command[1] == 'update') {
      final report = _envelopeData(_lastNonEmptyLine(stderr));
      final failed = report?['failed'];
      if (failed is List) {
        final failures = <BdUpdateFailure>[];
        for (final item in failed) {
          if (item is! Map<String, dynamic>) {
            return BdCommandFailed.fromOutput(
              command: command,
              exitCode: exitCode,
              stdout: stdout,
              stderr: stderr,
            );
          }
          final id = item['id'];
          final error = item['error'];
          if (id is! String ||
              id.isEmpty ||
              error is! String ||
              error.isEmpty) {
            return BdCommandFailed.fromOutput(
              command: command,
              exitCode: exitCode,
              stdout: stdout,
              stderr: stderr,
            );
          }
          failures.add(BdUpdateFailure(id: id, error: error));
        }
        if (failures.isNotEmpty) {
          return BdUpdatePartialFailure(
            command: command,
            exitCode: exitCode,
            message: report?['error'] is String
                ? report!['error'] as String
                : _messageFromOutput(exitCode, stdout, stderr),
            failures: List.unmodifiable(failures),
            stdout: stdout,
            stderr: stderr,
          );
        }
      }
    }

    if (exitCode == 2 &&
        command.length > 1 &&
        command[1] == 'list' &&
        command.contains('--ready')) {
      return BdUsageException(
        command: command,
        exitCode: exitCode,
        message: _messageFromOutput(exitCode, stdout, stderr),
        stdout: stdout,
        stderr: stderr,
      );
    }

    return BdCommandFailed.fromOutput(
      command: command,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
    );
  }

  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// One failed id reported by a multi-id `bd update`.
class BdUpdateFailure {
  const BdUpdateFailure({required this.id, required this.error});

  final String id;
  final String error;
}

/// Exit 13 from a conditional update whose envelope confirms a guard mismatch.
class BdGuardMismatch extends BdException {
  const BdGuardMismatch({
    required this.command,
    required this.message,
    required this.stdout,
    required this.stderr,
  });

  final List<String> command;
  @override
  final String message;
  final String stdout;
  final String stderr;
}

/// Exit 14 — a write refused because a `MIGRATION-FREEZE` marker is active.
///
/// The marker is a plain file an operator (or a migration tool) creates to stop
/// writes against a workspace and removes to resume them; bd only reads it.
/// This is a "come back later", not a failure to retry immediately.
class BdMigrationFrozen extends BdException {
  const BdMigrationFrozen({
    required this.command,
    required this.message,
    required this.markerPath,
    required this.stdout,
    required this.stderr,
  });

  final List<String> command;
  @override
  final String message;

  /// The marker path bd named, or null when bd could not stat the marker and
  /// failed closed instead ("cannot determine whether this workspace is
  /// frozen"), which names no marker.
  final String? markerPath;

  final String stdout;
  final String stderr;
}

/// A multi-id update applied some ids and reported failures for others.
class BdUpdatePartialFailure extends BdException {
  const BdUpdatePartialFailure({
    required this.command,
    required this.exitCode,
    required this.message,
    required this.failures,
    required this.stdout,
    required this.stderr,
  });

  final List<String> command;
  final int exitCode;
  @override
  final String message;
  final List<BdUpdateFailure> failures;
  final String stdout;
  final String stderr;
}

/// The invocation was refused because its argv combination is unsupported.
class BdUsageException extends BdException {
  const BdUsageException({
    required this.command,
    required this.exitCode,
    required this.message,
    required this.stdout,
    required this.stderr,
  });

  final List<String> command;
  final int exitCode;
  @override
  final String message;
  final String stdout;
  final String stderr;
}

/// An argv-only bead text field contains a control character that Dart cannot
/// transport safely.
class BeadTextRefused extends BdException {
  const BeadTextRefused({
    required this.field,
    required this.offset,
    required this.context,
  });

  final String field;
  final int offset;
  final String context;

  @override
  String get message =>
      'Refused $field at offset $offset near ${jsonEncode(context)}';
}

/// An argv-only bead text field differed when read back after persistence.
class BeadTextRoundTripFailure extends BdException {
  const BeadTextRoundTripFailure({
    required this.field,
    required this.sentLength,
    required this.storedLength,
    required this.offset,
    required this.sentContext,
    required this.storedContext,
  });

  final String field;
  final int sentLength;
  final int storedLength;
  final int offset;
  final String sentContext;
  final String storedContext;

  @override
  String get message =>
      '$field round-trip differed at offset $offset '
      '(sent $sentLength, stored $storedLength)';
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
    return BdCommandFailed(
      command: command,
      exitCode: exitCode,
      message: _messageFromOutput(exitCode, stdout, stderr),
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
}

Map<String, dynamic>? _envelopeData(String source) {
  if (source.trim().isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final data = decoded['data'];
  return data is Map<String, dynamic> ? data : null;
}

String _messageFromOutput(int exitCode, String stdout, String stderr) {
  final stdoutData = _envelopeData(stdout);
  final envelopeError = stdoutData?['error'];
  if (envelopeError is String && envelopeError.isNotEmpty) {
    return envelopeError;
  }
  if (stderr.trim().isNotEmpty) return stderr.trim();
  if (stdout.trim().isNotEmpty) return stdout.trim();
  return 'bd exited $exitCode with no output';
}

/// The `MIGRATION-FREEZE` marker path bd names in its refusal
/// (`bd <op> is blocked by the freeze marker at <path>.`), or null for the
/// fail-closed "cannot determine" shape, which names no marker.
String? _freezeMarkerPath(String stderr) => RegExp(
  r'blocked by the freeze marker at (.+)\.\s*$',
  multiLine: true,
).firstMatch(stderr)?.group(1);

String _lastNonEmptyLine(String source) {
  final lines = source.split('\n');
  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trim().isNotEmpty) return lines[i].trim();
  }
  return '';
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
