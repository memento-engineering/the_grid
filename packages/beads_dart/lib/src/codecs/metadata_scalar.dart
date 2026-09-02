import 'dart:convert';

/// Renders a `metadata` value read back from bd as the TEXT its
/// `--set-metadata` writer sent.
///
/// bd 1.3 re-types numeric/boolean/null-looking `--set-metadata` values into
/// JSON scalars — `attempt=3` lands as `3`, `flag=true` as `true`,
/// `nothing=null` as JSON null — while every value a pre-1.3 binary wrote stays
/// a JSON string. One store therefore carries BOTH shapes for the same key, so
/// a reader comparing against the writer's string must normalise first. A
/// [String] is returned unchanged; anything else is rendered as its JSON text —
/// exactly what `JSON_UNQUOTE(JSON_EXTRACT(...))` yields on the SQL leg, so the
/// two read paths agree on string, number, boolean and null values.
String metadataScalarText(Object? value) =>
    value is String ? value : jsonEncode(value);

/// True when [metadata] carries [key] and its value equals [expected] under
/// [metadataScalarText] — the version-tolerant metadata equality every
/// beads_dart reader uses. An ABSENT key is never equal; a JSON-null value
/// equals the text `null`.
bool metadataEntryEquals(
  Map<String, dynamic> metadata,
  String key,
  String expected,
) => metadata.containsKey(key) && metadataScalarText(metadata[key]) == expected;
