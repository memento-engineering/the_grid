/// The capability MODEL (ADR-0011 D6): typed capability **facts**, per-fact
/// composition (the cascade math), **containment** matching, toolchain
/// **probes**, and **TTL re-validation** of a held lease. Moved into the engine
/// SDK from `grid_federation` (the honesty-pass D-A9/D-B5 split, 2026-07-03):
/// the engine knows federation in CONCEPT only, and this is the transport-free
/// half of it.
///
/// The literal `InheritedSeed` cascade NODE — config nodes as ancestors of work
/// nodes, nearest-wins — is a later consumer wrapper over this model; here we
/// deliver only the pure cascade MATH ([CapabilityFacts.compose] +
/// [CapabilityFacts.deriveTargets]), the matching relation
/// ([CapabilityFacts.matches]), the probe seam ([CapabilityProbe]), and the
/// renewal-time staleness check ([CapabilityRevalidator]).
///
/// Per-fact composition, declared by the fact's domain (ADR-0011 D6):
///  - **scalar** facts OVERRIDE (the nearer/child value wins);
///  - **set** facts UNION (values accumulate).
/// The toolchain **targets** (`system-os`, `dart-target`, `flutter-target`) and
/// `radio` are SET-valued — a station is a capability-profiled slot, not a
/// scalar count, which is what "federated resources" means.
///
/// Matching is generalized declare-and-check **by CONTAINMENT**
/// (`station.facts ⊨ order.requires`): a required scalar must be present and
/// equal; a required set must be a subset of the station's set. **Fail-closed**
/// on a missing fact.
///
/// `dart:io` is touched only by the default [ToolchainProbe] tool query; the
/// value types + math are pure, and tests drive a [FakeProbe] (no real
/// toolchain, fully offline + deterministic).
library;

import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

/// The `system-os` fact key — the operating system(s) a station runs
/// (`{linux}`, `{macos}`, …). Set-valued (a singleton in practice).
const String kSystemOs = 'system-os';

/// The `dart-target` fact key — the platform(s) the dart toolchain can build
/// for. Set-valued; derives from [kSystemOs] when undeclared.
const String kDartTarget = 'dart-target';

/// The `flutter-target` fact key — the platform(s) the flutter toolchain can
/// build for. Set-valued; derives from [kDartTarget] when undeclared.
const String kFlutterTarget = 'flutter-target';

/// The `radio` fact key — the radios a station exposes (`{ble}`, `{ble, wifi}`).
/// Set-valued (it unions across composed domains).
const String kRadio = 'radio';

/// The derived-default chain, BROAD → NARROW (ADR-0011 D6): a missing
/// narrower target derives from the nearest broader one
/// (`flutter-target ⟸ dart-target ⟸ system-os`). Used by
/// [CapabilityFacts.deriveTargets]; NOT applied by [CapabilityFacts.matches]
/// (a probe reports ground truth — an absent toolchain must not be back-filled).
const List<String> kTargetChain = [kSystemOs, kDartTarget, kFlutterTarget];

/// The fact keys that are SET-valued this pass (the domains' set facts). When a
/// flat wire profile carries one of these as a bare string, [CapabilityFacts]
/// reads it as a singleton set; any other key with a string value is a scalar.
const Set<String> kSetFactKeys = {
  kSystemOs,
  kDartTarget,
  kFlutterTarget,
  kRadio,
};

/// A typed bag of capability facts — a station's profile or an order's
/// requirements (ADR-0011 D6).
///
/// Two fact kinds with distinct composition: [scalars] OVERRIDE (child wins)
/// and [sets] UNION. Immutable by convention (like the rest of the federation
/// wire types); compose/derive return fresh instances.
@immutable
class CapabilityFacts {
  /// Creates a fact bag from [scalars] (override facts) + [sets] (union facts).
  const CapabilityFacts({
    this.scalars = const {},
    this.sets = const {},
  });

  /// The scalar (override) facts — a single value per key.
  final Map<String, String> scalars;

  /// The set (union) facts — a set of values per key.
  final Map<String, Set<String>> sets;

  /// True when no facts are declared at all.
  bool get isEmpty => scalars.isEmpty && sets.isEmpty;

  /// The scalar value for [key], or `null` if undeclared.
  String? scalar(String key) => scalars[key];

  /// The set value for [key] (empty when undeclared).
  Set<String> setOf(String key) => sets[key] ?? const {};

  /// Composes a config cascade per ADR-0011 D6: [child] (the nearer node)
  /// layered over [parent]. **Scalar** facts OVERRIDE (child wins); **set**
  /// facts UNION. Pure — returns a fresh bag, mutating neither input.
  ///
  /// This is the cascade MATH; stacking ancestors in tree order is the future
  /// `InheritedSeed` node's job (a later track), not this file's.
  static CapabilityFacts compose(CapabilityFacts parent, CapabilityFacts child) {
    final scalars = {...parent.scalars, ...child.scalars}; // child overrides
    final sets = <String, Set<String>>{};
    for (final e in parent.sets.entries) {
      sets[e.key] = {...e.value};
    }
    for (final e in child.sets.entries) {
      (sets[e.key] ??= <String>{}).addAll(e.value); // union
    }
    return CapabilityFacts(scalars: scalars, sets: sets);
  }

  /// Returns a copy with the derived target defaults filled (ADR-0011 D6):
  /// a missing/empty narrower target inherits the nearest broader present one
  /// along [kTargetChain] (`flutter-target ⟸ dart-target ⟸ system-os`). Only
  /// divergence (a cross-compile/multi-target station) needs restating.
  ///
  /// This is a CONFIG-authoring convenience for declared facts — it is
  /// deliberately NOT applied by [matches], because a [CapabilityProbe] reports
  /// ground truth (an absent flutter toolchain emits NO `flutter-target`, and
  /// must not be back-filled from `dart-target` into a false match).
  CapabilityFacts deriveTargets() {
    final newSets = <String, Set<String>>{
      for (final e in sets.entries) e.key: {...e.value},
    };
    Set<String>? broader;
    for (final key in kTargetChain) {
      final cur = newSets[key];
      if (cur != null && cur.isNotEmpty) {
        broader = cur;
      } else if (broader != null) {
        broader = newSets[key] = {...broader};
      }
    }
    return CapabilityFacts(scalars: {...scalars}, sets: newSets);
  }

  /// Whether [station]'s facts SATISFY [requires] by CONTAINMENT (ADR-0011 D6):
  /// every required scalar is present and equal, and every required set is a
  /// subset of the station's set. **Fail-closed**: a required fact the station
  /// does not declare → no match. An empty requirement matches vacuously.
  ///
  /// Matches RAW facts (no implicit [deriveTargets]); compose + derive the
  /// station profile first if you want the derived defaults to count.
  static bool matches(CapabilityFacts station, CapabilityFacts requires) {
    for (final e in requires.scalars.entries) {
      if (station.scalars[e.key] != e.value) return false;
    }
    for (final e in requires.sets.entries) {
      if (e.value.isEmpty) continue; // an empty required set demands nothing
      final have = station.sets[e.key];
      if (have == null || !e.value.every(have.contains)) return false;
    }
    return true;
  }

  /// The flat wire-profile form (the `presence.profile` shape): scalar facts as
  /// strings, set facts as sorted string lists. Bridges the typed model onto
  /// the opaque profile transported by presence.
  Map<String, Object?> toProfile() => {
    ...scalars,
    for (final e in sets.entries) e.key: (e.value.toList()..sort()),
  };

  /// Reads a flat wire profile back into typed facts. A `List` value is a set
  /// fact; a `String` value is a set fact when its key is a known set key
  /// ([kSetFactKeys], read as a singleton) and a scalar otherwise. Other value
  /// types are coerced to a scalar string. Tolerant by design — it accepts the
  /// legacy `{'system-os': 'linux'}` string form for a set key.
  static CapabilityFacts fromProfile(Map<String, Object?> profile) {
    final scalars = <String, String>{};
    final sets = <String, Set<String>>{};
    for (final e in profile.entries) {
      final v = e.value;
      if (v is List) {
        sets[e.key] = {for (final x in v) '$x'};
      } else if (v is String && kSetFactKeys.contains(e.key)) {
        sets[e.key] = {v};
      } else if (v != null) {
        scalars[e.key] = '$v';
      }
    }
    return CapabilityFacts(scalars: scalars, sets: sets);
  }

  @override
  bool operator ==(Object other) =>
      other is CapabilityFacts &&
      _scalarsEq(scalars, other.scalars) &&
      _setsEq(sets, other.sets);

  @override
  int get hashCode {
    var h = 0;
    for (final e in scalars.entries) {
      h ^= Object.hash(e.key, e.value);
    }
    for (final e in sets.entries) {
      var sh = 0;
      for (final v in e.value) {
        sh ^= v.hashCode;
      }
      h ^= Object.hash(e.key, sh);
    }
    return h;
  }

  @override
  String toString() => 'CapabilityFacts(scalars: $scalars, sets: $sets)';

  static bool _scalarsEq(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  static bool _setsEq(
    Map<String, Set<String>> a,
    Map<String, Set<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null ||
          other.length != e.value.length ||
          !e.value.every(other.contains)) {
        return false;
      }
    }
    return true;
  }
}

/// Probes a station's CURRENT capability facts (ADR-0011 D6) — an observation.
///
/// `system-os` / `dart-target` / `flutter-target` are PROBED + DYNAMIC: a probe
/// reports ground truth at the moment it is read, so a toolchain that appears or
/// disappears shifts the profile and (via re-match / [CapabilityRevalidator])
/// the reconcile decision. Implementations: [ToolchainProbe] (the real, local,
/// offline-safe toolchain probe) and [FakeProbe] (tests).
abstract interface class CapabilityProbe {
  /// Reads the current capability facts.
  Future<CapabilityFacts> probe();
}

/// A controllable [CapabilityProbe] for tests: returns [facts], which a test may
/// reassign between reads to simulate a shifting configuration (a toolchain
/// gained or lost). No IO.
class FakeProbe implements CapabilityProbe {
  /// Creates a fake probe seeded with [facts].
  FakeProbe(this.facts);

  /// The facts the next [probe] returns; reassign to simulate a shift.
  CapabilityFacts facts;

  @override
  Future<CapabilityFacts> probe() async => facts;
}

/// Runs `<executable> --version` and returns its combined output, or `null` when
/// the tool is absent / not runnable. Injectable into [ToolchainProbe] so tests
/// need no real toolchain; the default runs a real local `Process.run` (offline
/// — a local toolchain query touches no network).
typedef ToolchainQuery = Future<String?> Function(String executable);

/// The real, LOCAL toolchain [CapabilityProbe] (ADR-0011 D6). Reports
/// `system-os` from [Platform] (the authoritative host OS), and a host-default
/// `dart-target` / `flutter-target` for whichever of `dart` / `flutter` is
/// present (probed via `--version`). An absent toolchain emits NO target fact
/// (fail-closed — never derived), so a station without flutter cannot match a
/// `flutter-target` requirement.
///
/// Cross-compile target SETS (android/ios/web/…) are a richer probe deferred to
/// the asset-repo split, where these probes move into
/// `dart_grid_assets` / `flutter_grid_assets` (their domains, M6 placement
/// decision). Probing the local toolchain is offline-safe; tests inject a
/// [ToolchainQuery] fake rather than spawn real processes.
class ToolchainProbe implements CapabilityProbe {
  /// Creates a probe. [os] defaults to the host ([Platform.operatingSystem]);
  /// [query] defaults to a real `<exe> --version` process run.
  ToolchainProbe({String? os, ToolchainQuery? query})
    : _os = os ?? Platform.operatingSystem,
      _query = query ?? _realQuery;

  final String _os;
  final ToolchainQuery _query;

  @override
  Future<CapabilityFacts> probe() async {
    final sets = <String, Set<String>>{
      kSystemOs: {_os},
    };
    final dartOut = await _query('dart');
    if (dartOut != null) {
      sets[kDartTarget] = {parseToolchainOs(dartOut) ?? _os};
    }
    final flutterOut = await _query('flutter');
    if (flutterOut != null) {
      sets[kFlutterTarget] = {_os};
    }
    return CapabilityFacts(sets: sets);
  }

  static Future<String?> _realQuery(String executable) async {
    try {
      final r = await Process.run(executable, const ['--version']);
      if (r.exitCode != 0) return null;
      return '${r.stdout}${r.stderr}';
    } on ProcessException {
      return null; // not on PATH
    }
  }
}

/// Extracts the OS token from a `dart --version` line's platform tag — e.g.
/// `... on "macos_arm64"` → `macos` — or `null` when none is recognized. Pure;
/// the recognized OS names mirror [Platform.operatingSystem].
String? parseToolchainOs(String versionOutput) {
  final m = RegExp(r'on "([a-z]+)_').firstMatch(versionOutput);
  final os = m?.group(1);
  const known = {'linux', 'macos', 'windows', 'android', 'ios', 'fuchsia'};
  return known.contains(os) ? os : null;
}

/// The outcome of a TTL-renewal re-validation (ADR-0011 D6, depth #2).
@immutable
class RevalidationResult {
  /// Creates a result carrying the [stale] decision + the [currentFacts] read.
  const RevalidationResult({required this.stale, required this.currentFacts});

  /// `true` when the held lease's requirements NO LONGER match the freshly
  /// probed facts — the reconcile DECISION: the consumer should lapse the lease
  /// and re-place the order on another match.
  final bool stale;

  /// The facts read by this re-validation (the shifted profile).
  final CapabilityFacts currentFacts;

  @override
  String toString() =>
      'RevalidationResult(stale: $stale, currentFacts: $currentFacts)';
}

/// Bridges [CapabilityFacts] into freezed/json_serializable's codec (the
/// `CapabilityStep.requires` field, the honesty-pass D-B5, 2026-07-03) so a
/// step's declared per-requirement [CapabilityFacts] round-trips through the
/// SAME `Circuit`/`CircuitStep` JSON shape every other field already does.
/// Reuses [CapabilityFacts.toProfile]/[fromProfile] — the identical wire form
/// [Presence.profile] carries — rather than inventing a second serialization.
/// Null-safe both ways: an undeclared requirement (the overwhelmingly common
/// case — most steps resolve locally) round-trips as `null`, never `{}`.
class CapabilityFactsConverter
    implements JsonConverter<CapabilityFacts?, Map<String, dynamic>?> {
  /// Const-constructible so it can annotate a freezed factory field.
  const CapabilityFactsConverter();

  @override
  CapabilityFacts? fromJson(Map<String, dynamic>? json) =>
      json == null ? null : CapabilityFacts.fromProfile(json);

  @override
  Map<String, dynamic>? toJson(CapabilityFacts? object) => object?.toProfile();
}

/// Re-validates a held lease against CURRENT capabilities at TTL renewal
/// (ADR-0011 D6, shift-revocation depth #2 — re-check at the renewal boundary,
/// NOT continuously).
///
/// At each renewal the consumer calls [revalidate] with the lease's original
/// requirements; it re-probes and checks containment still holds. If the
/// station's facts shifted so the requirements no longer match, [stale] is true
/// → the lease lapses and the order re-places on another match. Bounded by the
/// TTL; reuses the existing lease mechanism (no continuous watch / live
/// migration — a later depth).
class CapabilityRevalidator {
  /// Creates a re-validator over [probe].
  CapabilityRevalidator(this._probe);

  final CapabilityProbe _probe;

  /// Re-probes the current facts and returns the staleness decision for a lease
  /// that was granted against [requires].
  Future<RevalidationResult> revalidate(CapabilityFacts requires) async {
    final current = await _probe.probe();
    return RevalidationResult(
      stale: !CapabilityFacts.matches(current, requires),
      currentFacts: current,
    );
  }
}
