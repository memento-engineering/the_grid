import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

const _config = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
  maxConcurrentWork: 1,
);

const _retired = SessionProjection(
  workBeadId: 'tg-1#r1',
  sessionId: 'tgdog-retired',
);

final class _GatedRetiredCloseRunner extends RecordingBdRunner {
  _GatedRetiredCloseRunner() : super(createdId: 'tgdog-successor');

  final closeEntered = Completer<void>();
  final releaseClose = Completer<void>();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args.length > 1 &&
        args.first == 'close' &&
        args[1] == 'tgdog-retired') {
      if (!closeEntered.isCompleted) closeEntered.complete();
      await releaseClose.future;
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _ObservedJoinedSnapshot extends StatefulSeed {
  const _ObservedJoinedSnapshot({required this.child});

  final Seed child;

  @override
  State<_ObservedJoinedSnapshot> createState() =>
      _ObservedJoinedSnapshotState();
}

final class _ObservedJoinedSnapshotState
    extends State<_ObservedJoinedSnapshot> {
  JoinedSnapshot _snapshot = JoinedSnapshot.empty();
  JoinedSnapshotNotifier? _notifier;
  void Function()? _removeListener;

  @override
  void didChangeDependencies() {
    final notifier = context.watch<JoinedSnapshotNotifier>();
    assert(
      notifier != null,
      '_ObservedJoinedSnapshot requires a JoinedSnapshotNotifier',
    );
    if (identical(notifier, _notifier)) return;
    _removeListener?.call();
    _notifier = notifier;
    var first = true;
    _removeListener = notifier!.addListener((snapshot) {
      if (first) {
        first = false;
        _snapshot = snapshot;
        return;
      }
      if (!context.mounted) return;
      setState(() => _snapshot = snapshot);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _removeListener?.call();
    _removeListener = null;
  }

  @override
  Seed build(TreeContext context) =>
      Provider<JoinedSnapshot>.value(_snapshot, child: seed.child);
}

JoinedSnapshot _snapshot(SessionProjection session) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [bead('tg-1')],
    dependencies: const [],
    readyIds: const {'tg-1'},
    capturedAt: DateTime.utc(2026, 9, 12),
  ),
  sessionsByWorkBead: {'tg-1': session},
);

StationAdmissionReservation _reserveRetiredRound(
  StationServices station,
  JoinedSnapshot snapshot,
) {
  final work = bead('tg-1');
  return station.admission
      .admitPending(snapshot, _config, const ServiceBundle(), [
        StationAdmissionCandidate(bead: work, session: _retired),
      ])
      .admitted
      .single;
}

({TreeOwner owner, Branch root}) _mountRetiredRound({
  required JoinedSnapshotNotifier joined,
  required StationServices station,
  required StationAdmissionReservation reservation,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: station,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(circuits: const {}),
            child: InheritedSeed<ServiceBundle>(
              value: const ServiceBundle(),
              child: Provider<StationAdmissionReservation>.value(
                reservation,
                child: _ObservedJoinedSnapshot(
                  child: SessionScope(
                    bead: bead('tg-1'),
                    circuit: _circuit,
                    existingSession: _retired,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root);
}

Iterable<List<String>> _sessionCreates(RecordingBdRunner runner) =>
    runner.callsFor('create').where((call) {
      if (call.length > 1 && call[1] == '--graph') return false;
      final type = call.indexOf('--type');
      return type >= 0 &&
          type + 1 < call.length &&
          call[type + 1] == GridIssueTypes.session.wire;
    });

Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

void main() {
  group('causal close freshness barrier', () {
    late Duration originalGrace;

    setUpAll(() {
      originalGrace = SessionScopeState.freshMintSnapshotGrace;
      SessionScopeState.freshMintSnapshotGrace = const Duration(
        milliseconds: 50,
      );
    });

    tearDownAll(() {
      SessionScopeState.freshMintSnapshotGrace = originalGrace;
    });

    test('barrier admits the causally closed predecessor', () async {
      final runner = _GatedRetiredCloseRunner();
      addTearDown(() {
        if (!runner.releaseClose.isCompleted) runner.releaseClose.complete();
      });
      final fakes = buildFakes(createdId: 'unused');
      addTearDown(fakes.provider.close);
      final station = StationServices(
        provider: fakes.provider,
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
        maxConcurrentWork: 1,
      );
      addTearDown(station.dispose);
      final stale = _snapshot(_retired);
      final reservation = _reserveRetiredRound(station, stale);
      expect(reservation.reservationToken, isNotNull);
      final joined = JoinedSnapshotNotifier(stale);
      addTearDown(joined.dispose);
      final mounted = _mountRetiredRound(
        joined: joined,
        station: station,
        reservation: reservation,
      );
      addTearDown(mounted.owner.dispose);

      await runner.closeEntered.future;
      runner.releaseClose.complete();
      await _pumpUntil(mounted.owner, () => _sessionCreates(runner).isNotEmpty);

      expect(_sessionCreates(runner), hasLength(1));
      expect(
        runner.callsFor('close').where((call) => call[1] == 'tgdog-retired'),
        hasLength(1),
      );
      final closeIndex = runner.calls.indexWhere(
        (call) =>
            call.length > 1 &&
            call.first == 'close' &&
            call[1] == 'tgdog-retired',
      );
      final createIndex = runner.calls.indexWhere(
        (call) => _sessionCreates(runner).contains(call),
      );
      expect(closeIndex, isNonNegative);
      expect(closeIndex, lessThan(createIndex));
    });

    test('barrier vetoes a different open row', () async {
      final runner = _GatedRetiredCloseRunner();
      addTearDown(() {
        if (!runner.releaseClose.isCompleted) runner.releaseClose.complete();
      });
      final fakes = buildFakes(createdId: 'unused');
      addTearDown(fakes.provider.close);
      final station = StationServices(
        provider: fakes.provider,
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
        maxConcurrentWork: 1,
      );
      addTearDown(station.dispose);
      final stale = _snapshot(_retired);
      final reservation = _reserveRetiredRound(station, stale);
      expect(reservation.reservationToken, isNotNull);
      final joined = JoinedSnapshotNotifier(stale);
      addTearDown(joined.dispose);
      final mounted = _mountRetiredRound(
        joined: joined,
        station: station,
        reservation: reservation,
      );
      addTearDown(mounted.owner.dispose);

      await runner.closeEntered.future;
      joined.push(
        _snapshot(
          const SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'tgdog-unrelated',
          ),
        ),
      );
      mounted.owner.flush();
      runner.releaseClose.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      mounted.owner.flush();

      expect(_sessionCreates(runner), isEmpty);
      expect(
        runner.callsFor('close').where((call) => call[1] == 'tgdog-retired'),
        hasLength(1),
      );
    });
  });

  group('causal close reset sites', () {
    late String source;

    setUpAll(() {
      source = File('lib/src/circuit/session_scope.dart').readAsStringSync();
    });

    test('resets on successful mint', () {
      final mint = source.indexOf('_moleculeSessionId = id;');
      final reset = source.indexOf(
        '_causallyClosedRetiredSessionId = null;',
        mint,
      );
      expect(mint, isNonNegative);
      expect(reset, greaterThan(mint));
      expect(reset, lessThan(source.indexOf('_recorder.sessionMinted(', mint)));
    });

    test('resets on dispose', () {
      final dispose = source.indexOf('void dispose()');
      final cancelled = source.indexOf('_cancelled = true;', dispose);
      final reset = source.indexOf(
        '_causallyClosedRetiredSessionId = null;',
        cancelled,
      );
      expect(dispose, isNonNegative);
      expect(cancelled, greaterThan(dispose));
      expect(reset, greaterThan(cancelled));
      expect(
        reset,
        lessThan(source.indexOf('_mintingSuccessorForPath.clear', cancelled)),
      );
    });

    test('resets on abandoned mint', () {
      final method = source.indexOf('Future<bool> _stopAbandonedMint({');
      final guard = source.indexOf('if (reason == null) return false;', method);
      final reset = source.indexOf(
        '_causallyClosedRetiredSessionId = null;',
        guard,
      );
      final compensation = source.indexOf(
        'await _ctx?.admission.abandonSessionAttempt(',
        guard,
      );
      expect(method, isNonNegative);
      expect(guard, greaterThan(method));
      expect(reset, greaterThan(guard));
      expect(reset, lessThan(compensation));
    });
  });
}
