/// Operator-supplied appended substation identity (the append-only roster
/// layer a station shell parses from `--substation` and hands to the
/// delegate's arming policy).
class SubstationConfig {
  /// Creates an appended substation value.
  const SubstationConfig({
    required this.name,
    required this.root,
    required this.prefix,
  });

  /// The station-unique name.
  final String name;

  /// The absolute work-store root.
  final String root;

  /// The work store's issue-id prefix.
  final String prefix;
}
