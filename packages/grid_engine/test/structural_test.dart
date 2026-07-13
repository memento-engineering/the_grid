// Track E/F + Track B — the OPINION-FREE KERNEL invariant (ADR-0007 §1).
//
// The engine holds NO landing / VCS / provider opinion: agents, `claude`, the
// PR opener, the subprocess provider, the git service, the `.land(` call, and
// even `melos` (D-1) live ONLY in the `grid_assets` package — NEVER in the
// engine. The kernel, the effect core, and the core seeds resolve capabilities
// through the opaque SessionResolver / StationServices seams and never name a
// concrete opinion. The opinions used to live in `lib/src/extension/`; with the
// Track B extraction there is no such dir, so the engine must name NONE of the
// opinion literals ANYWHERE in `lib/src`.
//
// This is a structural (grep-the-source) guardrail: it reads every lib/src file
// and fails — naming the offending path — if an opinion literal appears. A
// pure-Dart, offline test (reads files; no live anything). The complementary
// "the opinions DO live somewhere" meaningfulness check is in
// grid_assets/test/structural_test.dart.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The literals that encode a landing / VCS / provider OPINION — none may appear
/// anywhere in the engine's `lib/src`.
const _opinionLiterals = <String>[
  // The coding agent the implement capability spawns.
  'claude',
  // The real PR opener (the land capability's only concrete VCS dep).
  'GhPrOpener',
  // The real process transport impl.
  'SubprocessProvider',
  // The real git worktree/land service.
  'StationGitService',
  // The land orchestration call site.
  '.land(',
  // The test-runner the toy verify shells out to (D-1: the engine names no
  // build-tool opinion either).
  'melos',
  // The git worktree LAYOUT (ADR-0009 EffectContext→StationServices cleanup /
  // ADR-0008 D5): "one git worktree per bead, built from source" is the
  // SourceControl impl's opinion, NOT the engine's — the workspace/branch come
  // from `SourceControl.workspaceFor`/`branchFor`, so the engine names this layout
  // marker nowhere (it used to leak via `EffectContext.worktreeFor`).
  '.grid/worktrees',
  // DELIVERY detail (M5 D-4a): "is landing armed?", "open a PR" and a PR ref are
  // the CODE domain's, not the engine's. The engine knows only "actuate the
  // terminal delivery" (`DeliveryMethod`); commit/push/open-a-PR left
  // `SourceControl` and ship in the asset's bound method.
  'canLand',
  'openPr',
  'PrRef',
];

/// tg-6gn — the ONE ROUTER. A route verdict is effected in exactly ONE engine
/// file: `circuit/capability_host.dart`. If any of these routing-effect call
/// sites appears anywhere else under `lib/src`, a second seam started effecting
/// routing and the "one router, one chokepoint" invariant (A37 / ADR-0009
/// Decision 3's invariant 2) is gone.
const _routingEffectCallSites = <String>[
  'nodeRewoundMetadata(', // the rewind re-key write
  '.createGate(', // the escalate → park effect
  '.deliver(', // the terminal advance's actuation
  '.escalate(', // the escalate → bound handler raise
];

/// The ONE file allowed to EFFECT them (the router).
const _router = 'circuit/capability_host.dart';

/// The DEFINITION sites the fence must not trip on. Only `session_bead.dart`
/// needs the exemption — it DECLARES `nodeRewoundMetadata`. The `DeliveryMethod`
/// / `EscalationHandler` interfaces (and their fakes) declare `deliver`/`escalate`
/// with no leading dot, so they never match a CALL site and are deliberately NOT
/// exempted: the fence stays tight enough to catch a second effector even inside
/// the SDK.
const _routingDefinitionFiles = <String>['domain/session_bead.dart'];

/// The SUPERSEDED tg-b3k workaround (tg-o90): a machine-actionable GATE-REASON
/// STRING convention (`kRespecGatePrefix` / `isRespecGate` / `machineActionableGate`),
/// with `SessionScope` auto-resolving the gate beads it matched. Routing is a
/// first-class `Rewind` VERDICT now — the engine NEVER parses a gate
/// reason, and a gate is always a HUMAN's. If any of these identifiers reappears
/// in the engine, the workaround came back.
const _supersededWorkaroundLiterals = <String>[
  'kRespecGatePrefix',
  'isRespecGate',
  'machineActionableGate',
];

/// Resolves this package's `lib/src` directory, walking up from the test's
/// working dir to find `packages/grid_engine/lib/src` (robust whether the suite
/// runs from the repo root or the package dir).
Directory _libSrc() {
  // Candidate roots: cwd, then cwd/packages/grid_engine, then walk up.
  final candidates = <String>[
    p.join('lib', 'src'),
    p.join('packages', 'grid_engine', 'lib', 'src'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          File(p.join(probe.path, 'kernel', 'station_kernel.dart')).existsSync()) {
        return probe;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate packages/grid_engine/lib/src from ${Directory.current.path}');
}

void main() {
  group('the engine is opinion-free (ADR-0007 §1)', () {
    final libSrc = _libSrc();

    final engineFiles = libSrc
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('the kernel, effect core, and core seeds reference NO opinion literal',
        () {
      expect(
        engineFiles,
        isNotEmpty,
        reason: 'sanity: the engine files were found',
      );
      final offences = <String>[];
      for (final file in engineFiles) {
        final source = file.readAsStringSync();
        for (final literal in _opinionLiterals) {
          if (source.contains(literal)) {
            offences.add(
              '${p.relative(file.path, from: libSrc.path)} references "$literal"',
            );
          }
        }
      }
      expect(
        offences,
        isEmpty,
        reason:
            'opinion literals must live ONLY in grid_assets — the engine holds '
            'no landing/VCS/provider opinion:\n  ${offences.join('\n  ')}',
      );
    });

    test('tg-6gn — the ONE ROUTER: no other lib/src file effects a route '
        'verdict', () {
      final offences = <String>[];
      for (final file in engineFiles) {
        final rel = p
            .relative(file.path, from: libSrc.path)
            .replaceAll(r'\', '/');
        if (rel == _router || _routingDefinitionFiles.contains(rel)) continue;
        final source = file.readAsStringSync();
        for (final site in _routingEffectCallSites) {
          if (source.contains(site)) offences.add('$rel effects "$site"');
        }
      }
      expect(
        offences,
        isEmpty,
        reason:
            'a route verdict is effected in ONE seam — the CapabilityHost — '
            'through the ONE bd chokepoint onto the_grid\'s OWN session bead '
            '(A37 / ADR-0009 invariant 2):\n  ${offences.join('\n  ')}',
      );
    });

    test('tg-6gn — MEANINGFULNESS: the router DOES effect all four (so the '
        'fence above cannot pass vacuously)', () {
      final source = File(
        p.join(libSrc.path, 'circuit', 'capability_host.dart'),
      ).readAsStringSync();
      for (final site in _routingEffectCallSites) {
        expect(
          source.contains(site),
          isTrue,
          reason:
              'the router must still effect "$site" — if it moved, the '
              'one-router fence is watching an empty room',
        );
      }
    });

    test('tg-o90 — the superseded gate-reason-STRING workaround stays dead', () {
      final offences = <String>[];
      for (final file in engineFiles) {
        final source = file.readAsStringSync();
        for (final literal in _supersededWorkaroundLiterals) {
          if (source.contains(literal)) {
            offences.add(
              '${p.relative(file.path, from: libSrc.path)} names "$literal"',
            );
          }
        }
      }
      expect(
        offences,
        isEmpty,
        reason:
            'routing is the first-class `Rewind` verdict (tg-o90) — the '
            'engine never parses a gate REASON, and SessionScope never '
            'auto-resolves a gate bead. The tg-b3k workaround must not come '
            'back:\n  ${offences.join('\n  ')}',
      );
    });

    test('tg-o90 — SessionScope never CLOSES a gate bead (a gate is a HUMAN\'s; '
        'its only gate write is the D-7 gated→pending re-arm)', () {
      final source = File(
        p.join(libSrc.path, 'circuit', 'session_scope.dart'),
      ).readAsStringSync();
      // The scope may close its OWN session (D-2 / breaker escalation / rework);
      // it may never MINT or RESOLVE a gate bead — that is what made the tg-b3k
      // workaround a machine loop wearing a human gate's clothes.
      expect(source.contains('createGate'), isFalse);
      expect(source.contains('closeGate'), isFalse);
      expect(
        source.contains('nodeStateMetadata'),
        isTrue,
        reason: 'sanity (non-vacuous): the D-7 re-arm write is still there',
      );
    });
  });
}
