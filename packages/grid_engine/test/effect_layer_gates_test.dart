// The capability-land derailment gates (ADR-0008 Decision 3, amended
// 2026-07-02 — the context rip-out).
//
// With the sandbox wall gone, the effect layer (lib/src/sdk/) can REACH the
// tree — so the invariants move from "unreachable by construction" to
// "enforced as gates" (the ADR-0009 posture, extended to capability-land):
//
//   1. The effect layer NEVER registers a dependency (`dependOn*` is the
//      tree/build verb — a registration outside build corrupts the reactive
//      graph; the effect verb is the non-binding `getInheritedSeedOfExactType`).
//   2. The effect layer NEVER subscribes (`addListener` on anything it reads
//      from context would be a second pipeline into the tree — invariant 1).
//   3. The effect layer NEVER holds the writer (`StationBeadWriter` — the
//      chokepoint belongs to the Host, off-build; invariant 2).
//   4. The effect layer NEVER dirties the tree (`markNeedsRebuild`).
//
// These are SOURCE gates over the SDK's own files, with a positive control so
// a path/glob regression cannot make them vacuous: the scan must SEE the
// effect verb in use (allocation.dart reads ambient values with it).

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// The effect layer: every file under lib/src/sdk/ — resolved via the package
/// URI (CWD-independent, like the track_e structural fence).
Iterable<File> _sdkSources() {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:grid_engine/grid_engine.dart'),
  );
  final sdkDir = Directory.fromUri(libUri!.resolve('src/sdk/'));
  return sdkDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
}

void main() {
  group('effect-layer gates (capability-land, ADR-0008 D3 2026-07-02)', () {
    test('positive control: the scan sees real SDK source', () {
      final sources = _sdkSources().toList();
      expect(sources, isNotEmpty, reason: 'lib/src/sdk must exist and be scanned');
      final all = sources.map((f) => f.readAsStringSync()).join('\n');
      // The effect verb IS used by the SDK (allocation.dart's ambient reads) —
      // proves the scan reads real bytes, so the negative gates below cannot
      // pass vacuously against an empty/moved directory.
      expect(
        all,
        contains('getInheritedSeedOfExactType'),
        reason: 'the effect verb must appear in the scanned SDK source '
            '(vacuousness control)',
      );
    });

    test('gate 1: no dependency registration (dependOn*) in the effect layer',
        () {
      for (final f in _sdkSources()) {
        expect(
          f.readAsStringSync(),
          isNot(contains('dependOnInheritedSeedOfExactType')),
          reason: '${f.path}: the effect layer must use the non-binding '
              'effect verb, never a build-phase dependency registration',
        );
      }
    });

    test('gate 2: no subscriptions (addListener) in the effect layer', () {
      for (final f in _sdkSources()) {
        expect(
          f.readAsStringSync(),
          isNot(contains('.addListener(')),
          reason: '${f.path}: the effect layer never subscribes — one pipeline '
              'subscription lives at the work boundary (invariant 1)',
        );
      }
    });

    test('gate 3: no writer (StationBeadWriter) in the effect layer', () {
      for (final f in _sdkSources()) {
        expect(
          f.readAsStringSync(),
          isNot(contains('StationBeadWriter')),
          reason: '${f.path}: the chokepoint belongs to the Host, off-build '
              '(invariant 2)',
        );
      }
    });

    test('gate 4: no tree dirtying (markNeedsRebuild) in the effect layer', () {
      for (final f in _sdkSources()) {
        expect(
          f.readAsStringSync(),
          isNot(contains('markNeedsRebuild')),
          reason: '${f.path}: an effect never dirties the tree — only the '
              'observing node marks dirty (ADR-0007 §6.1)',
        );
      }
    });

    test('the wall stays down honestly: no sandbox language in the SDK', () {
      // ADR-0009 dissolved the sandbox; ADR-0008 D3 (2026-07-02) purged the
      // framing. A reintroduction of wall-language usually rides a
      // reintroduction of the wall — keep the docs honest.
      for (final f in _sdkSources()) {
        expect(
          f.readAsStringSync().toLowerCase(),
          isNot(contains('sandbox')),
          reason: '${f.path}: the sandbox framing was retired (ADR-0009 / '
              'ADR-0008 D3 2026-07-02) — describe layering + gates instead',
        );
      }
    });
  });
}
