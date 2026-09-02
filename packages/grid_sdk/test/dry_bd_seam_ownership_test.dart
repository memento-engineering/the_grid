// tg-czsf — the dry-run bd seam mints its canned ids under the OWNING
// partition's prefix, so the chokepoint's fail-closed ownership assert
// (ADR-0006 Decision 2) passes on a dry id exactly as it does on a live
// `bd create` id. The predicate is untouched: the SEAM is what changed, and
// the `close('dry-session')` control below proves the gate still refuses an
// unprefixed id.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show BeadOwnershipPredicate, OwnershipRefused, StationBeadWriter;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// A Fake probe reader — the mint path reads nothing and the molecule pour's
/// already-minted scan must come back empty (house rule: Fakes, not mocks).
final class _EmptyProbeReader implements BeadProbeReader {
  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async =>
      null;

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => const <Bead>[];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async =>
      const <Bead>[];
}

/// A minimal resolver — no tree mounts in these tests.
class _NullResolver implements SessionResolver {
  const _NullResolver();

  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('no tree mounts in the dry-seam tests');
}

void _seedStore(String dir, {required String database}) {
  Directory('$dir/.beads').createSync(recursive: true);
  File(
    '$dir/.beads/metadata.json',
  ).writeAsStringSync('{"dolt_mode":"embedded","dolt_database":"$database"}');
}

({StationBeadWriter writer, List<String> refusals}) _dryWriter() {
  final refusals = <String>[];
  return (
    writer: StationBeadWriter(
      bd: BdCliService(NoOpBdRunner(substation: 'tgstate')),
      reader: _EmptyProbeReader(),
      ownership: BeadOwnershipPredicate({'tgstate', 'proj'}),
      onRefusal: refusals.add,
    ),
    refusals: refusals,
  );
}

void main() {
  group('the dry bd seam mints under its owning partition (tg-czsf)', () {
    test('every canned create id carries the seam prefix and is '
        'distinguishable', () async {
      final runner = NoOpBdRunner(substation: 'tgstate');

      final first = await runner.run(['create', '--json']);
      final second = await runner.run(['create', '--json']);

      expect(first.stdout, contains('"id":"tgstate-dry-1"'));
      expect(second.stdout, contains('"id":"tgstate-dry-2"'));
      expect(first.stdout, isNot(contains('dry-session')));
    });

    test('a non-create call still echoes its target id', () async {
      final runner = NoOpBdRunner(substation: 'tgstate');

      final result = await runner.run(['update', 'tgstate-dry-1', '--json']);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('"id":"tgstate-dry-1"'));
    });

    test('a seam mints under the owner that will assert it — a WORK seam '
        'takes its substation prefix, not the state one', () async {
      final workSeam = NoOpBdRunner(substation: 'pow');

      final minted = await workSeam.run(['create', '--json']);

      expect(minted.stdout, contains('"id":"pow-dry-1"'));
      expect(
        BeadOwnershipPredicate({'proj', 'pow'}).ownsTarget(id: 'pow-dry-1'),
        isTrue,
      );
    });

    test('the session mint returns a prefixed id the UNCHANGED predicate '
        'owns', () async {
      final dry = _dryWriter();

      final id = await dry.writer.createSession(
        substation: 'proj',
        title: 'grid session proj-1',
        workBeadId: 'proj-1',
      );

      expect(id, 'tgstate-dry-1');
      expect(dry.refusals, isEmpty);
      expect(
        BeadOwnershipPredicate.ownedPrefixOf(id, {'tgstate', 'proj'}),
        'tgstate',
      );
      expect(
        BeadOwnershipPredicate({'tgstate', 'proj'}).ownsTarget(id: id),
        isTrue,
      );
    });

    test('an owned follow-up write on the minted id clears the chokepoint, '
        'while the gate still refuses the old literal', () async {
      final dry = _dryWriter();
      final id = await dry.writer.createSession(
        substation: 'proj',
        title: 'grid session proj-1',
        workBeadId: 'proj-1',
      );

      // The assert that fired before the fix (`_assertOwned('close', id)`).
      await dry.writer.close(id, reason: 'dry smoke');
      expect(dry.refusals, isEmpty);

      // THE LIVE CONTROL: the predicate is untouched, so the former canned
      // literal is still not-owned and still refuses LOUDLY.
      await expectLater(
        dry.writer.close('dry-session'),
        throwsA(isA<OwnershipRefused>()),
      );
      expect(dry.refusals, hasLength(1));
      expect(dry.refusals.single, contains('dry-session'));
    });

    test('the molecule pour clears the parent-ownership assert — the site the '
        'reported refusal actually fired from', () async {
      final dry = _dryWriter();
      final id = await dry.writer.createSession(
        substation: 'proj',
        title: 'grid session proj-1',
        workBeadId: 'proj-1',
      );
      final plan = GraphApplyPlan(
        commitMessage: 'dry molecule pour',
        nodes: [
          GraphNode(
            key: 'root',
            title: 'molecule',
            type: 'molecule',
            parentId: id,
          ),
        ],
      );

      // The parent assert passes now; the pour then fails on the seam's
      // un-synthesized `data.ids` map — a DIFFERENT, acknowledged gap, and
      // never an ownership refusal.
      await expectLater(
        dry.writer.createMolecule(
          plan,
          substation: 'tgstate',
          sessionId: id,
          rootCrumbs: ['proj-1', id],
        ),
        throwsA(isA<BdParseException>()),
      );
      expect(dry.refusals, isEmpty);
    });

    test('a dry assembly mints its session under the state partition and '
        'refuses nothing to the operator', () async {
      final tmp = Directory.systemTemp.createTempSync('tg-czsf-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _seedStore('${tmp.path}/proj', database: 'pow');
      _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
      final refusals = <String>[];

      final work = await assembleStationWork(
        stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
        substations: [
          SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj'),
        ],
        resolver: const _NullResolver(),
        dryRun: true,
        onRefusal: refusals.add,
      );
      addTearDown(work.shutdown);

      expect(work.stateSubstation, 'tgstate');

      final sessionId = await work.wiring.services.writer.createSession(
        substation: 'proj',
        title: 'grid session proj-1',
        workBeadId: 'proj-1',
      );

      expect(sessionId, startsWith('tgstate-'));
      expect(sessionId, isNot('dry-session'));
      expect(refusals, isEmpty);
    });
  });
}
