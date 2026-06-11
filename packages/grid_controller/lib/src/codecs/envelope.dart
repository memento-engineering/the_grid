import 'dart:convert';

import '../errors/bd_exception.dart';

/// The pinned bd JSON envelope version (`BD_JSON_ENVELOPE=1`). Asserted on
/// every decode; a mismatch is upstream drift (ADR-0001 Decision 4).
const int kBdSchemaVersion = 1;

/// A decoded bd `--json` envelope: the top-level `{schema_version, data}`.
///
/// Decoding asserts `schema_version == 1` and throws on malformed JSON or a
/// version mismatch. Error envelopes (`data: {error: ...}`) decode fine here —
/// distinguishing success from failure is the caller's job, by exit code (see
/// [BdCommandFailed]); [errorMessage] is offered as a convenience.
class BdEnvelope {
  const BdEnvelope({required this.schemaVersion, required this.data});

  /// Parses [source], asserting the pinned schema version.
  ///
  /// Throws [BdParseException] on non-JSON / non-object / missing version, and
  /// [BdSchemaDriftException] when the version differs from [kBdSchemaVersion].
  factory BdEnvelope.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw BdParseException('invalid JSON from bd: ${e.message}', source);
    }
    if (decoded is! Map<String, dynamic>) {
      throw BdParseException('bd envelope was not a JSON object', source);
    }
    final version = decoded['schema_version'];
    if (version is! int) {
      throw BdParseException(
        'bd envelope missing integer schema_version',
        source,
      );
    }
    if (version != kBdSchemaVersion) {
      throw BdSchemaDriftException(
        found: version,
        expected: kBdSchemaVersion,
        source: source,
      );
    }
    return BdEnvelope(schemaVersion: version, data: decoded['data']);
  }

  final int schemaVersion;
  final Object? data;

  /// `data` as a list of JSON objects (list-returning commands like
  /// `ready`, `list`, `dep list`). Throws [BdParseException] on shape mismatch.
  List<Map<String, dynamic>> get dataList {
    final value = data;
    if (value is! List) {
      throw BdParseException('expected a JSON list in `data`, got $value');
    }
    return [
      for (final element in value)
        if (element is Map<String, dynamic>)
          element
        else
          throw BdParseException(
            'list element was not a JSON object: $element',
          ),
    ];
  }

  /// `data` as a JSON object (object-returning commands like `statuses`,
  /// `types`, `info`). Throws [BdParseException] on shape mismatch.
  Map<String, dynamic> get dataMap {
    final value = data;
    if (value is! Map<String, dynamic>) {
      throw BdParseException('expected a JSON object in `data`, got $value');
    }
    return value;
  }

  /// `data.error` (or a top-level `error`) when this envelope carries one.
  String? get errorMessage {
    final value = data;
    if (value is Map<String, dynamic>) {
      final error = value['error'];
      if (error is String && error.isNotEmpty) return error;
    }
    return null;
  }
}
