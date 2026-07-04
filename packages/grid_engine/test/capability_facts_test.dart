// Pure-logic proof of the CAPABILITY MODEL (ADR-0011 D6): per-fact composition
// (scalar override / set union + derived target defaults), CONTAINMENT matching,
// the dynamic toolchain probe (driven by an INJECTED tool query — no real
// toolchain), and TTL re-validation. The headline is the DYNAMIC-SHIFT test:
// a probe loses a capability → re-match flips → the re-validator reports stale.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// A [ToolchainQuery] backed by a static table (exe → `--version` output, or
/// `null` = absent). Fakes, not mocks; no real `Process.run`.
ToolchainQuery _fakeTools(Map<String, String?> table) =>
    (exe) async => table[exe];

void main() {
  group('CapabilityFacts.compose (the cascade math)', () {
    test('scalar facts OVERRIDE — the child (nearer node) wins', () {
      const parent = CapabilityFacts(scalars: {'tier': 'base', 'zone': 'us'});
      const child = CapabilityFacts(scalars: {'tier': 'pro'});
      final c = CapabilityFacts.compose(parent, child);
      expect(c.scalar('tier'), 'pro'); // child overrides
      expect(c.scalar('zone'), 'us'); // parent retained
    });

    test('set facts UNION across parent + child', () {
      const parent = CapabilityFacts(
        sets: {
          kRadio: {'ble'},
          kFlutterTarget: {'linux'},
        },
      );
      const child = CapabilityFacts(
        sets: {
          kRadio: {'wifi'},
          kFlutterTarget: {'android'},
        },
      );
      final c = CapabilityFacts.compose(parent, child);
      expect(c.setOf(kRadio), {'ble', 'wifi'});
      expect(c.setOf(kFlutterTarget), {'linux', 'android'});
    });

    test('is pure — neither input is mutated', () {
      const parent = CapabilityFacts(
        sets: {
          kRadio: {'ble'},
        },
      );
      const child = CapabilityFacts(
        sets: {
          kRadio: {'wifi'},
        },
      );
      CapabilityFacts.compose(parent, child);
      expect(parent.setOf(kRadio), {'ble'});
      expect(child.setOf(kRadio), {'wifi'});
    });
  });

  group('CapabilityFacts.deriveTargets (derived defaults)', () {
    test('flutter-target ⟸ dart-target ⟸ system-os when undeclared', () {
      const f = CapabilityFacts(
        sets: {
          kSystemOs: {'linux'},
        },
      );
      final d = f.deriveTargets();
      expect(d.setOf(kDartTarget), {'linux'}); // derived from system-os
      expect(d.setOf(kFlutterTarget), {'linux'}); // derived down the chain
      expect(f.sets.containsKey(kDartTarget), isFalse); // original untouched
    });

    test('only divergence is restated — a declared target is preserved', () {
      const f = CapabilityFacts(
        sets: {
          kSystemOs: {'macos'},
          kFlutterTarget: {'ios', 'android'},
        },
      );
      final d = f.deriveTargets();
      expect(d.setOf(kDartTarget), {'macos'}); // gap filled
      expect(d.setOf(kFlutterTarget), {'ios', 'android'}); // divergence kept
    });

    test('no broader fact → nothing to derive (fail-open, not invented)', () {
      const f = CapabilityFacts(
        sets: {
          kRadio: {'ble'},
        },
      );
      final d = f.deriveTargets();
      expect(d.sets.containsKey(kSystemOs), isFalse);
      expect(d.sets.containsKey(kDartTarget), isFalse);
      expect(d.sets.containsKey(kFlutterTarget), isFalse);
    });
  });

  group('CapabilityFacts.matches (containment)', () {
    const station = CapabilityFacts(
      scalars: {'tier': 'pro'},
      sets: {
        kSystemOs: {'linux'},
        kFlutterTarget: {'linux', 'android'},
        kRadio: {'ble', 'wifi'},
      },
    );

    test('an empty requirement matches vacuously', () {
      expect(CapabilityFacts.matches(station, const CapabilityFacts()), isTrue);
    });

    test('a required scalar must be present AND equal', () {
      expect(
        CapabilityFacts.matches(
          station,
          const CapabilityFacts(scalars: {'tier': 'pro'}),
        ),
        isTrue,
      );
      expect(
        CapabilityFacts.matches(
          station,
          const CapabilityFacts(scalars: {'tier': 'enterprise'}),
        ),
        isFalse,
      );
    });

    test('a required set must be a SUBSET of the station set', () {
      expect(
        CapabilityFacts.matches(
          station,
          const CapabilityFacts(
            sets: {
              kFlutterTarget: {'android'},
            },
          ),
        ),
        isTrue,
      );
      // android+ios — ios is not offered → not contained.
      expect(
        CapabilityFacts.matches(
          station,
          const CapabilityFacts(
            sets: {
              kFlutterTarget: {'android', 'ios'},
            },
          ),
        ),
        isFalse,
      );
    });

    test('fail-closed: a required fact the station does not declare → no '
        'match', () {
      expect(
        CapabilityFacts.matches(
          station,
          const CapabilityFacts(scalars: {'unknown': 'x'}),
        ),
        isFalse,
      );
      expect(
        CapabilityFacts.matches(
          station,
          const CapabilityFacts(
            sets: {
              'gpu': {'cuda'},
            },
          ),
        ),
        isFalse,
      );
    });

    test('an empty required set demands nothing (matches)', () {
      expect(
        CapabilityFacts.matches(
          station,
          const CapabilityFacts(sets: {'gpu': {}}),
        ),
        isTrue,
      );
    });

    test('the burn-follower profile matches a linux/ble peer', () {
      const follower = CapabilityFacts(
        sets: {
          kSystemOs: {'linux'},
          kFlutterTarget: {'linux'},
          kRadio: {'ble'},
        },
      );
      expect(CapabilityFacts.matches(station, follower), isTrue);
      // ...but a macos requirement does not.
      expect(
        CapabilityFacts.matches(
          station,
          const CapabilityFacts(
            sets: {
              kSystemOs: {'macos'},
            },
          ),
        ),
        isFalse,
      );
    });

    test('matches RAW facts — an absent toolchain is NOT back-filled by '
        'derivation', () {
      // A station with dart but no flutter (no flutter-target key).
      const dartOnly = CapabilityFacts(
        sets: {
          kSystemOs: {'linux'},
          kDartTarget: {'linux'},
        },
      );
      const wantFlutter = CapabilityFacts(
        sets: {
          kFlutterTarget: {'linux'},
        },
      );
      // Raw match fails (correct — it cannot build flutter)...
      expect(CapabilityFacts.matches(dartOnly, wantFlutter), isFalse);
      // ...even though derivation WOULD invent a flutter-target.
      expect(
        CapabilityFacts.matches(dartOnly.deriveTargets(), wantFlutter),
        isTrue,
      );
    });
  });

  group('CapabilityFacts wire profile + value semantics', () {
    test('toProfile/fromProfile round-trips (sets as lists)', () {
      const f = CapabilityFacts(
        scalars: {'tier': 'pro'},
        sets: {
          kSystemOs: {'linux'},
          kFlutterTarget: {'android', 'linux'},
        },
      );
      expect(CapabilityFacts.fromProfile(f.toProfile()), f);
    });

    test('fromProfile tolerates the legacy bare-string set form', () {
      // {'system-os': 'linux'} (a string for a known set key) → a singleton set.
      final f = CapabilityFacts.fromProfile(const {
        kSystemOs: 'linux',
        'tier': 'pro',
      });
      expect(f.setOf(kSystemOs), {'linux'});
      expect(f.scalar('tier'), 'pro');
    });

    test('value equality + hashCode are deep + order-independent', () {
      const a = CapabilityFacts(
        scalars: {'tier': 'pro'},
        sets: {
          kRadio: {'ble', 'wifi'},
        },
      );
      const b = CapabilityFacts(
        scalars: {'tier': 'pro'},
        sets: {
          kRadio: {'wifi', 'ble'}, // different iteration order
        },
      );
      const c = CapabilityFacts(
        scalars: {'tier': 'pro'},
        sets: {
          kRadio: {'ble'},
        },
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('ToolchainProbe (injected query — offline, deterministic)', () {
    test('emits system-os from the host + host-default dart/flutter targets',
        () async {
      final probe = ToolchainProbe(
        os: 'linux',
        query: _fakeTools({
          'dart': 'Dart SDK version: 3.11.0 (stable) on "linux_x64"',
          'flutter': 'Flutter 3.24.0 • channel stable',
        }),
      );
      final f = await probe.probe();
      expect(f.setOf(kSystemOs), {'linux'});
      expect(f.setOf(kDartTarget), {'linux'}); // parsed from the version tag
      expect(f.setOf(kFlutterTarget), {'linux'});
    });

    test('an absent toolchain emits NO target fact (fail-closed)', () async {
      final probe = ToolchainProbe(
        os: 'macos',
        query: _fakeTools({
          'dart': 'Dart SDK version: 3.11.0 (stable) on "macos_arm64"',
          // flutter absent
        }),
      );
      final f = await probe.probe();
      expect(f.setOf(kDartTarget), {'macos'});
      expect(f.sets.containsKey(kFlutterTarget), isFalse);
      // ...so it cannot match a flutter requirement.
      expect(
        CapabilityFacts.matches(
          f,
          const CapabilityFacts(
            sets: {
              kFlutterTarget: {'macos'},
            },
          ),
        ),
        isFalse,
      );
    });

    test('dart-target falls back to the host OS when the tag is unparseable',
        () async {
      final probe = ToolchainProbe(
        os: 'linux',
        query: _fakeTools({'dart': 'some unparseable version banner'}),
      );
      final f = await probe.probe();
      expect(f.setOf(kDartTarget), {'linux'});
    });
  });

  group('parseToolchainOs', () {
    test('extracts a recognized OS token from the platform tag', () {
      expect(parseToolchainOs('... on "macos_arm64"'), 'macos');
      expect(parseToolchainOs('... on "linux_x64"'), 'linux');
    });

    test('returns null for an unrecognized / missing tag', () {
      expect(parseToolchainOs('no platform tag here'), isNull);
      expect(parseToolchainOs('on "plan9_pdp11"'), isNull);
    });
  });

  group('CapabilityRevalidator (TTL renewal, depth #2)', () {
    test('not stale while the held requirements still match', () async {
      final probe = FakeProbe(
        const CapabilityFacts(
          sets: {
            kSystemOs: {'linux'},
            kFlutterTarget: {'linux', 'android'},
          },
        ),
      );
      final r = await CapabilityRevalidator(probe).revalidate(
        const CapabilityFacts(
          sets: {
            kFlutterTarget: {'android'},
          },
        ),
      );
      expect(r.stale, isFalse);
    });

    test('DYNAMIC SHIFT: a probe loses a capability → re-match flips → the '
        're-validator reports STALE', () async {
      // A lease was granted requiring a flutter android-build capability.
      const requires = CapabilityFacts(
        sets: {
          kFlutterTarget: {'android'},
        },
      );
      final probe = FakeProbe(
        const CapabilityFacts(
          sets: {
            kSystemOs: {'linux'},
            kFlutterTarget: {'linux', 'android'},
          },
        ),
      );
      final revalidator = CapabilityRevalidator(probe);

      // Initially the station satisfies the lease → not stale.
      expect(CapabilityFacts.matches(await probe.probe(), requires), isTrue);
      expect((await revalidator.revalidate(requires)).stale, isFalse);

      // The configuration SHIFTS — the android target is dropped.
      probe.facts = const CapabilityFacts(
        sets: {
          kSystemOs: {'linux'},
          kFlutterTarget: {'linux'},
        },
      );

      // Re-match flips...
      expect(CapabilityFacts.matches(await probe.probe(), requires), isFalse);
      // ...and at the next TTL renewal the re-validation DECISION is stale:
      // the consumer lapses the lease + re-places the order on another match.
      final after = await revalidator.revalidate(requires);
      expect(after.stale, isTrue);
      expect(after.currentFacts.setOf(kFlutterTarget), {'linux'});
    });
  });
}
