// The core lease family (ADR-0009 D6 / "leasing is core") — LeaseAllocation<H>
// driven directly with a fake LeaseCapability over an OPAQUE handle (H = String).
// PURE (no tree, no transport): proves the transport-agnostic orchestration —
// acquire/dispatch, daemon `ready` (the reap fix) vs job `complete`, adopt-or-
// reacquire (no-adopt-on-faith), dispose=release, detach=keep, and the two
// cancel-race release paths. Zero I/O.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart'
    show FakeRuntimeProvider, FakeTreeContext, stepArgs;
import 'package:test/test.dart';

/// A programmable core lease capability over an opaque String handle (a lease
/// id). Records releases + the hook call-log; never touches a transport.
class _FakeLeaseCap extends LeaseCapability<String> {
  _FakeLeaseCap({
    this.unavailable,
    this.outcome = const Ok({'endpoint': 'vm://x', 'station': 'peer'}),
    this.prior,
    this.fresh = true,
    this.onProveFresh,
    this.releaseThrows = false,
    List<String>? log,
  }) : log = log ?? [];

  final String? unavailable;
  final StepOutcome outcome;
  final LeaseBound<String>? prior;
  final bool fresh;
  final void Function()? onProveFresh;
  final bool releaseThrows;
  final List<String> log;

  int _seq = 0;
  final List<String> released = [];

  /// Mints a handle as [acquire] would (to seed a prior/adopt handle).
  String mint() => 'lease-${_seq++}';

  @override
  Future<LeaseResolution<String>> acquire(
    TreeContext context,
    StepArgs args,
  ) async {
    log.add('acquire');
    if (unavailable != null) return LeaseUnavailable(unavailable!);
    return LeaseBound(mint());
  }

  @override
  Future<StepOutcome> dispatchOn(
    String handle,
    TreeContext context,
    StepArgs args,
  ) async {
    log.add('dispatch:$handle');
    return outcome;
  }

  @override
  Future<bool> proveFresh(
    String handle,
    TreeContext context,
    StepArgs args,
  ) async {
    log.add('proveFresh:$handle');
    onProveFresh?.call();
    return fresh;
  }

  @override
  Future<void> release(String handle) async {
    released.add(handle);
    log.add('release:$handle');
    if (releaseThrows) throw StateError('already reaped');
  }

  @override
  Future<LeaseBound<String>?> adoptable(
    TreeContext context,
    StepArgs args,
  ) async {
    log.add('adoptable');
    return prior;
  }

  bool releasedAny() => released.isNotEmpty;
}

LeaseAllocation<String> _alloc(
  _FakeLeaseCap cap, {
  required AllocationSink sink,
  CancelToken? cancel,
  StepKind kind = StepKind.daemon,
}) => cap.createAllocation(
  AllocationContext(
    treeContext: FakeTreeContext(),
    args: stepArgs('tg-1/lease', cancel: cancel),
    transport: FakeRuntimeProvider(),
    address: const AllocationAddress('tgdog-s', 'tg-1/lease'),
    env: const {},
    sink: sink,
    kind: kind,
  ),
) as LeaseAllocation<String>;

void main() {
  group('LeaseAllocation — kind drives adoptability/detachability (D6)', () {
    test('a daemon lease is adoptable + detachable; a job lease is neither', () {
      final daemon = _alloc(_FakeLeaseCap(), sink: (_) {});
      final job = _alloc(_FakeLeaseCap(), sink: (_) {}, kind: StepKind.job);
      expect(daemon.isAdoptable, isTrue);
      expect(daemon.isDetachable, isTrue);
      expect(job.isAdoptable, isFalse);
      expect(job.isDetachable, isFalse);
    });
  });

  group('LeaseAllocation — daemon: acquire → dispatch → READY (the reap fix)', () {
    test('reports exactly one AllocationReady with the rendezvous payload, and '
        'NEVER AllocationCompleted (stays live, D6/OQ-5)', () async {
      final reports = <AllocationReport>[];
      final cap = _FakeLeaseCap();
      final alloc = _alloc(cap, sink: reports.add);
      await alloc.startOrAdopt();
      final readies = reports.whereType<AllocationReady>().toList();
      expect(readies, hasLength(1));
      expect(readies.single.payload, {'endpoint': 'vm://x', 'station': 'peer'});
      expect(reports.whereType<AllocationCompleted>(), isEmpty);
      expect(alloc.state, AllocationState.ready);
      // A daemon consults adoptable first (null here → no adopt), then acquires.
      expect(cap.log, ['adoptable', 'acquire', 'dispatch:lease-0']);
    });

    test('dispose RELEASES the held handle (dispose == release, the floor)',
        () async {
      final cap = _FakeLeaseCap();
      final alloc = _alloc(cap, sink: (_) {});
      await alloc.startOrAdopt();
      await alloc.dispose();
      expect(cap.released, ['lease-0']);
      expect(alloc.state, AllocationState.gone);
    });
  });

  group('LeaseAllocation — job: acquire → dispatch → COMPLETE (latches)', () {
    test('a job lease reports AllocationCompleted (not ready); dispose releases',
        () async {
      final reports = <AllocationReport>[];
      final cap = _FakeLeaseCap(outcome: const Ok({'exitCode': '0'}));
      final alloc = _alloc(cap, sink: reports.add, kind: StepKind.job);
      await alloc.startOrAdopt();
      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
      expect(reports.whereType<AllocationReady>(), isEmpty);
      await alloc.dispose();
      expect(cap.released, ['lease-0']);
    });

    test('a double dispose releases ONCE (idempotent)', () async {
      final cap = _FakeLeaseCap();
      final alloc = _alloc(cap, sink: (_) {}, kind: StepKind.job);
      await alloc.startOrAdopt();
      await alloc.dispose();
      await alloc.dispose();
      expect(cap.released, ['lease-0']);
    });
  });

  group('LeaseAllocation — dispatch outcomes route to reports', () {
    test('Failed dispatch → AllocationFailed (still releases on dispose)',
        () async {
      final reports = <AllocationReport>[];
      final cap = _FakeLeaseCap(outcome: const Failed('boom'));
      final alloc = _alloc(cap, sink: reports.add);
      await alloc.startOrAdopt();
      expect((reports.single as AllocationFailed).reason, 'boom');
      await alloc.dispose();
      expect(cap.releasedAny(), isTrue);
    });

    test('Gate dispatch → AllocationGated', () async {
      final reports = <AllocationReport>[];
      final cap = _FakeLeaseCap(outcome: const Gate('needs a human'));
      final alloc = _alloc(cap, sink: reports.add);
      await alloc.startOrAdopt();
      expect((reports.single as AllocationGated).reason, 'needs a human');
    });
  });

  group('LeaseAllocation — acquire fail-closed', () {
    test('LeaseUnavailable → AllocationFailed; nothing bound; dispose no-release',
        () async {
      final reports = <AllocationReport>[];
      final cap = _FakeLeaseCap(unavailable: 'no peer satisfies X');
      final alloc = _alloc(cap, sink: reports.add);
      await alloc.startOrAdopt();
      expect((reports.single as AllocationFailed).reason, 'no peer satisfies X');
      expect(cap.log, isNot(contains('dispatch')));
      expect(alloc.handle, isNull);
      await alloc.dispose();
      expect(cap.releasedAny(), isFalse);
    });
  });

  group('LeaseAllocation — a dispose racing the acquire releases the slot', () {
    test('cancel before startOrAdopt (job) → binds then RELEASES + skips dispatch '
        '+ no report', () async {
      final reports = <AllocationReport>[];
      final cap = _FakeLeaseCap();
      final alloc = _alloc(
        cap,
        sink: reports.add,
        cancel: CancelToken()..cancel(),
        kind: StepKind.job,
      );
      await alloc.startOrAdopt();
      expect(cap.log, isNot(contains('dispatch')));
      expect(cap.releasedAny(), isTrue);
      expect(reports, isEmpty);
      expect(alloc.state, AllocationState.gone);
    });
  });

  group('LeaseAllocation — daemon adopt-or-reacquire (no-adopt-on-faith)', () {
    test('a prior handle PROVEN fresh is ADOPTED — reattached, ready, NO acquire/'
        'dispatch; dispose releases it', () async {
      final reports = <AllocationReport>[];
      final cap = _FakeLeaseCap(prior: LeaseBound('prior-0'), fresh: true);
      final alloc = _alloc(cap, sink: reports.add);
      await alloc.startOrAdopt();
      expect(alloc.adopted, isTrue);
      expect(cap.log, isNot(contains('acquire')));
      expect(cap.log, isNot(contains('dispatch')));
      expect(cap.log, contains('proveFresh:prior-0'));
      expect(reports.whereType<AllocationReady>(), hasLength(1));
      expect(alloc.handle, 'prior-0');
      await alloc.dispose();
      expect(cap.released, ['prior-0']);
    });

    test('a prior handle that FAILS the proof → acquire FRESH (never adopt blind)',
        () async {
      final cap = _FakeLeaseCap(prior: LeaseBound('stale-0'), fresh: false);
      final alloc = _alloc(cap, sink: (_) {});
      await alloc.startOrAdopt();
      expect(alloc.adopted, isFalse);
      expect(cap.log, contains('acquire'));
      expect(cap.log, contains('dispatch:lease-0'));
      expect(alloc.handle, 'lease-0');
    });

    test('a dispose racing the adopt PROOF releases the prior handle (invariant 4)',
        () async {
      final cancel = CancelToken();
      final cap = _FakeLeaseCap(
        prior: LeaseBound('prior-0'),
        fresh: true,
        onProveFresh: cancel.cancel, // dispose lands inside proveFresh's await
      );
      final alloc = _alloc(cap, sink: (_) {}, cancel: cancel);
      await alloc.startOrAdopt();
      expect(alloc.adopted, isFalse);
      expect(cap.log, contains('proveFresh:prior-0'));
      expect(cap.released, contains('prior-0'),
          reason: 'the proven prior handle is released, not orphaned');
      await alloc.dispose();
      expect(cap.released, ['prior-0'], reason: 'no double release');
    });

    test('a JOB never adopts even with a fresh prior (respawn-or-skip)', () async {
      final cap = _FakeLeaseCap(prior: LeaseBound('prior-0'), fresh: true);
      final alloc = _alloc(cap, sink: (_) {}, kind: StepKind.job);
      await alloc.startOrAdopt();
      expect(alloc.adopted, isFalse);
      expect(cap.log, isNot(contains('adoptable')));
      expect(cap.log, contains('acquire'));
    });
  });

  group('LeaseAllocation — detach vs dispose (distinct verbs, D4)', () {
    test('detach LEAVES the daemon lease HELD (never releases); a later dispose '
        'still releases', () async {
      final cap = _FakeLeaseCap();
      final alloc = _alloc(cap, sink: (_) {});
      await alloc.startOrAdopt();
      await alloc.detach();
      expect(cap.releasedAny(), isFalse);
      await alloc.dispose();
      expect(cap.released, ['lease-0']);
    });

    test('detach on a JOB lease throws (never leave a grant held)', () async {
      final cap = _FakeLeaseCap();
      final alloc = _alloc(cap, sink: (_) {}, kind: StepKind.job);
      await alloc.startOrAdopt();
      await expectLater(alloc.detach(), throwsA(isA<UnsupportedError>()));
    });
  });

  group('LeaseAllocation — release stays idempotent for the holder', () {
    test('dispose swallows a throwing release (already reaped)', () async {
      final cap = _FakeLeaseCap(releaseThrows: true);
      final alloc = _alloc(cap, sink: (_) {});
      await alloc.startOrAdopt();
      await alloc.dispose(); // must not throw
      expect(cap.releasedAny(), isTrue);
    });
  });
}
