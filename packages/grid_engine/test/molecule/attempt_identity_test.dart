// W2 — ATTEMPT IDENTITY (stage1-wiring §2.1): attempt_id gets a durable
// carrier, and the three identity rules that follow from it.
//
// The binding property under test is RECOVERABILITY: the trajectory recorder
// holds no identity that is not rebuildable from the `grid.lease.*`
// breadcrumbs plus the log. Nothing here appends anything — Stage 1's recorder
// is W3 — so every test drives the CARRIER and the RULES:
//
//   1. FRESH SPAWN MINTS — the host mints an attempt id per mount, exports it
//      as `GRID_ATTEMPT_ID`, the spawner stamps it onto the [ProcessHandle],
//      and the lease vendor persists it on the breadcrumb.
//   2. ADOPT CONTINUES — an adopting mount reads the breadcrumb's attempt id
//      back and reuses it; NO fresh mint, no breadcrumb rewrite. One process
//      incarnation keeps one attempt across boots.
//   3. RECONCILER RECOVERS — a bounce settles a prior boot's session by the
//      breadcrumb's attempt id where present; a pre-Stage-1 session (no key at
//      all) gets a reconciler-minted id, marked so a shadow-diff can tell the
//      two apart.
//
// Plus the tolerance property every one of them leans on: a breadcrumb written
// BEFORE Stage 1 still parses and still adopts. Adoption never regresses on a
// trajectory field.
//
// Offline throughout — Fakes, not mocks; the composition-tier tests drive the
// REAL StationProcessLeaseVendor over the REAL stationProcessSpawner against a
// FakeRuntimeProvider and a StationBeadWriter over a recording BdRunner.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _name = 'tgdog-s/tg-1/lease';
const _stepBeadId = 'tgdog-step-attempt';
const _attempt = '01JQZ0000000000000ATTEMPT1';

void _ignoreReport(AllocationReport report) {}

/// A one-shot lane whose spawn config carries no env of its own — so the only
/// `GRID_ATTEMPT_ID` in the child config is the one the ALLOCATION env layered.
class _JobCap extends ProcessCapability {
  const _JobCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(
        workDir: '/tmp/tg-1',
        command: 'sh',
        args: ['-c', 'true'],
        lifecycle: Lifecycle.oneTurn,
      );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>> result(
    TreeContext context,
    StepArgs args,
  ) async => const {'rc': '0'};
}

/// The LITERAL request, with the host's env block reproduced verbatim — the
/// token and the attempt id side by side, which is the layering the design
/// pins (`GRID_INSTANCE_TOKEN` is NOT displaced at Stage 1).
ProcessLeaseRequest _request({
  required FakeRuntimeProvider transport,
  required StepArgs args,
  String attemptId = _attempt,
  AllocationSink sink = _ignoreReport,
  StepKind kind = StepKind.job,
}) => ProcessLeaseRequest(
  stepBeadId: _stepBeadId,
  capability: const _JobCap(),
  allocation: AllocationContext(
    treeContext: FakeTreeContext(),
    args: args,
    transport: transport,
    address: const AllocationAddress('tgdog-s', 'tg-1/lease'),
    env: {
      'GRID_INSTANCE_TOKEN': 'tok-attempt',
      if (attemptId.isNotEmpty) 'GRID_ATTEMPT_ID': attemptId,
    },
    sink: sink,
    kind: kind,
  ),
);

void main() {
  group('the breadcrumb carrier — grid.lease.attempt_id', () {
    test(
      'a full handle round-trips its attempt id through the metadata map',
      () {
        const handle = ProcessHandle(
          pgid: 4242,
          pid: 4343,
          token: 'tok-abc',
          attemptId: _attempt,
        );
        final parsed = leaseBreadcrumbOf(leaseBreadcrumb(handle));
        expect(parsed, isNotNull);
        expect(parsed!.attemptId, _attempt);
        // The process identity is unchanged by the addition.
        expect(parsed, handle);
        expect(parsed.pgid, 4242);
        expect(parsed.pid, 4343);
        expect(parsed.token, 'tok-abc');
      },
    );

    test('the attempt key stays inside the single-writer namespace', () {
      expect(LeaseKeys.attemptId, startsWith(LeaseKeys.prefix));
      const handle = ProcessHandle(pgid: 1, pid: 1, token: 't');
      for (final key in leaseBreadcrumb(handle).keys) {
        expect(key, startsWith(LeaseKeys.prefix), reason: key);
      }
      for (final key in kClearedLeaseKeys.keys) {
        expect(key, startsWith(LeaseKeys.prefix), reason: key);
      }
    });

    test(
      'a PRE-STAGE-1 breadcrumb (no attempt key at all) still parses and still '
      'adopts — the parse is tolerant, so adoption never regresses',
      () {
        const handle = ProcessHandle(pgid: 111, pid: 222, token: 'tok-old');
        final legacy = {
          LeaseKeys.pgid: '111',
          LeaseKeys.pid: '222',
          LeaseKeys.token: 'tok-old',
        };
        expect(legacy.containsKey(LeaseKeys.attemptId), isFalse);
        final parsed = leaseBreadcrumbOf(legacy);
        expect(parsed, handle, reason: 'the process identity still parses');
        expect(
          parsed!.attemptId,
          isEmpty,
          reason: 'empty means UNKNOWN, never "a fresh attempt"',
        );
      },
    );

    test('a BLANK attempt id on an otherwise complete breadcrumb parses the '
        'same way — blank reads exactly like absent', () {
      final blanked = {
        ...leaseBreadcrumb(
          const ProcessHandle(pgid: 5, pid: 6, token: 't', attemptId: _attempt),
        ),
        LeaseKeys.attemptId: '',
      };
      expect(leaseBreadcrumbOf(blanked)!.attemptId, isEmpty);
    });

    test('leaseBreadcrumb ALWAYS names the attempt key, even for a handle that '
        'carries none — a merge write must not leave a PRIOR attempt standing '
        'under this incarnation pgid/pid', () {
      const noAttempt = ProcessHandle(pgid: 9, pid: 9, token: 'tok-fresh');
      final payload = leaseBreadcrumb(noAttempt);
      expect(payload.containsKey(LeaseKeys.attemptId), isTrue);
      expect(payload[LeaseKeys.attemptId], '');
    });

    test('release CLEARS the attempt id with the rest of the namespace', () {
      expect(kClearedLeaseKeys[LeaseKeys.attemptId], '');
      expect(
        leaseBreadcrumbOf(kClearedLeaseKeys),
        isNull,
        reason: 'a cleared lease never round-trips back into a handle',
      );
      expect(
        recoverAttemptId(kClearedLeaseKeys).basis,
        AttemptIdBasis.reconcilerMinted,
        reason: 'a cleared breadcrumb names no live attempt to recover',
      );
    });

    test('the attempt id is NOT part of process identity — a pre-Stage-1 view '
        'of an incarnation equals the same incarnation named', () {
      const bare = ProcessHandle(pgid: 3, pid: 4, token: 'tok');
      const named = ProcessHandle(
        pgid: 3,
        pid: 4,
        token: 'tok',
        attemptId: _attempt,
      );
      expect(named, bare);
      expect(named.hashCode, bare.hashCode);
      // But it is visible where an operator reads it.
      expect(named.toString(), contains(_attempt));
      expect(bare.toString(), isNot(contains('attempt')));
    });
  });

  group('rule 1 — a FRESH SPAWN mints, exports, and persists', () {
    test(
      'the spawner stamps the env attempt id onto the handle and hands it to '
      'the child (transport tier)',
      () async {
        final transport = FakeRuntimeProvider();
        addTearDown(transport.close);
        final args = stepArgs('tg-1/lease');
        final request = _request(transport: transport, args: args);

        final spawning = stationProcessSpawner(
          request,
          FakeTreeContext(),
          args,
        );
        await pumpEventQueue();
        transport.emit(const SessionStarted(name: _name, pid: 7, pgid: 7));
        final handle = await spawning;

        expect(handle.attemptId, _attempt);
        expect(handle.token, 'tok-attempt');
        // The child sees it too — the allocation env layers over the
        // capability's own spawn config.
        expect(
          transport.started.single.config.env['GRID_ATTEMPT_ID'],
          _attempt,
        );
        expect(
          transport.started.single.config.env['GRID_INSTANCE_TOKEN'],
          'tok-attempt',
          reason: 'Stage 1 DUAL-exports; the token is not displaced',
        );
      },
    );

    test('the real vendor PERSISTS the spawned attempt id on the breadcrumb '
        '(composition tier: env -> handle -> grid.lease.attempt_id)', () async {
      final fakes = buildFakes();
      final transport = fakes.provider;
      addTearDown(transport.close);
      final writer = fakes.ctx.writer;
      final vendor = StationProcessLeaseVendor(
        writer: writer,
        spawn: stationProcessSpawner,
        dispatch: stationProcessDispatcher,
        metadataOf: writer.metadataOf,
      );

      final args = stepArgs('tg-1/lease');
      final request = _request(transport: transport, args: args);
      final alloc = vendor
          .leaseFor(request)
          .createAllocation(request.allocation);

      final done = alloc.startOrAdopt();
      await pumpEventQueue();
      transport.emit(const SessionStarted(name: _name, pid: 9, pgid: 9));
      await pumpEventQueue();
      transport.emit(const Exited(name: _name, exitCode: 0));
      await done.timeout(const Duration(seconds: 5));
      await pumpEventQueue();

      expect(fakes.runner.callsFor('update'), isNotEmpty);
      expect(fakes.runner.metadataOfUpdate(0), {
        LeaseKeys.pgid: '9',
        LeaseKeys.pid: '9',
        LeaseKeys.token: 'tok-attempt',
        LeaseKeys.attemptId: _attempt,
      });
      await alloc.dispose();
    });

    test(
      'a spawn whose env carries NO attempt id persists a BLANK one — never a '
      'silently invented name',
      () async {
        final transport = FakeRuntimeProvider();
        addTearDown(transport.close);
        final args = stepArgs('tg-1/lease');
        final request = _request(
          transport: transport,
          args: args,
          attemptId: '',
        );

        final spawning = stationProcessSpawner(
          request,
          FakeTreeContext(),
          args,
        );
        await pumpEventQueue();
        transport.emit(const SessionStarted(name: _name, pid: 7, pgid: 7));
        final handle = await spawning;

        expect(handle.attemptId, isEmpty);
        expect(leaseBreadcrumb(handle)[LeaseKeys.attemptId], '');
      },
    );
  });

  group('rule 2 — ADOPT CONTINUES the breadcrumb attempt (no fresh mint)', () {
    test('the vendor binds the PRIOR attempt id, spawns nothing, and rewrites '
        'no breadcrumb', () async {
      final fakes = buildFakes();
      final transport = fakes.provider;
      addTearDown(transport.close);
      final prior = leaseBreadcrumb(
        const ProcessHandle(
          pgid: 111,
          pid: 222,
          token: 'tok-prior',
          attemptId: _attempt,
        ),
      );
      final vendor = StationProcessLeaseVendor(
        writer: fakes.ctx.writer,
        spawn: (request, context, args) async =>
            throw StateError('adopt must not spawn'),
        dispatch: (handle, request, context, args) async => const Ok({}),
        metadataOf: (stepBeadId) async => prior,
        liveness: (fence) => true,
      );

      final args = stepArgs('tg-1/lease');
      final request = _request(
        transport: transport,
        args: args,
        // A DIFFERENT attempt id sits in the env — the mount minted one, as
        // every mount does. Adoption must ignore it.
        attemptId: '01JQZ9999999999999FRESHMNT',
        kind: StepKind.daemon,
      );
      final alloc =
          vendor.leaseFor(request).createAllocation(request.allocation)
              as LeaseAllocation<ProcessHandle>;
      await alloc.startOrAdopt();

      expect(alloc.adopted, isTrue);
      expect(
        alloc.handle!.attemptId,
        _attempt,
        reason: 'the attempt PERSISTS with the process incarnation',
      );
      expect(transport.started, isEmpty, reason: 'no spawn on adopt');
      expect(
        fakes.runner.callsFor('update'),
        isEmpty,
        reason: 'adopt reattaches — it never re-persists the breadcrumb',
      );
      await alloc.dispose();
    });

    test('a PRE-STAGE-1 survivor still adopts — with an empty attempt id, not '
        'a refusal and not a fresh mint', () async {
      final fakes = buildFakes();
      final transport = fakes.provider;
      addTearDown(transport.close);
      final vendor = StationProcessLeaseVendor(
        writer: fakes.ctx.writer,
        spawn: (request, context, args) async =>
            throw StateError('adopt must not spawn'),
        dispatch: (handle, request, context, args) async => const Ok({}),
        metadataOf: (stepBeadId) async => const {
          LeaseKeys.pgid: '111',
          LeaseKeys.pid: '222',
          LeaseKeys.token: 'tok-old',
        },
        liveness: (fence) => true,
      );

      final args = stepArgs('tg-1/lease');
      final request = _request(
        transport: transport,
        args: args,
        kind: StepKind.daemon,
      );
      final alloc =
          vendor.leaseFor(request).createAllocation(request.allocation)
              as LeaseAllocation<ProcessHandle>;
      await alloc.startOrAdopt();

      expect(alloc.adopted, isTrue);
      expect(alloc.handle!.attemptId, isEmpty);
      await alloc.dispose();
    });
  });

  group('rule 3 — the RECONCILER recovers, or mints and says so', () {
    test('a breadcrumb-carried attempt id is recovered verbatim, OBSERVED', () {
      final recovered = recoverAttemptId(
        leaseBreadcrumb(
          const ProcessHandle(pgid: 1, pid: 2, token: 't', attemptId: _attempt),
        ),
      );
      expect(recovered.attemptId, _attempt);
      expect(recovered.basis, AttemptIdBasis.breadcrumb);
      expect(recovered.basis.inferred, isFalse);
      expect(recovered.basis.wire, 'breadcrumb');
    });

    test(
      'a PRE-STAGE-1 session (no attempt key) settles with a reconciler-minted '
      'id, marked INFERRED',
      () {
        final recovered = recoverAttemptId(const {
          LeaseKeys.pgid: '111',
          LeaseKeys.pid: '222',
          LeaseKeys.token: 'tok-old',
        });
        expect(recovered.attemptId, hasLength(26));
        expect(recovered.basis, AttemptIdBasis.reconcilerMinted);
        expect(recovered.basis.inferred, isTrue);
        expect(recovered.basis.wire, 'reconciler-minted');
      },
    );

    test('NO breadcrumb at all (no step bead) mints the same way', () {
      expect(recoverAttemptId(null).basis, AttemptIdBasis.reconcilerMinted);
      expect(
        recoverAttemptId(const <String, String>{}).basis,
        AttemptIdBasis.reconcilerMinted,
      );
    });

    test(
      'a PARTIAL breadcrumb still yields its attempt id — settling needs the '
      "attempt's NAME, not the adopt fence (leaseBreadcrumbOf refuses it)",
      () {
        final partial = {
          LeaseKeys.token: 'tok-lost',
          LeaseKeys.attemptId: _attempt,
        };
        expect(
          leaseBreadcrumbOf(partial),
          isNull,
          reason: 'a partial breadcrumb is not ADOPTABLE',
        );
        expect(
          recoverAttemptId(partial),
          (attemptId: _attempt, basis: AttemptIdBasis.breadcrumb),
          reason: 'but it still names a real attempt row in the log',
        );
      },
    );

    test('two mints are distinct — a reconciler never collides two sessions '
        'onto one attempt', () {
      final a = recoverAttemptId(null).attemptId;
      final b = recoverAttemptId(null).attemptId;
      expect(a, isNot(b));
      expect(newAttemptId(), isNot(newAttemptId()));
    });
  });
}
