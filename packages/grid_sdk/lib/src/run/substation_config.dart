/// Operator-supplied appended substation identity (the append-only roster
/// layer a station shell parses from `--substation` and hands to the
/// delegate's arming policy).
///
/// NAME DOPPELGANGER (tg-at3r): `grid_engine` exports a DIFFERENT
/// `SubstationConfig` — its internal freezed arming/ownership domain value
/// (`substationId`/`ownedSubstations`/`driveList`/…). This barrel's curated
/// grid_engine re-export deliberately omits the engine one, so importing
/// `grid_sdk.dart` alone always yields THIS type; a file importing both
/// barrels unprefixed must `show`/`hide` one of them. Disambiguating the
/// engine type is tracked as follow-up hygiene.
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
