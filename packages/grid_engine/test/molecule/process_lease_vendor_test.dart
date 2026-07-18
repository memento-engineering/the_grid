// R3 — ProcessLeaseVendor: leased process identity (DESIGN-tg-pm6.md §7,
// Decided item 5).
//
// Three layers, offline, Fakes-not-mocks throughout:
//  - requireProcessLeaseVendor: the LOUD-or-GONE seam-level assertion, proven
//    via FakeTreeContext (mirrors inherited_circuit_test.dart's wiring test).
//  - the lease breadcrumb codec (leaseBreadcrumb/leaseBreadcrumbOf/
//    kClearedLeaseKeys): pure round-trip + malformed-input tests, mirroring
//    molecule_codec_test.dart's style.
//  - StationProcessLeaseVendor / SelfManagedProcessVendor driven through the
//    UNCHANGED LeaseAllocation<ProcessHandle> (sdk/lease.dart), exactly the
//    _alloc/_FakeLeaseCap pattern lease_allocation_test.dart already
//    establishes — proving daemon adopt-on-proveFresh-true with no re-spawn,
//    a job never adopting, and release clearing the breadcrumb.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  group('requireProcessLeaseVendor — LOUD-or-GONE (item 5)', () {
    test('throws when no ProcessLeaseVendor is mounted ambient', () {
      final ctx = FakeTreeContext();
      expect(
        () => requireProcessLeaseVendor(ctx),
        throwsA(isA<StateError>()),
      );
    });

    test('resolves the mounted vendor via the TREE verb (dependOn…), never '
        'throwing', () {
      const vendor = SelfManagedProcessVendor(
        spawn: _neverSpawn,
        dispatch: _neverDispatch,
      );
      final ctx = FakeTreeContext()..provide<ProcessLeaseVendor>(vendor);
      expect(requireProcessLeaseVendor(ctx), same(vendor));
    });
  });

  group('lease breadcrumb codec — leaseBreadcrumb / leaseBreadcrumbOf', () {
    const handle = ProcessHandle(pgid: 4242, pid: 4343, token: 'tok-abc');

    test('round-trips a full handle through the metadata map', () {
      expect(leaseBreadcrumbOf(leaseBreadcrumb(handle)), handle);
    });

    test('a missing pgid/pid/token key is not a handle', () {
      final full = leaseBreadcrumb(handle);
      for (final key in [LeaseKeys.pgid, LeaseKeys.pid, LeaseKeys.token]) {
        final partial = {...full}..remove(key);
        expect(
          leaseBreadcrumbOf(partial),
          isNull,
          reason: 'missing $key must not parse',
        );
      }
    });

    test('an unparsable pgid/pid is not a handle', () {
      final full = leaseBreadcrumb(handle);
      expect(
        leaseBreadcrumbOf({...full, LeaseKeys.pgid: 'not-a-number'}),
        isNull,
      );
      expect(
        leaseBreadcrumbOf({...full, LeaseKeys.pid: 'not-a-number'}),
        isNull,
      );
    });

    test('kClearedLeaseKeys never round-trips back into a handle — the '
        'blank sentinel reads exactly like absent', () {
      expect(leaseBreadcrumbOf(kClearedLeaseKeys), isNull);
    });

    test('empty metadata is not a handle', () {
      expect(leaseBreadcrumbOf(const {}), isNull);
    });

    test('structural — the breadcrumb never touches a key outside '
        'LeaseKeys.prefix', () {
      for (final key in leaseBreadcrumb(handle).keys) {
        expect(key.startsWith(LeaseKeys.prefix), isTrue, reason: key);
      }
      for (final key in kClearedLeaseKeys.keys) {
        expect(key.startsWith(LeaseKeys.prefix), isTrue, reason: key);
      }
    });
  });

  group(
    'StationProcessLeaseVendor — daemon adopt-or-reacquire (mirrors '
    'LeaseAllocation, D4/D5)',
    () {
      test(
        'a prior breadcrumb PROVEN fresh is ADOPTED — no spawn, no '
        'breadcrumb rewrite (no-adopt-on-faith honored, no re-persist)',
        () async {
          final fakes = buildFakes();
          final log = <String>[];
          const prior = ProcessHandle(pgid: 111, pid: 222, token: 'tok-0');

          final vendor = StationProcessLeaseVendor(
            writer: fakes.ctx.writer,
            spawn: (context, args) async {
              log.add('spawn');
              return const ProcessHandle(pgid: 999, pid: 998, token: 'fresh');
            },
            dispatch: (handle, context, args) async {
              log.add('dispatch:${handle.token}');
              return const Ok({'endpoint': 'vm://x'});
            },
            metadataOf: (stepBeadId) async {
              log.add('metadataOf:$stepBeadId');
              return leaseBreadcrumb(prior);
            },
            liveness: (fence) {
              log.add('liveness:${fence.pgid}');
              return true;
            },
          );

          final reports = <AllocationReport>[];
          final alloc = _alloc(
            vendor.leaseFor('tgdog-step-1', stepArgs('tg-1/lease')),
            sink: reports.add,
          );
          await alloc.startOrAdopt();

          expect(alloc.adopted, isTrue);
          expect(alloc.handle, prior);
          expect(log, ['metadataOf:tgdog-step-1', 'liveness:111']);
          expect(
            fakes.runner.callsFor('update'),
            isEmpty,
            reason: 'adopt reattaches — it never re-persists the breadcrumb',
          );
          expect(reports.whereType<AllocationReady>(), hasLength(1));
        },
      );

      test(
        'no prior breadcrumb — spawns fresh and writes it exactly once',
        () async {
          final fakes = buildFakes();
          final log = <String>[];
          const fresh = ProcessHandle(pgid: 55, pid: 66, token: 'tok-fresh');

          final vendor = StationProcessLeaseVendor(
            writer: fakes.ctx.writer,
            spawn: (context, args) async {
              log.add('spawn');
              return fresh;
            },
            dispatch: (handle, context, args) async {
              log.add('dispatch:${handle.token}');
              return const Ok({'endpoint': 'vm://x'});
            },
            metadataOf: (stepBeadId) async {
              log.add('metadataOf:$stepBeadId');
              return null;
            },
            liveness: (fence) {
              log.add('liveness');
              return true;
            },
          );

          final reports = <AllocationReport>[];
          final alloc = _alloc(
            vendor.leaseFor('tgdog-step-1', stepArgs('tg-1/lease')),
            sink: reports.add,
          );
          await alloc.startOrAdopt();

          expect(alloc.adopted, isFalse);
          expect(alloc.handle, fresh);
          expect(log, ['metadataOf:tgdog-step-1', 'spawn', 'dispatch:tok-fresh']);
          final updates = fakes.runner.callsFor('update');
          expect(updates, hasLength(1));
          expect(fakes.runner.metadataOfUpdate(0), leaseBreadcrumb(fresh));
          expect(reports.whereType<AllocationReady>(), hasLength(1));
        },
      );

      test(
        'a prior breadcrumb that FAILS the liveness proof — acquires fresh '
        '(never adopt blind)',
        () async {
          final fakes = buildFakes();
          const prior = ProcessHandle(pgid: 1, pid: 2, token: 'stale');
          const fresh = ProcessHandle(pgid: 3, pid: 4, token: 'new');
          final vendor = StationProcessLeaseVendor(
            writer: fakes.ctx.writer,
            spawn: (context, args) async => fresh,
            dispatch: (handle, context, args) async => const Ok({}),
            metadataOf: (stepBeadId) async => leaseBreadcrumb(prior),
            liveness: (fence) => false,
          );

          final alloc = _alloc(
            vendor.leaseFor('tgdog-step-1', stepArgs('tg-1/lease')),
            sink: (_) {},
          );
          await alloc.startOrAdopt();

          expect(alloc.adopted, isFalse);
          expect(alloc.handle, fresh);
          expect(fakes.runner.callsFor('update'), hasLength(1));
        },
      );

      test(
        'a partial/malformed prior breadcrumb is not adoptable — acquires '
        'fresh',
        () async {
          final fakes = buildFakes();
          const fresh = ProcessHandle(pgid: 3, pid: 4, token: 'new');
          final vendor = StationProcessLeaseVendor(
            writer: fakes.ctx.writer,
            spawn: (context, args) async => fresh,
            dispatch: (handle, context, args) async => const Ok({}),
            // Missing the token key entirely — leaseBreadcrumbOf must refuse.
            metadataOf: (stepBeadId) async => {
              LeaseKeys.pgid: '1',
              LeaseKeys.pid: '2',
            },
            liveness: (fence) => true,
          );

          final alloc = _alloc(
            vendor.leaseFor('tgdog-step-1', stepArgs('tg-1/lease')),
            sink: (_) {},
          );
          await alloc.startOrAdopt();

          expect(alloc.adopted, isFalse);
          expect(alloc.handle, fresh);
        },
      );
    },
  );

  group('StationProcessLeaseVendor — a job never adopts (D6)', () {
    test(
      'a job with a fresh, live prior breadcrumb still respawns (adoptable '
      'is never even consulted for a job)',
      () async {
        final fakes = buildFakes();
        final log = <String>[];
        const prior = ProcessHandle(pgid: 111, pid: 222, token: 'tok-0');
        const fresh = ProcessHandle(pgid: 999, pid: 998, token: 'fresh');

        final vendor = StationProcessLeaseVendor(
          writer: fakes.ctx.writer,
          spawn: (context, args) async {
            log.add('spawn');
            return fresh;
          },
          dispatch: (handle, context, args) async {
            log.add('dispatch');
            return const Ok({});
          },
          metadataOf: (stepBeadId) async {
            log.add('metadataOf');
            return leaseBreadcrumb(prior);
          },
          liveness: (fence) {
            log.add('liveness');
            return true;
          },
        );

        final reports = <AllocationReport>[];
        final alloc = _alloc(
          vendor.leaseFor('tgdog-step-1', stepArgs('tg-1/lease')),
          sink: reports.add,
          kind: StepKind.job,
        );
        await alloc.startOrAdopt();

        expect(alloc.adopted, isFalse);
        expect(log, ['spawn', 'dispatch']);
        expect(fakes.runner.callsFor('update'), hasLength(1));
        expect(reports.whereType<AllocationCompleted>(), hasLength(1));
      },
    );
  });

  group('StationProcessLeaseVendor — release clears the breadcrumb', () {
    test('dispose releases — the writer records the cleared payload', () async {
      final fakes = buildFakes();
      const fresh = ProcessHandle(pgid: 7, pid: 8, token: 'tok-7');
      final vendor = StationProcessLeaseVendor(
        writer: fakes.ctx.writer,
        spawn: (context, args) async => fresh,
        dispatch: (handle, context, args) async => const Ok({}),
        metadataOf: (stepBeadId) async => null,
        liveness: (fence) => false,
      );

      final alloc = _alloc(
        vendor.leaseFor('tgdog-step-1', stepArgs('tg-1/lease')),
        sink: (_) {},
      );
      await alloc.startOrAdopt();
      await alloc.dispose();

      final updates = fakes.runner.callsFor('update');
      expect(updates, hasLength(2), reason: 'acquire writes, dispose releases');
      expect(fakes.runner.metadataOfUpdate(0), leaseBreadcrumb(fresh));
      expect(fakes.runner.metadataOfUpdate(1), kClearedLeaseKeys);
    });

    test('release is idempotent for the holder — calling it twice writes '
        'the SAME cleared payload both times, never throws', () async {
      final fakes = buildFakes();
      const fresh = ProcessHandle(pgid: 7, pid: 8, token: 'tok-7');
      final vendor = StationProcessLeaseVendor(
        writer: fakes.ctx.writer,
        spawn: (context, args) async => fresh,
        dispatch: (handle, context, args) async => const Ok({}),
        metadataOf: (stepBeadId) async => null,
        liveness: (fence) => false,
      );
      final cap = vendor.leaseFor('tgdog-step-1', stepArgs('tg-1/lease'));

      await cap.release(fresh);
      await cap.release(fresh);

      final updates = fakes.runner.callsFor('update');
      expect(updates, hasLength(2));
      expect(fakes.runner.metadataOfUpdate(0), kClearedLeaseKeys);
      expect(fakes.runner.metadataOfUpdate(1), kClearedLeaseKeys);
    });
  });

  group('SelfManagedProcessVendor — the explicit degraded mode (item 5)', () {
    test(
      'a daemon never adopts — no durable identity exists to check, so it '
      'always spawns fresh',
      () async {
        final log = <String>[];
        final vendor = SelfManagedProcessVendor(
          spawn: (context, args) async {
            log.add('spawn');
            return const ProcessHandle(pgid: 1, pid: 2, token: 't');
          },
          dispatch: (handle, context, args) async {
            log.add('dispatch');
            return const Ok({});
          },
        );

        final reports = <AllocationReport>[];
        final alloc = _alloc(
          vendor.leaseFor('tgdog-step-3', stepArgs('tg-1/lease')),
          sink: reports.add,
        );
        await alloc.startOrAdopt();

        expect(alloc.adopted, isFalse);
        expect(log, ['spawn', 'dispatch']);
        expect(reports.whereType<AllocationReady>(), hasLength(1));
      },
    );

    test('release is a safe no-op — nothing was ever persisted to clear', () async {
      final vendor = SelfManagedProcessVendor(
        spawn: (context, args) async => const ProcessHandle(pgid: 1, pid: 2, token: 't'),
        dispatch: (handle, context, args) async => const Ok({}),
      );
      final alloc = _alloc(
        vendor.leaseFor('tgdog-step-3', stepArgs('tg-1/lease')),
        sink: (_) {},
      );
      await alloc.startOrAdopt();
      await alloc.dispose(); // must not throw
      expect(alloc.state, AllocationState.gone);
    });
  });
}

Future<ProcessHandle> _neverSpawn(TreeContext context, StepArgs args) =>
    Future.error(StateError('spawn must not be called'));

Future<StepOutcome> _neverDispatch(
  ProcessHandle handle,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('dispatch must not be called'));

/// Builds a [LeaseAllocation<ProcessHandle>] over [cap] — the same bare-drive
/// harness `lease_allocation_test.dart`'s own `_alloc` uses.
LeaseAllocation<ProcessHandle> _alloc(
  LeaseCapability<ProcessHandle> cap, {
  required AllocationSink sink,
  StepKind kind = StepKind.daemon,
}) => cap.createAllocation(
  AllocationContext(
    treeContext: FakeTreeContext(),
    args: stepArgs('tg-1/lease'),
    transport: FakeRuntimeProvider(),
    address: const AllocationAddress('tgdog-s', 'tg-1/lease'),
    env: const {},
    sink: sink,
    kind: kind,
  ),
) as LeaseAllocation<ProcessHandle>;
