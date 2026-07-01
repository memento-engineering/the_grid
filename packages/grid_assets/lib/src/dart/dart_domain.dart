/// The **`grid.dart` envelope** — the DART domain's serialized information on a
/// bead (the `SCRATCH-pub-capability-and-repo-split` design; the FIRST instance
/// of the "domains serialize their own information" pattern, so this shape is
/// the precedent).
///
/// The store: a bead's `metadata` is ONE JSON object and bd `--metadata` merges
/// at TOP-LEVEL-KEY granularity ("everyone gets a slot"). Concurrent-writer
/// state (the cursor, grades) stays FLAT dotted keys so parallel writers never
/// clobber; single-writer domain CONFIGURATION takes **one envelope key per
/// domain**, replaced whole on write:
///
/// ```json
/// {
///   "grid.dart": {
///     "assets_version": "0.0.1",
///     "packs_version": null,
///     "payload": { "pub": { "links": [ ... ] } }
///   }
/// }
/// ```
///
/// `assets_version` is the codec's version discriminator (this pack's shape
/// version); `packs_version` is reserved for the gc pack-protocol scheme
/// (nullable/missing okay). Decoding is FAIL-CLOSED: an envelope written by an
/// incompatible (newer) pack yields [DartEnvelopeIncompatible] — never a
/// silent partial parse; malformed JSON yields [DartEnvelopeMalformed].
///
/// The config hangs on the **WORK bead** (bead/work information — "the desire
/// to dev-time link"; the substation's location and the bead's worktree are
/// projections). It is part of the work DEFINITION, authored with the bead;
/// the_grid only READS it at provision time — A37 (pristine work source) holds
/// by construction.
library;

import 'package:meta/meta.dart';

import 'pub_links.dart';

/// The bead-metadata top-level key the DART domain owns. Pub is subordinate to
/// the Dart domain ("Pub doesn't work without Dart"), so pub linkage rides the
/// `grid.dart` payload rather than a `grid.pub` sibling.
const String kDartDomainKey = 'grid.dart';

/// This pack's envelope-shape version (the codec discriminator).
///
/// The versioning RULE (the precedent for every domain envelope): a **patch**
/// bump is ADDITIVE-only — an older reader tolerates it (unknown fields are
/// ignored on read) and, being a tolerant reader, must NEVER write back an
/// envelope it did not fully understand (the_grid never writes work beads at
/// all — A37; authoring tools re-author from typed config). A **breaking**
/// shape change bumps minor pre-1.0 / major from 1.0, which
/// [isCompatibleAssetsVersion] refuses whole (fail-closed).
const String kDartAssetsVersion = '0.0.1';

/// Whether an envelope written at [version] is decodable by THIS pack.
///
/// Pub-style semantics: pre-1.0 (`0.y.z`) treats `y` as breaking — compatible
/// iff same major AND same minor; from 1.0 compatible iff same major. A
/// version this can't parse is incompatible (fail-closed).
bool isCompatibleAssetsVersion(String version) {
  final ours = _parse(kDartAssetsVersion);
  final theirs = _parse(version);
  if (theirs == null || ours == null) return false;
  if (ours.major == 0) {
    return theirs.major == 0 && theirs.minor == ours.minor;
  }
  return theirs.major == ours.major;
}

({int major, int minor, int patch})? _parse(String version) {
  final parts = version.split('.');
  if (parts.length != 3) return null;
  final major = int.tryParse(parts[0]);
  final minor = int.tryParse(parts[1]);
  final patch = int.tryParse(parts[2]);
  if (major == null || minor == null || patch == null) return null;
  // Semver components are non-negative; "1.-1.0" must not slip a gate.
  if (major < 0 || minor < 0 || patch < 0) return null;
  return (major: major, minor: minor, patch: patch);
}

/// The decoded DART domain configuration (the envelope's typed payload).
@immutable
class DartDomainConfig {
  /// Creates the config.
  const DartDomainConfig({
    this.pub = const PubLinkConfig(),
    this.packsVersion,
  });

  /// The pub dev-time linkage slice.
  final PubLinkConfig pub;

  /// The gc pack-protocol version the envelope carried (reserved; nullable).
  final String? packsVersion;

  /// The full envelope value for the [kDartDomainKey] metadata slot —
  /// `{assets_version, packs_version?, payload}` — stamped with THIS pack's
  /// [kDartAssetsVersion]. (The write side is for authoring tools/round-trip;
  /// the_grid itself only reads work beads — A37.)
  Map<String, Object?> toEnvelope() => {
    'assets_version': kDartAssetsVersion,
    if (packsVersion != null) 'packs_version': packsVersion,
    'payload': {'pub': pub.toJson()},
  };

  @override
  bool operator ==(Object other) =>
      other is DartDomainConfig &&
      other.pub == pub &&
      other.packsVersion == packsVersion;

  @override
  int get hashCode => Object.hash(pub, packsVersion);
}

/// The outcome of decoding [kDartDomainKey] off a bead's metadata — sealed so
/// consumers switch exhaustively (house style).
sealed class DartEnvelopeResult {
  const DartEnvelopeResult();
}

/// The envelope decoded cleanly.
class DartEnvelopeDecoded extends DartEnvelopeResult {
  /// Wraps the decoded [config].
  const DartEnvelopeDecoded(this.config);

  /// The typed DART domain configuration.
  final DartDomainConfig config;
}

/// The bead carries no `grid.dart` key — the domain declares nothing here
/// (NOT an error; the common case).
class DartEnvelopeAbsent extends DartEnvelopeResult {
  /// The absent result.
  const DartEnvelopeAbsent();
}

/// The envelope was written by an incompatible pack version — fail-closed
/// (never a partial parse of a newer shape).
class DartEnvelopeIncompatible extends DartEnvelopeResult {
  /// Carries the envelope's [version] against [kDartAssetsVersion].
  const DartEnvelopeIncompatible(this.version);

  /// The `assets_version` the envelope carried.
  final String version;
}

/// The envelope is structurally broken (not a map, a missing version, a
/// malformed payload) — fail-closed with a [reason].
class DartEnvelopeMalformed extends DartEnvelopeResult {
  /// Carries the diagnostic [reason].
  const DartEnvelopeMalformed(this.reason);

  /// What was wrong (diagnostics; never partially applied).
  final String reason;
}

/// Decodes the DART domain envelope from a bead's full [metadata] map (the
/// read half — the_grid reads the WORK bead at provision time; A37).
DartEnvelopeResult decodeDartEnvelope(Map<String, dynamic> metadata) {
  final raw = metadata[kDartDomainKey];
  if (raw == null) return const DartEnvelopeAbsent();
  if (raw is! Map) {
    return const DartEnvelopeMalformed('"$kDartDomainKey" is not an object');
  }
  final envelope = raw.cast<String, Object?>();
  final version = envelope['assets_version'];
  if (version is! String) {
    return const DartEnvelopeMalformed('missing/non-string "assets_version"');
  }
  if (!isCompatibleAssetsVersion(version)) {
    return DartEnvelopeIncompatible(version);
  }
  final payload = envelope['payload'];
  if (payload is! Map) {
    return const DartEnvelopeMalformed('missing/non-object "payload"');
  }
  try {
    final map = payload.cast<String, Object?>();
    final pubRaw = map['pub'];
    final pub = pubRaw == null
        ? const PubLinkConfig()
        : PubLinkConfig.fromJson((pubRaw as Map).cast<String, Object?>());
    return DartEnvelopeDecoded(
      DartDomainConfig(
        pub: pub,
        packsVersion: envelope['packs_version'] as String?,
      ),
    );
  } on FormatException catch (e) {
    return DartEnvelopeMalformed(e.message);
  } on TypeError catch (e) {
    return DartEnvelopeMalformed('payload shape: $e');
  }
}
