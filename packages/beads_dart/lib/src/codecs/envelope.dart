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

  /// Parses a flat bd `--json` payload from the upstream protocol corpus.
  ///
  /// Flat object payloads carry `schema_version` beside their command fields;
  /// flat arrays and scalars omit it. The returned [data] is therefore the
  /// value comparable with an enveloped variant's `data`. Throws
  /// [BdParseException] for malformed JSON and [BdSchemaDriftException] when
  /// an object advertises a schema other than [kBdSchemaVersion].
  factory BdEnvelope.parseFlat(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw BdParseException('invalid JSON from bd: ${e.message}', source);
    }

    if (decoded case final Map<String, dynamic> object
        when object.containsKey('schema_version')) {
      final version = object['schema_version'];
      if (version is! int) {
        throw BdParseException(
          'flat bd payload has non-integer schema_version',
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
      final data = Map<String, dynamic>.of(object)..remove('schema_version');
      return BdEnvelope(schemaVersion: version, data: data);
    }

    return BdEnvelope(schemaVersion: kBdSchemaVersion, data: decoded);
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
