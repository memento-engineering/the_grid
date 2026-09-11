/// A structural guard on the SOURCE ITSELF: no Dart file under any package's
/// `lib/` may carry a raw NUL byte (r12; widened to the WORKSPACE in r13).
///
/// This is not style. A literal U+0000 in a source file makes `file` classify
/// the whole file as binary `data`, and it makes plain `grep` return NOTHING
/// for that file — silently. Several guards in this very directory work by
/// reading and grepping sources; a NUL blinds them, and it blinds every
/// review and sweep besides. The escape (backslash-u-0000) has the identical string
/// value and none of the consequences, so the only cost of this rule is
/// remembering it — which is what this test is for.
///
/// THE SCOPE IS THE WORKSPACE, deliberately (r13). The hazard is not
/// package-local — a NUL anywhere blinds the same greps and the same sweeps —
/// and the first cut of this guard scanned only its own `lib/` while a live
/// offender sat in `grid_runtime`. If no workspace root can be located (a
/// vendored or single-package checkout) it falls back to this package's own
/// `lib/` rather than passing vacuously.
library;

import 'dart:io';

import 'package:test/test.dart';

/// The nearest ancestor holding a `packages/` directory — the pub workspace
/// root. Null when there is none.
Directory? _workspaceRoot() {
  var dir = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth += 1) {
    if (Directory('${dir.path}/packages').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return null;
}

List<Directory> _libRoots() {
  final root = _workspaceRoot();
  if (root == null) return [Directory('lib')];
  return [
    for (final entity in Directory('${root.path}/packages').listSync())
      if (entity is Directory && Directory('${entity.path}/lib').existsSync())
        Directory('${entity.path}/lib'),
  ];
}

void main() {
  test(
    'admission authority retains only documented non-snapshot collections',
    () {
      final workspace = _workspaceRoot();
      expect(workspace, isNotNull);
      final root = workspace!.path;
      final authority = File(
        '$root/packages/grid_engine/lib/src/kernel/station_admission_authority.dart',
      ).readAsStringSync();
      final workList = File(
        '$root/packages/grid_engine/lib/src/seeds/work_list.dart',
      ).readAsStringSync();
      final sessionScope = File(
        '$root/packages/grid_engine/lib/src/circuit/session_scope.dart',
      ).readAsStringSync();
      final amendment = File(
        '$root/docs/decisions/2026-09-04-admission-authority-in-process-cut.md',
      ).readAsStringSync();

      const removed = [
        '_mountAttemptsScheduled',
        '_mountEligibilityRechecks',
        '_trustRefusedReported',
        '_surplusRetiresScheduled',
        '_surplusAliveReported',
        '_sessionAmbiguityReported',
        '_rivalRetiresRequired',
        '_rivalCleanupsInFlight',
        '_gateSweepsScheduled',
        '_capacityWaitingSignature',
        '_scopeBySessionId',
        '_retryBlocked',
        '_scopeForSession',
      ];
      for (final name in removed) {
        expect(
          authority,
          isNot(contains(name)),
          reason: '$name must not suppress a current snapshot fact',
        );
      }

      const retained = {
        '_mountedIds',
        '_mountEligibilityRefusals',
        '_zeroAdmissionSinceByBead',
        '_scopes',
        '_reservations',
        '_lastScopeByBead',
        '_listeners',
        '_retryTimers',
        '_mountAttemptWrites',
        '_blockedUntilFreshReady',
      };
      final declaredCollections = RegExp(
        r'final\s+(?:Set|Map|List)<[^;]+?>\s+(_[A-Za-z0-9]+)\s*=',
      ).allMatches(authority).map((match) => match.group(1)!).toSet();
      expect(declaredCollections, retained);

      const rationaleByCollection = {
        '_mountedIds': 'Structural branch membership',
        '_mountEligibilityRefusals': 'Refusal timing and restoration history',
        '_zeroAdmissionSinceByBead': 'First-observed zero-admission timing',
        '_scopes': 'Per-substation branch and status state',
        '_reservations': 'durable session rows appear',
        '_lastScopeByBead': 'Bare bead ids on async entry points',
        '_listeners': 'Registered station consumers',
        '_retryTimers': 'Live backoff operations',
        '_mountAttemptWrites': 'Writes not yet represented by JoinedSnapshot',
        '_blockedUntilFreshReady': 'Cancellation quarantine persists',
      };
      for (final entry in rationaleByCollection.entries) {
        expect(
          authority,
          matches(
            RegExp(
              '//[^\n]*${RegExp.escape(entry.value)}[^\n]*\n'
              '\\s*final[^;]+${RegExp.escape(entry.key)}\\s*=',
            ),
          ),
          reason: '${entry.key} needs an adjacent non-snapshot rationale',
        );
      }
      expect(authority, contains('Stage 3 exclusively owns retirement'));
      expect(
        authority,
        contains(
          'This is not that switch; every bead write and flare remains.',
        ),
      );
      expect(authority, contains('run level-triggered on each pass'));
      expect(authority, contains('_scopeForBead'));
      expect(workList, isNot(contains('_scopeForBead')));
      final statusStart = authority.indexOf(
        'final class StationAdmissionStatus',
      );
      final statusEnd = authority.indexOf(
        '/// A work bead and the session projection',
        statusStart,
      );
      expect(statusStart, greaterThanOrEqualTo(0));
      expect(statusEnd, greaterThan(statusStart));
      expect(
        authority.substring(statusStart, statusEnd),
        isNot(contains('set ')),
        reason: 'the public admission snapshot has no mutable setter surface',
      );
      for (final authorityOnly in ['_scheduleRivalCleanup']) {
        expect(
          authority,
          contains(authorityOnly),
          reason: '$authorityOnly stays behind the admission owner',
        );
        expect(workList, isNot(contains(authorityOnly)));
        expect(sessionScope, isNot(contains(authorityOnly)));
      }
      expect(authority, contains("listRunning('\$rivalId/')"));
      expect(workList, isNot(contains('listRunning(')));
      expect(sessionScope, isNot(contains('listRunning(')));
      for (final incumbent in [
        'recordMountAttempt',
        'voidKeyFor',
        'voidRetireMetadata',
        'grid.voided_reason',
      ]) {
        expect(authority, contains(incumbent));
      }
      expect(workList, isNot(contains('recordMountAttempt')));

      const directAttemptCalls = [
        'writer.recordMountAttempt(',
        'writer.createSession(',
        'writer.createMolecule(',
        'writer.closeSessionAndOpenGatesForTerminal(',
        'writer.closeOpenGatesForTerminal(',
        'writer.close(',
      ];
      for (final call in directAttemptCalls) {
        expect(workList, isNot(contains(call)));
        expect(sessionScope, isNot(contains(call)));
      }
      for (final retainedExecution in [
        'createStepSuccessor',
        'parkSessionAtGate',
        'stepRearmed',
        'worktreeReaped',
        'sessionMinted',
      ]) {
        expect(sessionScope, contains(retainedExecution));
      }

      for (final retiredFlare in [
        'work.sessionRivalAlive',
        'work.sessionAmbiguous',
        'work.sessionRivalRetireFailed',
      ]) {
        for (final libRoot in _libRoots()) {
          for (final entity in libRoot.listSync(recursive: true)) {
            if (entity is! File || !entity.path.endsWith('.dart')) continue;
            expect(
              entity.readAsStringSync(),
              isNot(contains(retiredFlare)),
              reason: entity.path,
            );
          }
        }
      }

      for (final stage3Only in [
        'grid_trajectory',
        'AdmissionGrantIssued',
        'AdmissionGrantConsumed',
        'AdmissionGrantClosed',
        'AdmissionRefused',
        'AdmissionRestored',
        'grantId',
        'authorityId',
        'reservationId',
        'fencingToken',
        'leaseId',
        'expiry',
        'expiresAt',
        'decisionBasis',
        '.append(',
      ]) {
        expect(authority, isNot(contains(stage3Only)));
      }
      for (final treePrimitive in [
        'TreeContext',
        'InheritedModelSeed',
        'package:genesis_tree/',
        'package:tree/',
        'dependOn',
      ]) {
        expect(
          authority,
          isNot(contains(treePrimitive)),
          reason: '$treePrimitive must not enter the station-lifetime owner',
        );
      }
      expect(
        amendment,
        contains('updates: ["the_grid#admission-authority-boundary"]'),
      );
      expect(amendment, contains('retains the supported'));
      expect(amendment, contains('synchronous offline fallback'));
      expect(amendment, contains('under `kDefaultMaxConcurrentWork`'));
      expect(amendment, contains('belongs exclusively to tg-lt0s'));
    },
  );

  test('no lib/ source in the WORKSPACE carries a raw NUL byte — the escape, '
      'always', () {
    final roots = _libRoots();
    expect(roots, isNotEmpty, reason: 'the guard must scan something');
    final offenders = <String>[];
    for (final root in roots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsBytesSync().contains(0)) offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a literal U+0000 makes `grep` silently skip the file and every '
          'source-reading guard in this suite blind to it — write \\u0000',
    );
  });
}
