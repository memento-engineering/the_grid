// M6 Track F — the BURN formula, offline end-to-end (ADR-0011 D9).
//
// The burn is TWO capability-scoped orders (`burn-follower` leased to a
// capability match + `burn-host` local) over TWO orthogonal channels: the
// federation BUS (lease + endpoint rendezvous) and the DIRECT leonard_drive ↔
// ext.exploration.* perception channel. These tests exercise the REAL capability
// bodies + the follower runner with FAKES (no real leonard/butane/claude, no
// socket): a fake lessor station wraps a ButaneFollowerRunner whose launcher is a
// headless stand-in and whose reaper is a fake ProcessGroupController, and a
// scripted LeonardDrive supplies zero-model responses. The engine's
// fan-out/barrier/daemon/teardown MECHANICS are already proven offline by
// grid_engine's track_j_burn_test; here we prove the burn DOMAIN: rendezvous,
// the direct drive, the collected TestReport, and the GUARANTEED teardown (the
// follower daemon is reaped even on the failure path).
import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart' show LeaseAllocation;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart' show FakeRuntimeProvider, bead;
import 'package:grid_federation/grid_federation.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show GroupTerminateResult, ProcessGroupController;
import 'package:test/test.dart';

/// The endpoint the headless follower stand-in publishes.
const FollowerEndpoint _published = FollowerEndpoint(
  vmServiceUri: 'ws://127.0.0.1:5599/Abc123=/ws',
  station: 'the-dashboard',
);

/// A linux/ble follower profile that SATISFIES [kDefaultFollowerRequires].
const Map<String, Object?> _linuxProfile = {
  'system-os': 'linux',
  'flutter-target': ['linux'],
  'radio': ['ble'],
};

/// A macos profile that does NOT satisfy the follower requirements.
const Map<String, Object?> _macosProfile = {
  'system-os': 'macos',
  'flutter-target': ['macos'],
};

// --- fakes (Fakes, not mocks) ------------------------------------------------

/// A headless follower launcher stand-in — never shells butane/flutter; returns
/// a fixed [LaunchedDaemon] with a reapable pgid.
class _FakeFollowerLauncher implements FollowerLauncher {
  static const LaunchedDaemon _daemon = LaunchedDaemon(
    pid: 4242,
    pgid: 4242,
    endpoint: _published,
  );

  int launches = 0;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    launches++;
    return _daemon;
  }
}

/// A fake process-group controller — records the signals the M4 reaper sends and
/// reports the group as exiting on SIGTERM (so `terminateGroup` resolves cleanly,
/// fully offline + deterministic). Its own group id is unique so the guard never
/// refuses (it is never the daemon's pgid).
class _FakeProcessGroupController implements ProcessGroupController {
  final List<String> signals = [];
  bool _alive = true;

  @override
  Future<int?> resolvePgid(int pid) async => pid;

  @override
  bool processAlive(int pid) => _alive;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    final label = signal == ProcessSignal.sigterm
        ? 'TERM'
        : signal == ProcessSignal.sigkill
        ? 'KILL'
        : 'OTHER';
    signals.add('$label:$pgid');
    if (signal == ProcessSignal.sigterm) _alive = false; // exits on TERM
    return true;
  }

  @override
  int currentGroupId() => 999999;

  /// Whether the group was actually signalled for termination.
  bool get terminated => signals.any((s) => s.startsWith('TERM'));
}

/// A fake lessor station (the follower box) over the federation bus, backed by a
/// real [ButaneFollowerRunner]: `dispatch` launches the follower (publishing its
/// endpoint), `release` reaps it through the runner's M4 reaper. Records calls in
/// order; never touches a socket.
class _FollowerStation implements StationClient {
  _FollowerStation({
    required this.runner,
    this.station = 'the-dashboard',
    this.profile = _linuxProfile,
    this.onLeaseGranted,
  });

  final ButaneFollowerRunner runner;
  final String station;
  final Map<String, Object?> profile;

  /// Set true to make the lessor deny leases (no capacity).
  bool denyLease = false;

  /// Fires right after a grant is minted — used to simulate a dispose racing the
  /// acquire (the bus latency window).
  final void Function()? onLeaseGranted;

  final List<String> calls = [];
  int _seq = 0;

  @override
  Future<Presence> presence() async {
    calls.add('presence');
    return Presence(
      station: station,
      kinds: const [kBurnKind],
      offered: 1,
      available: runner.isRunning ? 0 : 1,
      profile: profile,
    );
  }

  @override
  Future<LeaseGrant> requestLease(LeaseRequest req) async {
    calls.add('lease:${req.lessee}:${req.kind}');
    if (denyLease) throw const LeaseDeniedException('no capacity');
    final grant = LeaseGrant(
      leaseId: 'burn-lease-${_seq++}',
      station: station,
      ttlSeconds: 300,
      fencingToken: 1,
      kind: req.kind,
    );
    onLeaseGranted?.call();
    return grant;
  }

  @override
  Future<Map<String, dynamic>> dispatch(
    LeaseGrant lease,
    Map<String, dynamic> payload, {
    String idempotencyKey = '',
  }) async {
    calls.add('dispatch');
    final endpoint = await runner.launch(LaunchSpec.fromJson(payload));
    return endpoint.toJson();
  }

  @override
  Future<void> heartbeat(LeaseGrant lease) async => calls.add('heartbeat');

  @override
  Future<void> release(LeaseGrant lease) async {
    calls.add('release');
    await runner.teardown(); // the lessor reaps the launched app on release
  }

  @override
  Future<void> close() async => calls.add('close');

  int countWith(String prefix) =>
      calls.where((c) => c.startsWith(prefix)).length;
}

/// A scripted, zero-model leonard_drive over the DIRECT perception channel.
class _ScriptedLeonardDrive implements LeonardDrive {
  _ScriptedLeonardDrive({
    this.observeResponses = const {},
    this.invokeResponses = const {},
  });

  final Map<String, String> observeResponses;
  final Map<String, String> invokeResponses;
  final List<String> calls = [];
  String? attachedTo;
  bool closed = false;

  @override
  Future<void> attach(FollowerEndpoint endpoint) async {
    attachedTo = endpoint.vmServiceUri;
    calls.add('attach:${endpoint.vmServiceUri}');
  }

  @override
  Future<String> observe(String path) async {
    calls.add('observe:$path');
    return observeResponses[path] ?? '';
  }

  @override
  Future<String> invoke(String tool, Map<String, String> args) async {
    calls.add('invoke:$tool');
    return invokeResponses[tool] ?? '';
  }

  @override
  Future<void> close() async {
    calls.add('close');
    closed = true;
  }
}

// --- helpers -----------------------------------------------------------------

/// Builds a follower runner + the fake lessor station that wraps it.
({_FollowerStation station, _FakeProcessGroupController processes, ButaneFollowerRunner runner})
_lessor({
  Map<String, Object?> profile = _linuxProfile,
  String station = 'the-dashboard',
  void Function()? onLeaseGranted,
}) {
  final processes = _FakeProcessGroupController();
  final runner = ButaneFollowerRunner(
    launcher: _FakeFollowerLauncher(),
    processes: processes,
  );
  final s = _FollowerStation(
    runner: runner,
    station: station,
    profile: profile,
    onLeaseGranted: onLeaseGranted,
  );
  return (station: s, processes: processes, runner: runner);
}

CapabilityContext _ctx({
  required String nodePath,
  CancelToken? cancel,
  SiblingView siblings = const SiblingView(),
}) => CapabilityContext(
  params: const {},
  bead: bead('tg-burn'),
  workspaceDir: '/w/tg-burn',
  branch: 'grid/tg-burn',
  baseBranch: 'main',
  services: const ServiceBundle(),
  cancel: cancel ?? CancelToken(),
  nodePath: nodePath,
  siblings: siblings,
);

const String _followerPath = 'tg-burn/$kBurnFollowerStep';
const String _hostPath = 'tg-burn/$kBurnHostStep';

/// Drives the `burn-follower` order as the engine would — a daemon
/// [LeaseAllocation] (mount → adopt-or-acquire → dispatch), returning the pushed
/// reports + the allocation (so a test can dispose it, releasing the lease → the
/// peer reaps the launched app). The burn formula's follower step is
/// `StepKind.daemon`, so a successful launch reports `ready` (stays live), never
/// `complete`.
Future<({List<AllocationReport> reports, LeaseAllocation alloc})> _driveFollower(
  BurnFollowerCapability follower,
  CapabilityContext ctx,
) async {
  final reports = <AllocationReport>[];
  final alloc = follower.createAllocation(
    AllocationContext(
      capContext: ctx,
      transport: FakeRuntimeProvider(),
      address: AllocationAddress('tgdog-s', ctx.nodePath),
      env: const {},
      sink: reports.add,
      kind: StepKind.daemon,
    ),
  ) as LeaseAllocation;
  await alloc.startOrAdopt();
  return (reports: reports, alloc: alloc);
}

/// The rendezvous payload the follower published (its `ready` report), or null if
/// it never reached ready (a failed order).
Map<String, String>? _publishedEndpoint(List<AllocationReport> reports) {
  final ready = reports.whereType<AllocationReady>();
  return ready.isEmpty ? null : ready.first.payload;
}

const LaunchSpec _spec = LaunchSpec(app: 'butane_flutter', target: 'linux');

/// A passing scripted scenario (every step's expectation holds).
DriveScenario _passingScenario() => const DriveScenario(
  name: 'smoke',
  steps: [
    DriveStep.observe('cli', expectContains: 'ready'),
    DriveStep.invoke('grid.ready', expectContains: 'tg-1'),
  ],
);

_ScriptedLeonardDrive _passingDrive() => _ScriptedLeonardDrive(
  observeResponses: const {'cli': '{"state":"ready"}'},
  invokeResponses: const {'grid.ready': '["tg-1","tg-2"]'},
);

void main() {
  group('the burn formula composition (ADR-0011 D9)', () {
    test('two capability-scoped orders + the rendezvous barrier', () {
      expect(kBurnFormula.id, 'burn');
      expect(kBurnFormula.terminalStepId, kBurnHostStep);
      expect(kBurnFormula.supervision, SupervisionStrategy.restForOne);

      final follower = kBurnFormula.stepById(kBurnFollowerStep) as CapabilityStep;
      final host = kBurnFormula.stepById(kBurnHostStep) as CapabilityStep;
      expect(
        follower.kind,
        StepKind.daemon,
        reason: 'the follower app is a long-lived daemon on the peer',
      );
      expect(follower.dependsOn, isEmpty);
      expect(
        host.dependsOn,
        {kBurnFollowerStep},
        reason: 'the host awaits the follower rendezvous (the barrier)',
      );
      expect(host.kind, StepKind.job);
    });

    test('the formula round-trips through JSON (the one declared shape)', () {
      final decoded =
          jsonDecode(jsonEncode(kBurnFormula)) as Map<String, dynamic>;
      expect(Formula.fromJson(decoded), kBurnFormula);
    });

    test('buildBurnRegistry wires the two orders + the burn formula', () {
      final reg = buildBurnRegistry(
        peers: const [],
        launchSpec: _spec,
        drive: _ScriptedLeonardDrive(),
        scenario: const DriveScenario(name: 's', steps: []),
      );
      expect(reg.formula('burn'), kBurnFormula);
    });
  });

  group('capability matching (Track C containment, ADR-0011 D6)', () {
    test('matchFollower picks the first peer whose profile satisfies the '
        'requires by containment', () async {
      final macos = _lessor(profile: _macosProfile, station: 'studio');
      final linux = _lessor(profile: _linuxProfile, station: 'dashboard');
      final picked = await matchFollower(
        peers: [
          FollowerPeer(id: 'studio', client: macos.station),
          FollowerPeer(id: 'dashboard', client: linux.station),
        ],
        requires: kDefaultFollowerRequires,
      );
      expect(picked?.id, 'dashboard');
    });

    test('matchFollower returns null when no peer matches (fail-closed)',
        () async {
      final macos = _lessor(profile: _macosProfile, station: 'studio');
      final picked = await matchFollower(
        peers: [FollowerPeer(id: 'studio', client: macos.station)],
        requires: kDefaultFollowerRequires,
      );
      expect(picked, isNull);
    });
  });

  group('the burn — the happy path (rendezvous → drive → report → teardown)', () {
    test('fan-out two orders → rendezvous → scripted drive → TestReport '
        'collected → both torn down', () async {
      final lessor = _lessor();
      final follower = BurnFollowerCapability(
        peers: [FollowerPeer(id: 'the-dashboard', client: lessor.station)],
        launchSpec: _spec,
        lessee: 'the-studio',
      );
      final drive = _passingDrive();
      final host = BurnHostCapability(drive: drive, scenario: _passingScenario());

      // ORDER 1 — burn-follower: match → lease → dispatch launch → endpoint. As a
      // daemon lease it reports `ready` (stays live), NEVER `complete` (the
      // daemon-reap fix): the endpoint rides the ready payload.
      final fCtx = _ctx(nodePath: _followerPath);
      final f = await _driveFollower(follower, fCtx);
      expect(f.reports.whereType<AllocationReady>(), hasLength(1));
      expect(f.reports.whereType<AllocationCompleted>(), isEmpty,
          reason: 'a held daemon lease must not complete/retire');
      expect(
        lessor.station.calls,
        ['presence', 'lease:the-studio:burn', 'dispatch'],
        reason: 'the rendezvous rode the bus: probe → lease → dispatch',
      );
      expect(lessor.runner.isRunning, isTrue, reason: 'the follower launched');

      // The endpoint handoff: the follower's ready payload threads to the host as
      // a sibling result (D-5 — pull-free, never through the bus).
      final published = _publishedEndpoint(f.reports)!;
      expect(published['endpoint'], _published.vmServiceUri);

      // ORDER 2 — burn-host: read endpoint → attach drive → scripted scenario.
      final hCtx = _ctx(
        nodePath: _hostPath,
        siblings: SiblingView(results: {_followerPath: published}),
      );
      final hOut = await host.run(hCtx);
      expect(hOut, isA<Ok>());
      expect(
        drive.attachedTo,
        _published.vmServiceUri,
        reason: 'the DIRECT perception channel attached to the published endpoint',
      );

      // The domain TestReport is collected (and passing).
      final report = host.reportFor(hCtx);
      expect(report, isNotNull);
      expect(report!.passed, isTrue);
      expect(report.total, 2);
      expect(report.failures, 0);

      // TEARDOWN both orders: host closes the drive; the follower allocation's
      // dispose releases the lease → the lessor reaps the launched app via the M4
      // terminateGroup reaper.
      await host.teardown(hCtx);
      await f.alloc.dispose();
      expect(drive.closed, isTrue, reason: 'the drive channel is closed');
      expect(lessor.station.calls, contains('release'));
      expect(
        lessor.runner.isRunning,
        isFalse,
        reason: 'the follower daemon is reaped on release',
      );
      expect(
        lessor.processes.terminated,
        isTrue,
        reason: 'reaped via terminateGroup (pgid reaper)',
      );
    });
  });

  group('the burn — the failure path (guaranteed teardown)', () {
    test('the scripted scenario fails → host escalates (Failed) → the leaked '
        'follower daemon is STILL reaped', () async {
      final lessor = _lessor();
      final follower = BurnFollowerCapability(
        peers: [FollowerPeer(id: 'the-dashboard', client: lessor.station)],
        launchSpec: _spec,
      );
      // A scenario whose second step's expectation does NOT hold → a regression.
      final drive = _ScriptedLeonardDrive(
        observeResponses: const {'cli': '{"state":"ready"}', 'panel': 'boom'},
      );
      final scenario = const DriveScenario(
        name: 'smoke',
        steps: [
          DriveStep.observe('cli', expectContains: 'ready'),
          DriveStep.observe('panel', expectContains: 'ok'), // fails
        ],
      );
      final host = BurnHostCapability(drive: drive, scenario: scenario);

      final fCtx = _ctx(nodePath: _followerPath);
      final f = await _driveFollower(follower, fCtx);
      final published = _publishedEndpoint(f.reports)!;
      expect(lessor.runner.isRunning, isTrue, reason: 'a daemon to leak');

      final hCtx = _ctx(
        nodePath: _hostPath,
        siblings: SiblingView(results: {_followerPath: published}),
      );
      final hOut = await host.run(hCtx);
      expect(hOut, isA<Failed>(), reason: 'a failed scenario escalates');
      final report = host.reportFor(hCtx);
      expect(report!.passed, isFalse);
      expect(report.failures, 1);
      expect(report.total, 2, reason: 'every step is recorded, not just the first');

      // The GUARANTEED teardown: even though the host escalated, tearing the
      // orders down reaps the follower daemon — no leaked process.
      await host.teardown(hCtx);
      await f.alloc.dispose();
      expect(
        lessor.runner.isRunning,
        isFalse,
        reason: 'the leaked follower daemon is reaped on the failure path',
      );
      expect(lessor.processes.terminated, isTrue);
    });

    test('no peer matches → the follower order is denied; nothing leases or '
        'launches', () async {
      final lessor = _lessor(profile: _macosProfile); // wrong OS
      final follower = BurnFollowerCapability(
        peers: [FollowerPeer(id: 'studio', client: lessor.station)],
        launchSpec: _spec,
      );
      final ctx = _ctx(nodePath: _followerPath);
      final f = await _driveFollower(follower, ctx);
      expect(f.reports.single, isA<AllocationFailed>());
      expect(lessor.station.calls, ['presence'], reason: 'probed, then no lease');
      expect(lessor.runner.isRunning, isFalse);
      await f.alloc.dispose(); // no grant held → no release
      expect(lessor.station.countWith('release'), 0);
    });

    test('the host with no rendezvous endpoint fails (does not attach the drive)',
        () async {
      final drive = _passingDrive();
      final host = BurnHostCapability(drive: drive, scenario: _passingScenario());
      // No sibling result for the follower step → no endpoint.
      final out = await host.run(_ctx(nodePath: _hostPath));
      expect(out, isA<Failed>());
      expect(drive.attachedTo, isNull, reason: 'never attached without an endpoint');
    });

    test('a denied lease → the follower order fails; dispose no-ops', () async {
      final lessor = _lessor()..station.denyLease = true;
      final follower = BurnFollowerCapability(
        peers: [FollowerPeer(id: 'the-dashboard', client: lessor.station)],
        launchSpec: _spec,
      );
      final ctx = _ctx(nodePath: _followerPath);
      final f = await _driveFollower(follower, ctx);
      expect(f.reports.single, isA<AllocationFailed>());
      expect(lessor.station.countWith('dispatch'), 0);
      await f.alloc.dispose();
      expect(lessor.station.countWith('release'), 0);
    });

    test('a dispose racing the acquire releases the grant + skips the dispatch '
        '(release even when cancelled)', () async {
      final cancel = CancelToken();
      final lessor = _lessor(onLeaseGranted: cancel.cancel);
      final follower = BurnFollowerCapability(
        peers: [FollowerPeer(id: 'the-dashboard', client: lessor.station)],
        launchSpec: _spec,
      );
      final ctx = _ctx(nodePath: _followerPath, cancel: cancel);
      final f = await _driveFollower(follower, ctx);
      expect(f.reports, isEmpty, reason: 'a cancelled start reports nothing');
      expect(lessor.station.countWith('dispatch'), 0, reason: 'no launch after cancel');
      expect(lessor.station.countWith('release'), 1, reason: 'released despite cancel');
      // dispose must NOT double-release (start released inline; no held grant).
      await f.alloc.dispose();
      expect(lessor.station.countWith('release'), 1);
    });

    test('the follower order releases ONCE (idempotent on a double dispose)',
        () async {
      final lessor = _lessor();
      final follower = BurnFollowerCapability(
        peers: [FollowerPeer(id: 'the-dashboard', client: lessor.station)],
        launchSpec: _spec,
      );
      final ctx = _ctx(nodePath: _followerPath);
      final f = await _driveFollower(follower, ctx);
      await f.alloc.dispose();
      await f.alloc.dispose();
      expect(lessor.station.countWith('release'), 1);
    });
  });

  group('the follower runner — guaranteed teardown via the M4 reaper', () {
    test('launch publishes the endpoint; teardown reaps the group ONCE', () async {
      final processes = _FakeProcessGroupController();
      final runner = ButaneFollowerRunner(
        launcher: _FakeFollowerLauncher(),
        processes: processes,
      );
      final endpoint = await runner.launch(_spec);
      expect(endpoint.vmServiceUri, _published.vmServiceUri);
      expect(runner.isRunning, isTrue);

      expect(await runner.teardown(), GroupTerminateResult.exitedOnTerm);
      expect(runner.isRunning, isFalse);
      expect(processes.terminated, isTrue);

      // A second teardown is a no-op (a release racing a TTL reap).
      expect(await runner.teardown(), GroupTerminateResult.alreadyGone);
      expect(processes.signals.where((s) => s.startsWith('TERM')).length, 1);
    });
  });
}
