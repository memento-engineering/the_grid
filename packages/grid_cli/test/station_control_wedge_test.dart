import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/src/station_control.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// tg-jwh — the wedge signal on the RS-4 status surface: the station derives it
/// (a real [WedgeMonitor] over the producer-side join) and the status route
/// reports it as a first-class block. No live stores, no real bd/git/claude.
void main() {
  final t0 = DateTime.utc(2026, 7, 12, 10);
  late DateTime now;
  late Map<String, SessionProjection> sessions;
  late WedgeMonitor monitor;

  Future<Map<String, Object?>> statusOf(StationControl control) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('${control.url}/status'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer t');
      final response = await request.close();
      final body = await response.transform(const Utf8Decoder()).join();
      return jsonDecode(body) as Map<String, Object?>;
    } finally {
      client.close(force: true);
    }
  }

  StationStatus status({WedgeState? wedge}) => StationStatus(
    substation: 'tg',
    stateStore: null,
    workRoot: null,
    dryRun: true,
    pid: 1,
    startedAt: t0,
    version: 'test-vm',
    ready: 0,
    mounted: sessions.length,
    liveSessions: sessions.length,
    lastSyncAt: null,
    // The station's OWN truth — never re-derived on the watcher side.
    wedge: wedge ?? monitor.state,
  );

  Future<StationControl> serve({StationStatus Function()? view}) async {
    final control = await StationControl.start(
      port: 0,
      token: 't',
      view: view ?? status,
    );
    addTearDown(control.dispose);
    return control;
  }

  // Molecule fixtures (tg-eli phase 2: the sampler reads ONLY molecule step
  // state — a non-molecule session contributes no nodes).
  Bead step(String id, String nodePath, StepState state) => Bead(
    id: id,
    issueType: IssueType.step,
    status: BeadStatus.open,
    metadata: {
      MoleculeStepKeys.path: nodePath,
      MoleculeStepKeys.state: state.name,
    },
  );

  SessionProjection moleculeSession(String id, StepState state) =>
      SessionProjection(
        workBeadId: id,
        sessionId: 'tgdog-$id',
        isMolecule: true,
        moleculeBeads: [step('tgdog-$id-step', 'n/x', state)],
      );

  setUp(() {
    now = t0;
    sessions = {
      for (final id in ['tg-a', 'tg-b', 'tg-c'])
        id: moleculeSession(id, StepState.gated),
    };
    monitor = WedgeMonitor(
      latest: () => JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: const [],
          dependencies: const [],
          readyIds: const [],
          capturedAt: t0,
        ),
        sessionsByWorkBead: sessions,
      ),
      threshold: const Duration(minutes: 10),
      clock: () => now,
    );
    addTearDown(monitor.dispose);
  });

  test(
    'ALL sessions gated + 0 running, sustained past M → the status route reports '
    'wedged:true with since + reason',
    () async {
      final control = await serve();

      monitor.poll(); // t0 — the stall begins
      now = t0.add(const Duration(minutes: 10));
      monitor.poll();

      final wedge = (await statusOf(control))['wedge']! as Map<String, Object?>;
      expect(wedge['wedged'], isTrue);
      expect(wedge['since'], t0.toIso8601String());
      expect(wedge['reason'], contains('parked at a gate'));
      expect(wedge['live'], 3);
      expect(wedge['running'], 0);
      expect(wedge['gated'], 3);
    },
  );

  test('under M minutes → wedged:false (no false alarm on a between-stages '
      'transition)', () async {
    final control = await serve();

    monitor.poll();
    now = t0.add(const Duration(minutes: 9, seconds: 59));
    monitor.poll();

    final wedge = (await statusOf(control))['wedge']! as Map<String, Object?>;
    expect(wedge['wedged'], isFalse);
    expect(wedge['since'], t0.toIso8601String());
  });

  test('any running session → wedged:false, even with a gate open elsewhere (a '
      'routine gate-open is NOT a wedge)', () async {
    final control = await serve();

    monitor.poll();
    now = t0.add(const Duration(minutes: 20));
    sessions['tg-a'] = moleculeSession('tg-a', StepState.running);
    monitor.poll();

    final wedge = (await statusOf(control))['wedge']! as Map<String, Object?>;
    expect(wedge['wedged'], isFalse);
    expect(wedge['running'], 1);
    expect(wedge['gated'], 2);
  });

  test(
    'the wedge block is a first-class TOP-LEVEL key — the station/process/work '
    'blocks are unchanged',
    () async {
      final control = await serve();
      final body = await statusOf(control);
      expect(
        body.keys,
        containsAll(<String>['station', 'process', 'work', 'wedge']),
      );
      expect(
        (body['work']! as Map<String, Object?>).containsKey('wedged'),
        isFalse,
        reason: 'the wedge is first-class, not smuggled into the work block',
      );
    },
  );

  test('a status built without a work runtime defaults to kNotWedged (never a '
      'phantom alarm)', () async {
    sessions = {};
    final control = await serve(
      view: () => StationStatus(
        substation: 'tg',
        stateStore: null,
        workRoot: null,
        dryRun: true,
        pid: 1,
        startedAt: t0,
        version: 'test-vm',
        ready: 0,
        mounted: 0,
        liveSessions: 0,
        lastSyncAt: null,
      ),
    );

    final wedge = (await statusOf(control))['wedge']! as Map<String, Object?>;
    expect(wedge['wedged'], isFalse);
    expect(wedge['live'], 0);
  });
}
