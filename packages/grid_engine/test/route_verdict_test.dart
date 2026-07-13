// tg-6gn — routing unified: advance | rewind | escalate over ONE primitive.
//
// Every case drives a REAL `CapabilityHost` (the ONE router) over the recording
// bd chokepoint, and asserts on the writes it actually made. The writes ARE the
// proof: nothing here is hand-waved through a fake router.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

/// The ROOT circuit: `route` IS the terminal (landing is no longer a step — it is
/// the actuation of this route's advance).
const _code = Circuit(
  id: 'code',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'route', capabilityId: 'route', dependsOn: {'agent'}),
  ],
);

/// A NESTED circuit whose own terminal route must NOT deliver.
const _sub = Circuit(
  id: 'spec',
  terminalStepId: 'route',
  steps: [CapabilityStep(stepId: 'route', capabilityId: 'route')],
);

const _routeStep = CapabilityStep(stepId: 'route', capabilityId: 'route');

// The COMPILE-TIME half of the exhaustiveness proof: no default arm, so adding,
// removing or renaming an arm stops these compiling.
String _describeVerdict(RouteVerdict verdict) => switch (verdict) {
  Advance() => 'advance',
  Rewind() => 'rewind',
  Escalate() => 'escalate',
};

String _describeOutcome(StepOutcome outcome) => switch (outcome) {
  Ok() => 'ok',
  Failed() => 'failed',
};

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Mounts the REAL [CapabilityHost] for [capability] at [circuit]'s route step.
/// The work bead is always `tg-1`, so `circuitPath: 'tg-1'` makes the circuit's
/// terminal step the DELIVERY TERMINAL, and `'tg-1/spec'` makes it a mere
/// sub-circuit terminal. [ambient] mounts the work [Bead] + [Workspace] the real
/// tree provides (WorkBead / SessionScope); pass false to drive the
/// mis-composition refusal.
({TreeOwner owner, Fakes fakes}) _mountRoute(
  Capability capability, {
  Circuit circuit = _code,
  String circuitPath = 'tg-1',
  ServiceBundle services = const ServiceBundle(),
  NodeCursor node = const NodeCursor(),
  bool ambient = true,
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  final nodePath = '$circuitPath/route';
  Seed child = CapabilityHost(
    capability: capability,
    mount: StepMount(
      step: _routeStep,
      nodePath: nodePath,
      circuit: circuit,
      circuitPath: circuitPath,
      session: const SessionHandle('tgdog-s'),
      node: node,
      key: ValueKey('$nodePath#${node.restartCount}.${node.rewindCount}'),
    ),
  );
  if (ambient) {
    child = InheritedSeed<Bead>(
      value: bead('tg-1'),
      child: InheritedSeed<Workspace>(
        value: testWorkspace('tg-1', branch: 'grid/tg-1'),
        child: child,
      ),
    );
  }
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: DateTime(2026)),
        child: InheritedSeed<ServiceBundle>(
          value: services,
          child: InheritedSeed<SiblingView>(
            value: const SiblingView(),
            child: child,
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

/// Mounts, pumps the effect to its terminal, and tears the tree down.
Future<Fakes> _drive(
  Capability capability, {
  Circuit circuit = _code,
  String circuitPath = 'tg-1',
  ServiceBundle services = const ServiceBundle(),
  NodeCursor node = const NodeCursor(),
  bool ambient = true,
}) async {
  final h = _mountRoute(
    capability,
    circuit: circuit,
    circuitPath: circuitPath,
    services: services,
    node: node,
    ambient: ambient,
  );
  addTearDown(() {
    h.owner.dispose();
    unawaited(h.fakes.provider.close());
  });
  await _pump();
  return h.fakes;
}

/// Every `--metadata` payload of every recorded `update`, as raw JSON.
Iterable<String> _allWrites(RecordingBdRunner runner) sync* {
  for (final call in runner.callsFor('update')) {
    final i = call.indexOf('--metadata');
    if (i >= 0) yield call[i + 1];
  }
}

/// A route whose BODY blows up (a mis-authored asset) — the per-work
/// fail-closed posture must catch it, never leak an unhandled zone error.
class _ThrowingRouteCap extends RouteCapability {
  const _ThrowingRouteCap();

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async =>
      throw StateError('the route blew up');
}

void main() {
  group('tg-6gn — the ALLOCATION layer maps each verdict to its OWN report', () {
    Future<AllocationReport> reportFor(RouteCapability capability) async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      await RouteAllocation(
        capability,
        AllocationContext(
          treeContext: FakeTreeContext(),
          args: stepArgs('tg-1/route'),
          transport: provider,
          address: const AllocationAddress('tgdog-s', 'tg-1/route'),
          env: const {},
          sink: reports.add,
        ),
      ).startOrAdopt();
      return reports.single;
    }

    test('Advance → AllocationAdvanced (carrying its payload)', () async {
      final report = await reportFor(
        const FixedRouteCapability(Advance({'grade': 'A'})),
      );
      expect(report, isA<AllocationAdvanced>());
      expect((report as AllocationAdvanced).payload, {'grade': 'A'});
    });

    test('Escalate → AllocationEscalated (carrying its reason)', () async {
      final report = await reportFor(
        const FixedRouteCapability(Escalate('declined')),
      );
      expect(report, isA<AllocationEscalated>());
      expect((report as AllocationEscalated).reason, 'declined');
    });

    test('a THROWING route body routes to supervision as AllocationFailed — '
        'never an unhandled zone error', () async {
      final report = await reportFor(const _ThrowingRouteCap());
      expect(report, isA<AllocationFailed>());
      expect((report as AllocationFailed).reason, contains('route threw'));
      expect(report.reason, contains('the route blew up'));
    });
  });

  group('tg-6gn — a THROWING route reaches the ROUTER as a supervised failure',
      () {
    test('the host writes state=failed + a bumped restartCount, and NEVER '
        'completes', () async {
      final fakes = await _drive(const _ThrowingRouteCap());

      final meta = fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/route.state'], 'failed');
      expect(meta['grid.cursor.tg-1/route.restartCount'], '1');
      expect(
        meta['grid.cursor.tg-1/route.failureReason'],
        contains('route threw'),
      );
      expect(fakes.runner.callsFor('create'), isEmpty, reason: 'no gate bead');
      for (final write in _allWrites(fakes.runner)) {
        expect(write.contains('complete'), isFalse);
      }
    });
  });

  group('tg-6gn — the two unions', () {
    test('RouteVerdict is sealed over exactly {Advance, Rewind, Escalate}', () {
      expect(_describeVerdict(const Advance()), 'advance');
      expect(_describeVerdict(const Rewind({'agent'})), 'rewind');
      expect(_describeVerdict(const Escalate('x')), 'escalate');
    });

    test('StepOutcome is narrowed to exactly {Ok, Failed} — a build agent does '
        'not route', () {
      expect(_describeOutcome(const Ok()), 'ok');
      expect(_describeOutcome(const Failed('boom')), 'failed');
    });
  });

  group('tg-6gn — ADVANCE: delivery is the actuation of a TERMINAL advance', () {
    test('a TERMINAL advance actuates the bound method; the receipt + the '
        'delivery id land in the SAME state=complete write', () async {
      final method = RecordingDeliveryMethod();
      final fakes = await _drive(
        const FixedRouteCapability(Advance({'grade': 'A'})),
        services: ServiceBundle(delivery: method),
      );

      // The method got the ambient tree values as plain VALUES (ADR-0013 1/4).
      final request = method.requests.single;
      expect(request.bead.id, 'tg-1');
      expect(request.workspace.branch, 'grid/tg-1');
      expect(request.payload['grade'], 'A');
      expect(request.nodePath, 'tg-1/route');
      expect(request.sessionId, 'tgdog-s');

      // ONE write: the cursor advance, the route's payload, the method's
      // receipt, and the audit record of HOW the work left — atomically.
      final meta = fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/route.state'], 'complete');
      expect(meta['grid.result.tg-1/route.grade'], 'A');
      expect(meta['grid.result.tg-1/route.pr_url'], 'https://example.test/pr/1');
      expect(meta['grid.result.tg-1/route.delivery'], 'fake-delivery');
    });

    test('COMMIT-ONLY: with NO method bound the terminal advance still '
        'completes and delivers nothing', () async {
      final fakes = await _drive(const FixedRouteCapability(Advance()));

      final meta = fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/route.state'], 'complete');
      for (final write in _allWrites(fakes.runner)) {
        expect(write.contains('.delivery'), isFalse);
        expect(write.contains('failed'), isFalse);
      }
    });

    test('a SUB-CIRCUIT terminal advance NEVER delivers, even with a method '
        'bound', () async {
      final method = RecordingDeliveryMethod();
      final fakes = await _drive(
        const FixedRouteCapability(Advance()),
        circuit: _sub,
        circuitPath: 'tg-1/spec',
        services: ServiceBundle(delivery: method),
      );

      expect(method.requests, isEmpty, reason: 'only the ROOT terminal delivers');
      expect(
        fakes.runner.metadataOfUpdate(0)['grid.cursor.tg-1/spec/route.state'],
        'complete',
      );
    });
  });

  group('tg-6gn — a delivery that does not happen NEVER advances', () {
    test('a FAILED delivery routes to supervision (never state=complete)',
        () async {
      final method = RecordingDeliveryMethod()
        ..outcome = const Failed('gh exploded');
      final fakes = await _drive(
        const FixedRouteCapability(Advance()),
        services: ServiceBundle(delivery: method),
      );

      final meta = fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/route.state'], 'failed');
      expect(meta['grid.cursor.tg-1/route.restartCount'], '1');
      for (final write in _allWrites(fakes.runner)) {
        expect(write.contains('complete'), isFalse);
      }
    });

    test('a THROWING delivery is identical, and NAMES the method', () async {
      final method = RecordingDeliveryMethod()..throwNext = true;
      final fakes = await _drive(
        const FixedRouteCapability(Advance()),
        services: ServiceBundle(delivery: method),
      );

      final meta = fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/route.state'], 'failed');
      expect(
        meta['grid.cursor.tg-1/route.failureReason'],
        contains('fake-delivery'),
      );
    });

    test('a MIS-COMPOSITION (a bound method under a tree with no ambient '
        'Bead/Workspace) refuses LOUD', () async {
      final method = RecordingDeliveryMethod();
      final fakes = await _drive(
        const FixedRouteCapability(Advance()),
        services: ServiceBundle(delivery: method),
        ambient: false,
      );

      final meta = fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/route.state'], 'failed');
      expect(
        meta['grid.cursor.tg-1/route.failureReason'],
        contains('ambient Bead + Workspace'),
      );
      expect(method.requests, isEmpty);
      for (final write in _allWrites(fakes.runner)) {
        expect(write.contains('complete'), isFalse);
      }
    });
  });

  group('tg-6gn — ESCALATE: the engine RAISES, the bound handler DECIDES', () {
    test('NO handler bound reproduces M5 D-7 EXACTLY: state=gated + one real '
        'type=gate bead, and no rewind write', () async {
      final fakes = await _drive(const FixedRouteCapability(Escalate('x')));

      expect(
        fakes.runner.metadataOfUpdate(0)['grid.cursor.tg-1/route.state'],
        'gated',
      );
      final creates = fakes.runner.callsFor('create');
      expect(creates, hasLength(1));
      expect(creates.single, containsAllInOrder(['--type', 'gate']));
      for (final write in _allWrites(fakes.runner)) {
        expect(write.contains('rewindCount'), isFalse);
      }
    });

    test('a BOUND handler receives plain VALUES and parks with ITS OWN reason',
        () async {
      final handler = RecordingEscalationHandler();
      final fakes = await _drive(
        const FixedRouteCapability(Escalate('x')),
        services: ServiceBundle(escalation: handler),
      );

      // The escalation rides IN the value — the handler never probes the world
      // to reconstruct it (ADR-0013 item 2).
      final request = handler.requests.single;
      expect(request.beadId, 'tg-1');
      expect(request.sessionId, 'tgdog-s');
      expect(request.nodePath, 'tg-1/route');
      expect(request.reason, 'x');
      expect(request.rewindCount, 0);

      // The gate bead carries the HANDLER's words, not the route's — the reason
      // rides the bead's birth stamp (the LAST recorded update).
      final creates = fakes.runner.callsFor('create');
      expect(creates, hasLength(1));
      final births = fakes.runner.callsFor('update');
      expect(
        fakes.runner.metadataOfUpdate(births.length - 1)['reason'],
        'parked by the fake handler',
      );
    });

    test('a DECLINING handler fails to supervision and mints NO gate bead',
        () async {
      final handler = RecordingEscalationHandler()
        ..decision = const FailToSupervision('queue full');
      final fakes = await _drive(
        const FixedRouteCapability(Escalate('x')),
        services: ServiceBundle(escalation: handler),
      );

      final meta = fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/route.state'], 'failed');
      expect(
        meta['grid.cursor.tg-1/route.failureReason'],
        contains('fake-handler'),
      );
      expect(fakes.runner.callsFor('create'), isEmpty);
    });

    test('a THROWING handler is identical — an escalation nobody owns must '
        'never look like a park somebody does', () async {
      final handler = RecordingEscalationHandler()..throwNext = true;
      final fakes = await _drive(
        const FixedRouteCapability(Escalate('x')),
        services: ServiceBundle(escalation: handler),
      );

      final meta = fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/route.state'], 'failed');
      expect(
        meta['grid.cursor.tg-1/route.failureReason'],
        contains('fake-handler'),
      );
      expect(fakes.runner.callsFor('create'), isEmpty);
    });
  });

  group('tg-6gn — the BELT escalates through the bound handler', () {
    test('a node AT the rework cap escalates (carrying its spent rewindCount) '
        'instead of rewinding again', () async {
      final handler = RecordingEscalationHandler();
      final fakes = await _drive(
        const FixedRouteCapability(Rewind({'agent'}, 'again')),
        services: ServiceBundle(escalation: handler),
        node: const NodeCursor(rewindCount: kMaxReworkRounds),
      );

      final request = handler.requests.single;
      expect(request.rewindCount, kMaxReworkRounds);
      expect(request.reason, contains('rework cap reached'));

      // The loop does NOT spin: nothing was flipped back to pending.
      for (final write in _allWrites(fakes.runner)) {
        expect(write.contains('pending'), isFalse);
      }
    });
  });

  group('tg-6gn — the delivery seam is PER-SUBSTATION and MODE-AGNOSTIC', () {
    test('two substations binding two different methods each actuate their '
        'OWN — the shape the three landing paths plug into', () async {
      final prNoMerge = RecordingDeliveryMethod(id: 'pr-no-merge');
      final directMerge = RecordingDeliveryMethod(
        id: 'direct-merge',
        outcome: const Ok({'merged_sha': 'abc123'}),
      );

      final a = await _drive(
        const FixedRouteCapability(Advance()),
        services: ServiceBundle(delivery: prNoMerge),
      );
      final b = await _drive(
        const FixedRouteCapability(Advance()),
        services: ServiceBundle(delivery: directMerge),
      );

      expect(prNoMerge.requests, hasLength(1));
      expect(directMerge.requests, hasLength(1));

      final metaA = a.runner.metadataOfUpdate(0);
      expect(metaA['grid.cursor.tg-1/route.state'], 'complete');
      expect(metaA['grid.result.tg-1/route.delivery'], 'pr-no-merge');
      expect(
        metaA['grid.result.tg-1/route.pr_url'],
        'https://example.test/pr/1',
      );

      final metaB = b.runner.metadataOfUpdate(0);
      expect(metaB['grid.cursor.tg-1/route.state'], 'complete');
      expect(metaB['grid.result.tg-1/route.delivery'], 'direct-merge');
      expect(metaB['grid.result.tg-1/route.merged_sha'], 'abc123');
    });
  });
}
