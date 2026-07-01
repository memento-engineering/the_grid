/// The **`grid.dart` envelope** — the DART domain's serialized information on a
/// bead, riding the shared domain-envelope machinery
/// (`src/domain/domain_envelope.dart`; the "domains serialize their own
/// information" precedent).
///
/// ```json
/// {
///   "grid.dart": {
///     "assets_version": "0.0.1",
///     "payload": { "pub": { "links": [ ... ] } }
///   }
/// }
/// ```
///
/// No `packs_version` here: that field belongs to TOML packs implementing the
/// **gc packs protocol**, which this Dart-asset domain does not.
///
/// The config hangs on the **WORK bead** (bead/work information — "the desire
/// to dev-time link"; the substation's location and the bead's worktree are
/// projections). It is part of the work DEFINITION, authored with the bead;
/// the_grid only READS it at provision time — A37 (pristine work source) holds
/// by construction.
library;

import 'package:meta/meta.dart';

import '../domain/domain_envelope.dart';
import 'pub_links.dart';

/// The bead-metadata top-level key the DART domain owns. Pub is subordinate to
/// the Dart domain ("Pub doesn't work without Dart"), so pub linkage rides the
/// `grid.dart` payload rather than a `grid.pub` sibling.
const String kDartDomainKey = 'grid.dart';

/// This pack's envelope-shape version. The rule (shared discipline —
/// `envelopeVersionCompatible`): patch = additive-only + tolerant reader that
/// never writes back; breaking = minor pre-1.0 / major from 1.0, refused whole.
const String kDartAssetsVersion = '0.0.1';

/// The decoded DART domain configuration (the envelope's typed payload).
@immutable
class DartDomainConfig {
  /// Creates the config.
  const DartDomainConfig({this.pub = const PubLinkConfig()});

  /// The pub dev-time linkage slice.
  final PubLinkConfig pub;

  /// The full envelope value for the [kDartDomainKey] metadata slot, stamped
  /// with THIS pack's [kDartAssetsVersion]. (The write side is for authoring
  /// tools/round-trip; the_grid itself only reads work beads — A37.)
  Map<String, Object?> toEnvelope() => domainEnvelope(
    assetsVersion: kDartAssetsVersion,
    payload: {'pub': pub.toJson()},
  );

  @override
  bool operator ==(Object other) =>
      other is DartDomainConfig && other.pub == pub;

  @override
  int get hashCode => pub.hashCode;
}

/// Decodes the DART domain envelope from a bead's full [metadata] map (the
/// read half — the_grid reads the WORK bead at provision time; A37). The
/// version gate + fail-closed malformed handling ride the shared
/// [decodeDomainEnvelope].
DomainEnvelopeResult<DartDomainConfig> decodeDartEnvelope(
  Map<String, dynamic> metadata,
) => decodeDomainEnvelope<DartDomainConfig>(
  metadata,
  domainKey: kDartDomainKey,
  assetsVersion: kDartAssetsVersion,
  parsePayload: (payload) {
    final pubRaw = payload['pub'];
    if (pubRaw == null) return const DartDomainConfig();
    if (pubRaw is! Map) {
      throw const FormatException('"pub" must be an object');
    }
    return DartDomainConfig(
      pub: PubLinkConfig.fromJson(pubRaw.cast<String, Object?>()),
    );
  },
);
