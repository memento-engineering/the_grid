// tg-b1t8 — the FRESH-status land gate, built by grid_sdk and INJECTED into
// grid_runtime's `StationGitService.land`, so a build whose bead was parked or
// closed mid-round pushes its branch but opens NO pull request.
//
// Offline: a scripted GitRunner answers every git call ok, the PR opener is
// grid_engine's recording `FakePrOpener` (engine_fakes.dart), and a mutable
// probe reader plays the owning store so the bead can be OPEN at mount and
// DEFERRED at push time. No git binary, no gh, no network.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/testing.dart' show FakePrOpener;
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _MutableReader implements BeadProbeReader {
  _MutableReader(Iterable<Bead> beads) : beads = beads.toList();

  List<Bead> beads;
  final List<String> reads = [];

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    reads.add(id);
    for (final bead in beads) {
      if (bead.id == id && types.contains(bead.issueType)) return bead;
    }
    return null;
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => const [];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];

  void setStatus(String id, BeadStatus status) {
    beads = [
      for (final bead in beads)
        bead.id == id ? bead.copyWith(status: status) : bead,
    ];
  }
}

/// Every git call succeeds — the land path's commit and push are not what is
/// under test here; the gate between the push and the PR is. The root-guard
/// probe (`rev-parse --show-toplevel --show-prefix`) is answered as if the
/// workDir were a work-tree root, so `GitOps` lets the commands through.
final class _OkGitRunner implements GitRunner {
  /// Every non-probe git call, in order.
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    if (args case ['rev-parse', '--show-toplevel', '--show-prefix']) {
      return GitRunResult(exitCode: 0, output: '$workingDirectory\n\n');
    }
    calls.add(List<String>.unmodifiable(args));
    return const GitRunResult(exitCode: 0, output: '');
  }
}

void main() {
  const root = RootCheckout(
    path: '/work/tg',
    defaultBranch: 'main',
    substation: 'tg',
  );
  const worktree = BeadWorktree(
    beadId: 'tg-1',
    path: '/work/tg/.grid/worktrees/tg/tg-1',
    branch: 'grid/tg-1',
  );

  group('buildWorkBeadLandGate', () {
    test(
      'answers from a read performed AT CALL TIME, never a snapshot',
      () async {
        final reader = _MutableReader(const [
          Bead(id: 'tg-1', issueType: IssueType.task),
        ]);
        final gate = buildWorkBeadLandGate(readerFor: (_) => reader);

        expect(await gate('tg-1'), isA<LandGateOpen>());
        reader.setStatus('tg-1', BeadStatus.deferred);
        final deferred = await gate('tg-1') as LandGateRefused;
        expect(deferred.status, 'deferred');
        expect(deferred.reason, 'only an open bead lands; tg-1 reads deferred');
        reader.setStatus('tg-1', BeadStatus.closed);
        expect((await gate('tg-1') as LandGateRefused).status, 'closed');
        reader.setStatus('tg-1', BeadStatus.open);
        expect(await gate('tg-1'), isA<LandGateOpen>());
        expect(reader.reads, hasLength(4), reason: 'one read per ask');
      },
    );

    test('an absent bead and an unowned bead both refuse', () async {
      final reader = _MutableReader(const []);
      final gate = buildWorkBeadLandGate(
        readerFor: (beadId) => beadId.startsWith('tg-') ? reader : null,
      );

      final absent = await gate('tg-9') as LandGateRefused;
      expect(absent.status, 'absent');
      expect(absent.reason, 'bead tg-9 is not in its store');
      final unowned = await gate('xx-1') as LandGateRefused;
      expect(unowned.status, 'unowned');
      expect(unowned.reason, 'no attached store owns bead xx-1');
    });

    test('COMPOSES the dispatchable-work clause: an open epic is not '
        'driveable, so it does not land', () async {
      final reader = _MutableReader(const [
        Bead(id: 'tg-2', issueType: IssueType.epic),
        Bead(id: 'tg-3', issueType: IssueType.bug),
      ]);
      final gate = buildWorkBeadLandGate(readerFor: (_) => reader);

      final epic = await gate('tg-2') as LandGateRefused;
      expect(epic.status, 'open but not driveable (epic)');
      expect(
        epic.reason,
        'issue type epic is not dispatchable for this substation',
      );
      expect(await gate('tg-3'), isA<LandGateOpen>());
    });
  });

  group('StationGitService.land with the injected gate', () {
    test('a bead open at mount and deferred at push time is committed and '
        'pushed but FakePrOpener.open is never called', () async {
      final reader = _MutableReader(const [
        Bead(id: 'tg-1', issueType: IssueType.task),
      ]);
      final git = _OkGitRunner();
      final pr = FakePrOpener();
      final service = StationGitService(
        runner: git,
        prOpener: pr,
        landGate: buildWorkBeadLandGate(readerFor: (_) => reader),
      );
      // Mount-time: open. (Nothing here consults this — the point.)
      expect(await reader.beadById('tg-1', types: {IssueType.task}), isNotNull);
      reader.setStatus('tg-1', BeadStatus.deferred);

      final result = await service.land(
        root: root,
        worktree: worktree,
        commitMessage: 'grid: tg-1',
        prTitle: 'grid/tg-1',
      );

      expect(pr.opened, isEmpty);
      expect(result.isLanded, isFalse);
      expect(result.committed, isTrue);
      expect(result.pushed, isTrue);
      expect(
        result.failureReason,
        'pr open refused: work bead tg-1 is deferred at push time — only an '
        'open bead lands; tg-1 reads deferred; no PR opened',
      );
      expect(git.calls, [
        ['add', '-A'],
        ['commit', '-m', 'grid: tg-1'],
        ['push', '-u', 'origin', 'grid/tg-1'],
      ]);
    });

    test('an open driveable bead lands: FakePrOpener.open is called once with '
        'the branch and base', () async {
      final reader = _MutableReader(const [
        Bead(id: 'tg-1', issueType: IssueType.task),
      ]);
      final pr = FakePrOpener();
      final service = StationGitService(
        runner: _OkGitRunner(),
        prOpener: pr,
        landGate: buildWorkBeadLandGate(readerFor: (_) => reader),
      );

      final result = await service.land(
        root: root,
        worktree: worktree,
        commitMessage: 'grid: tg-1',
        prTitle: 'grid/tg-1',
        prBody: 'body',
      );

      expect(result.isLanded, isTrue, reason: result.failureReason ?? '');
      expect(result.pr!.url, pr.url);
      final opened = pr.opened.single;
      expect(opened.branch, 'grid/tg-1');
      expect(opened.baseBranch, 'main');
      expect(opened.workDir, worktree.path);
      expect(opened.title, 'grid/tg-1');
      expect(opened.body, 'body');
    });

    test('a bead closed at push time is refused with status closed', () async {
      final reader = _MutableReader(const [
        Bead(id: 'tg-1', issueType: IssueType.task),
      ]);
      final pr = FakePrOpener();
      final service = StationGitService(
        runner: _OkGitRunner(),
        prOpener: pr,
        landGate: buildWorkBeadLandGate(readerFor: (_) => reader),
      );
      reader.setStatus('tg-1', BeadStatus.closed);

      final result = await service.land(
        root: root,
        worktree: worktree,
        commitMessage: 'm',
        prTitle: 't',
      );

      expect(pr.opened, isEmpty);
      expect(result.failureReason, contains('work bead tg-1 is closed'));
    });
  });
}
