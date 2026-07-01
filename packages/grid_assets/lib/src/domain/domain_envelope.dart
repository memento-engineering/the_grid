/// The **domain envelope** — the SHARED machinery for "domains serialize their
/// own information" (the `SCRATCH-pub-capability-and-repo-split` precedent;
/// domain-agnostic, so every domain reuses ONE codec discipline instead of
/// re-deciding it).
///
/// The store: a bead's `metadata` is one JSON object and bd `--metadata`
/// merges at TOP-LEVEL-KEY granularity ("everyone gets a slot"). A domain owns
/// ONE top-level key (`grid.<domain>`) carrying its versioned envelope,
/// replaced whole on write:
///
/// ```json
/// { "grid.<domain>": { "assets_version": "0.0.1", "payload": { } } }
/// ```
///
/// `assets_version` is the pack's shape version, gated by
/// [envelopeVersionCompatible] (pub_semver parsing; the RULE: patch =
/// additive-only + a tolerant reader never writes back an envelope it did not
/// fully understand; breaking = minor pre-1.0 / major from 1.0, refused whole
/// — fail-closed). A `packs_version` field exists only for TOML packs that
/// implement the **gc packs protocol** — a plain Dart-asset domain (like
/// `grid.dart`) does NOT carry it; its (future) TOML codec would add it.
///
/// Flat dotted keys (the cursor / `grid.result.*` pattern) stay reserved for
/// CONCURRENT-writer state; the envelope is for single-writer domain
/// configuration.
library;

import 'package:pub_semver/pub_semver.dart';

/// Whether an envelope written at [theirs] is decodable by a pack whose shape
/// version is [ours].
///
/// Pub-style semantics over [Version.parse]: pre-1.0 (`0.y.z`) treats `y` as
/// breaking — compatible iff same major AND same minor; from 1.0 compatible
/// iff same major. Anything unparseable (garbage, negative components) is
/// incompatible — fail-closed.
bool envelopeVersionCompatible({required String ours, required String theirs}) {
  final Version mine;
  final Version other;
  try {
    mine = Version.parse(ours);
    other = Version.parse(theirs);
  } on FormatException {
    return false;
  }
  if (mine.major == 0) {
    return other.major == 0 && other.minor == mine.minor;
  }
  return other.major == mine.major;
}

/// The outcome of decoding a domain's envelope off a bead's metadata — sealed
/// so consumers switch exhaustively (house style). [C] is the domain's typed
/// config.
sealed class DomainEnvelopeResult<C> {
  const DomainEnvelopeResult();
}

/// The envelope decoded cleanly into the domain's typed [config].
class DomainEnvelopeDecoded<C> extends DomainEnvelopeResult<C> {
  /// Wraps the decoded [config].
  const DomainEnvelopeDecoded(this.config);

  /// The domain's typed configuration.
  final C config;
}

/// The bead carries no key for this domain — it declares nothing here (NOT an
/// error; the common case).
class DomainEnvelopeAbsent<C> extends DomainEnvelopeResult<C> {
  /// The absent result.
  const DomainEnvelopeAbsent();
}

/// The envelope was written by an incompatible pack version — fail-closed
/// (never a partial parse of a newer shape).
class DomainEnvelopeIncompatible<C> extends DomainEnvelopeResult<C> {
  /// Carries the envelope's [version].
  const DomainEnvelopeIncompatible(this.version);

  /// The `assets_version` the envelope carried.
  final String version;
}

/// The envelope is structurally broken (not a map, a missing version, a
/// malformed payload) — fail-closed with a [reason].
class DomainEnvelopeMalformed<C> extends DomainEnvelopeResult<C> {
  /// Carries the diagnostic [reason].
  const DomainEnvelopeMalformed(this.reason);

  /// What was wrong (diagnostics; never partially applied).
  final String reason;
}

/// Decodes a domain's envelope from a bead's full [metadata] map: reads
/// [domainKey], gates `assets_version` against [assetsVersion]
/// ([envelopeVersionCompatible]), and hands the `payload` object to
/// [parsePayload]. A [FormatException]/[TypeError] thrown by [parsePayload]
/// yields [DomainEnvelopeMalformed] — the fail-closed discipline every domain
/// inherits for free.
DomainEnvelopeResult<C> decodeDomainEnvelope<C>(
  Map<String, dynamic> metadata, {
  required String domainKey,
  required String assetsVersion,
  required C Function(Map<String, Object?> payload) parsePayload,
}) {
  final raw = metadata[domainKey];
  if (raw == null) return DomainEnvelopeAbsent<C>();
  if (raw is! Map) {
    return DomainEnvelopeMalformed<C>('"$domainKey" is not an object');
  }
  final envelope = raw.cast<String, Object?>();
  final version = envelope['assets_version'];
  if (version is! String) {
    return DomainEnvelopeMalformed<C>('missing/non-string "assets_version"');
  }
  if (!envelopeVersionCompatible(ours: assetsVersion, theirs: version)) {
    return DomainEnvelopeIncompatible<C>(version);
  }
  final payload = envelope['payload'];
  if (payload is! Map) {
    return DomainEnvelopeMalformed<C>('missing/non-object "payload"');
  }
  try {
    return DomainEnvelopeDecoded<C>(
      parsePayload(payload.cast<String, Object?>()),
    );
  } on FormatException catch (e) {
    return DomainEnvelopeMalformed<C>(e.message);
  } on TypeError catch (e) {
    return DomainEnvelopeMalformed<C>('payload shape: $e');
  }
}

/// The write half: the envelope value for a domain's metadata slot —
/// `{assets_version, payload}`. (For authoring tools / round-trip; the_grid
/// itself only reads work beads — A37. TOML gc-packs-protocol codecs add their
/// own `packs_version`; a plain Dart-asset domain does not carry one.)
Map<String, Object?> domainEnvelope({
  required String assetsVersion,
  required Map<String, Object?> payload,
}) => {'assets_version': assetsVersion, 'payload': payload};
