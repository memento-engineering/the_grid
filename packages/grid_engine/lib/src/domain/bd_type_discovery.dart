import 'package:beads_dart/beads_dart.dart';

/// Returns the configured bd type names in [typesEnvelope].
///
/// [typesEnvelope] is bd's `types --json` data object. A present group must be
/// a list whose entries are non-empty strings (the shape `custom_types` uses)
/// or maps carrying a non-empty string `name` (the shape `core_types` uses),
/// so a future upstream convergence of the two shapes reads the same either
/// way. bd omits an empty group entirely, which is an empty result rather than
/// an error.
///
/// Every caller that scopes a bd read by TYPE needs this: an unregistered type
/// makes `bd list -t <type>` a refusal, so the type set is discovered from the
/// store instead of assumed.
Set<String> configuredBdTypeNames(
  Map<String, dynamic> typesEnvelope, {
  Iterable<String> fields = const <String>['custom_types'],
}) {
  final names = <String>{};
  for (final field in fields) {
    final raw = typesEnvelope[field];
    if (raw == null) continue;
    if (raw is! List) {
      throw BdParseException('bd type discovery field "$field" was not a list');
    }
    for (final entry in raw) {
      final name = switch (entry) {
        final String value => value,
        final Map<Object?, Object?> value when value['name'] is String =>
          value['name'] as String,
        _ => null,
      };
      if (name == null || name.isEmpty) {
        throw BdParseException('bd type discovery field "$field" had no name');
      }
      names.add(name);
    }
  }
  return names;
}
