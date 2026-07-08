// The D-H state-leak fence (ADR-0008 Decision-H, sharpened by the 2026-07-02
// agent-scope rip-out that purged the engine's notifier `current` mirrors by
// hand): NO public SYNCHRONOUS accessor over `StateNotifier` state may exist in
// grid_sdk's authoring surface.
//
// `GridDelegate` IS a `StateNotifier<GridConfiguration>`. D-H bans "public sync
// accessors over notifier state" (and "no sync state reads without
// subscribing"). Configuration must reach consumers ONLY as an *observed value*:
// `runGrid` provides the emitted value as `InheritedSeed<GridConfiguration>`,
// and `build()` observes it via `GridConfiguration.of` — which SUBSCRIBES
// (`dependOnInheritedSeedOfExactType`). The delegate (the notifier) must never
// ride the tree, so its `.state` can never be snapshotted; and no getter/method
// may re-surface that state synchronously.
//
// These are SOURCE gates over grid_sdk's own `lib/`, modeled on grid_engine's
// effect_layer_gates_test — each with a positive/vacuousness control so a
// path/glob regression cannot make them pass silently. Guards are LOUD or GONE
// (ADR-0008 D-6): instructions decay, so the invariant is fenced structurally.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Every AUTHORED `.dart` under grid_sdk/lib/ (excludes generated
/// `.freezed.dart`), resolved via the package URI — CWD-independent, like
/// effect_layer_gates_test's `_sdkSources`.
Iterable<File> _libSources() {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:grid_sdk/grid_sdk.dart'),
  );
  final libDir = Directory.fromUri(libUri!.resolve('./'));
  return libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (f) => f.path.endsWith('.dart') && !f.path.endsWith('.freezed.dart'),
      );
}

/// Strips `//` / `///` line comments: the gates reason about CODE. The D-H
/// design notes deliberately DISCUSS `GridConfiguration`, the delegate, and
/// `.state` in prose — a substring/regex over raw bytes would trip on the very
/// documentation that explains the invariant. (No block comments are used in
/// this package.)
String _code(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  group('D-H fence: no public sync accessor over StateNotifier state (grid_sdk)',
      () {
    test('positive control: the scan sees real source AND the sanctioned '
        'subscribing observation', () {
      final sources = _libSources().toList();
      expect(
        sources,
        isNotEmpty,
        reason: 'grid_sdk/lib must exist and be scanned',
      );
      final all = sources.map((f) => f.readAsStringSync()).join('\n');
      // Configuration reaches consumers as an OBSERVED value: GridConfiguration.of
      // SUBSCRIBES. Its presence proves the scan reads real bytes, so the
      // negative gates below cannot pass vacuously against a moved/empty dir.
      expect(
        all,
        contains('dependOnInheritedSeedOfExactType<GridConfiguration>'),
        reason: 'the sanctioned subscribing observation '
            '(GridConfiguration.of) must appear in the scanned source '
            '— vacuousness control',
      );
    });

    test('gate: the delegate (the StateNotifier) never rides the tree as an '
        'ambient value', () {
      // Providing the notifier as an InheritedSeed makes its `.state` reachable
      // as a snapshot — the D-H leak. runGrid holds the delegate and drives the
      // config scope BY CONSTRUCTION; only the VALUE (GridConfiguration) is
      // provided ambiently.
      for (final f in _libSources()) {
        expect(
          _code(f.readAsStringSync()),
          isNot(contains('InheritedSeed<GridDelegate>')),
          reason: '${f.path}: the delegate/notifier must not be provided as an '
              'ambient InheritedSeed — its `.state` would be snapshottable (D-H)',
        );
      }
    });

    test('gate: the delegate type is never looked up from the tree (either verb)',
        () {
      // Neither the effect verb (getInheritedSeedOfExactType<GridDelegate>) nor
      // the subscribing verb (dependOnInheritedSeedOfExactType<GridDelegate>)
      // may fetch the delegate — both share this substring. A consumer that
      // reaches the notifier reads `.state` off it synchronously; configuration
      // is observed via GridConfiguration.of, the delegate is never exposed.
      for (final f in _libSources()) {
        expect(
          _code(f.readAsStringSync()),
          isNot(contains('InheritedSeedOfExactType<GridDelegate>')),
          reason: '${f.path}: the delegate is never an ambient tree lookup '
              '(D-H) — observe the configuration value, not the notifier',
        );
      }
    });

    test('gate: the notifier raw state is never re-surfaced synchronously', () {
      // No re-exposed public `state` getter, no `debugState` peek, and no
      // getter/method body that hands back the notifier state directly.
      final banned = <RegExp>[
        RegExp(r'\bdebugState\b'),
        RegExp(r'\bget\s+state\b'),
        RegExp(r'=>\s*state\b'),
        RegExp(r'\breturn\s+state\b'),
      ];
      for (final f in _libSources()) {
        final code = _code(f.readAsStringSync());
        for (final re in banned) {
          expect(
            re.hasMatch(code),
            isFalse,
            reason: '${f.path}: matches /${re.pattern}/ — a StateNotifier\'s '
                'state must not be re-surfaced synchronously (D-H)',
          );
        }
      }
    });

    test('gate: only GridConfiguration.of/maybeOf return the configuration '
        'value (the build-observation reads)', () {
      // Any OTHER public getter/method returning GridConfiguration is a sync
      // accessor over notifier state. `of`/`maybeOf` are the sanctioned
      // observations (they subscribe, valid in build); nothing else may return
      // the state value.
      final getter = RegExp(r'\bGridConfiguration\b\??\s+get\s+(\w+)');
      final method = RegExp(r'\bGridConfiguration\b\??\s+(\w+)\s*\(');
      final returned = <String>{};
      for (final f in _libSources()) {
        final code = _code(f.readAsStringSync());
        for (final m in getter.allMatches(code)) {
          returned.add(m.group(1)!);
        }
        for (final m in method.allMatches(code)) {
          returned.add(m.group(1)!);
        }
      }
      // Non-vacuous: the sanctioned subscribing readers ARE present…
      expect(
        returned,
        containsAll(<String>['of', 'maybeOf']),
        reason: 'the subscribing GridConfiguration.of/maybeOf must be found '
            '(the scan really parses declarations) — vacuousness control',
      );
      // …and they are the ONLY declarations returning the configuration value.
      final extra = returned.difference(<String>{'of', 'maybeOf'});
      expect(
        extra,
        isEmpty,
        reason: 'only GridConfiguration.of/maybeOf (the build-observation reads) '
            'may return the configuration; any other getter/method returning it '
            'is a public sync accessor over notifier state (D-H): $extra',
      );
    });
  });
}
