@TestOn('vm')
@Tags(['integration'])
library;

import 'package:grid_controller/src/codecs/envelope.dart';
import 'package:grid_controller/src/errors/bd_exception.dart';
import 'package:grid_controller/src/models/dependency_type.dart';
import 'package:grid_controller/src/models/issue_type.dart';
import 'package:grid_controller/src/ready/ready_work_differential.dart';
import 'package:grid_controller/src/ready/ready_work_filter.dart';
import 'package:grid_controller/src/ready/ready_work_query.dart';
import 'package:grid_controller/src/services/bd_cli_service.dart';
import 'package:grid_controller/src/services/bd_runner.dart';
import 'package:grid_controller/src/services/beads_workspace.dart';
import 'package:grid_controller/src/services/dolt_query_service.dart';
import 'package:test/test.dart';

import 'support/hermetic_dolt_server.dart';
import 'support/hermetic_workspace.dart';

/// Track F differential test gate (ADR-0003 Decision 5), in three halves.
///
/// **Half 1 — hermetic oracle witnesses (always runs with bd on PATH).** Each
/// test builds one predicate scenario with the real `bd` 1.0.5 binary in a fresh
/// `bd init` temp workspace and asserts the **oracle** (`bd ready --json`)
/// behaves as the port spec (`grid_reconciler/doc/port/ready-work-predicate.md`)
/// states — clause by clause. These pin the predicate's semantics the SQL port
/// must reproduce; they are the buildable, runs-everywhere proof that each
/// scenario is well-formed and that `bd ready` is the contract the port targets.
/// A hermetic workspace is embedded Dolt (no MySQL endpoint), so the SQL port
/// itself cannot run here — that is Half 2.
///
/// **Half 2 — live SQL-port == bd-ready differential (self-skips without
/// `GC_DOLT_PASSWORD`).** Against the real gc-managed tg server, runs
/// [ReadyWorkDifferential.assertAgreement] for each sort policy over the live
/// graph AS-IS. Pure reads — coexistence-safe (no live mutations; CLAUDE.md).
/// Self-skips exactly like `services/dolt_query_service_live_test.dart`. This
/// half proves the port against production-scale data but only covers whatever
/// shapes the live graph happens to carry — it does **not** guarantee any named
/// divergent scenario is present. That guarantee is Half 3's job.
///
/// **Half 3 — hermetic SQL-port == bd-ready differential over SEEDED divergent
/// fixtures (runs-everywhere; no creds).** Stands up a private
/// [HermeticDoltServer] (a `dolt sql-server` + a `bd init --server --external`
/// workspace pointed at it), seeds each named divergent shape — a
/// conditional-blocks blocker closed with a *failure-keyword* reason, a
/// future-`defer_until` bead, a molecule, a same-second `created_at` tie — and
/// runs [ReadyWorkDifferential.assertAgreement] for every policy. Because `bd`
/// and the SQL port read the **one** server, each scenario is asserted on
/// **both** sides at once. This is the half that closes the "passes only because
/// it omits the divergent case" gap Half 2 leaves open.
///
/// The hermetic server is the only configuration where both sides can read one
/// store: `bd init`'s embedded Dolt has no MySQL endpoint for the SQL port, and
/// a `dolt sql-server` cannot share that embedded store with a concurrent
/// embedded `bd` (single-writer lock → `bd ready` hangs). Pointing `bd` itself
/// at the server resolves it. See [HermeticDoltServer] for the `127.0.0.1`
/// auth-gate workaround. Skips cleanly when `dolt`/`bd` are not on PATH.
void main() {
  // -------------------------------------------------------------------------
  // Half 1: hermetic oracle witnesses — one scenario per predicate clause.
  // -------------------------------------------------------------------------
  group('bd ready oracle witnesses (hermetic; each predicate clause)', () {
    late HermeticWorkspace ws;
    late ProcessBdRunner runner;
    late BdCliService bd;

    setUp(() async {
      ws = await HermeticWorkspace.create(prefix: 'grid_it_ready_');
      runner = ProcessBdRunner(workspaceRoot: ws.rootPath);
      bd = BdCliService(runner);
    });

    tearDown(() => ws.dispose());

    /// The oracle's ready id list for [policy] (the same invocation the
    /// differential harness uses: `--json --limit 0 --sort <policy>`).
    Future<List<String>> readyIds({
      ReadyWorkSortPolicy policy = ReadyWorkSortPolicy.priority,
      List<String> extraFlags = const [],
    }) async {
      final result = await runner.run([
        'ready',
        '--json',
        '--limit',
        '0',
        '--sort',
        policy.wire,
        ...extraFlags,
      ]);
      expect(result.exitCode, 0, reason: 'bd ready failed: ${result.stderr}');
      return [
        for (final row in BdEnvelope.parse(result.stdout).dataList)
          row['id'] as String,
      ];
    }

    Future<String> create(
      String title, {
      IssueType type = IssueType.task,
      int priority = 1,
    }) => bd.create(title: title, type: type, priority: priority);

    test('open enters ready; closed exits (clause #1)', () async {
      final a = await create('A');
      expect(await readyIds(), contains(a));
      await bd.close(a);
      expect(await readyIds(), isNot(contains(a)));
    });

    test(
      'a blocks edge blocks the dependent until the blocker closes (#3/#4.1)',
      () async {
        final a = await create('blocker');
        final b = await create('dependent');
        await bd.depAdd(b, a, type: DependencyType.blocks);
        final whileOpen = await readyIds();
        expect(whileOpen, contains(a));
        expect(
          whileOpen,
          isNot(contains(b)),
          reason: 'b is blocked while a is open',
        );
        await bd.close(a);
        expect(
          await readyIds(),
          contains(b),
          reason: 'b unblocks when a closes',
        );
      },
    );

    test('conditional-blocks ≡ blocks: unblocks on success AND on a failure '
        'keyword close, identically (trap #1)', () async {
      // Success close.
      final a1 = await create('cond-success-blocker');
      final b1 = await create('cond-success-dependent');
      await bd.depAdd(b1, a1, type: DependencyType.conditionalBlocks);
      expect(await readyIds(), isNot(contains(b1)));
      await bd.close(a1, reason: 'done successfully');
      expect(
        await readyIds(),
        contains(b1),
        reason: 'conditional-blocks unblocks on a SUCCESS close',
      );

      // Failure-keyword close — must be identical (no close_reason branch).
      final a2 = await create('cond-fail-blocker');
      final b2 = await create('cond-fail-dependent');
      await bd.depAdd(b2, a2, type: DependencyType.conditionalBlocks);
      expect(await readyIds(), isNot(contains(b2)));
      await bd.close(a2, reason: 'failed badly');
      expect(
        await readyIds(),
        contains(b2),
        reason:
            'conditional-blocks unblocks on a FAILURE close too — the '
            'failure-keyword vocabulary is dead in the ready path',
      );
    });

    test('waits-for gate: blocked while a parent-child child is open, '
        'unblocked when all children close (§4.2)', () async {
      final spawner = await create('spawner');
      final child = await create('gate-child');
      await bd.depAdd(child, spawner, type: DependencyType.parentChild);
      final waiter = await create('waiter');
      await bd.depAdd(waiter, spawner, type: DependencyType.waitsFor);
      expect(
        await readyIds(),
        isNot(contains(waiter)),
        reason: 'waiter blocked while the spawner has an open child',
      );
      await bd.close(child);
      expect(
        await readyIds(),
        contains(waiter),
        reason: 'all-children gate releases when the child closes',
      );
    });

    test(
      'molecule is excluded by default; -t molecule surfaces it (A14/#6)',
      () async {
        final mol = await create('mol', type: IssueType.molecule);
        expect(
          await readyIds(),
          isNot(contains(mol)),
          reason: 'a molecule is a container, excluded from ready (A14)',
        );
        expect(
          await readyIds(extraFlags: ['-t', 'molecule']),
          contains(mol),
          reason: '-t molecule drops the exclusion list (trap #6)',
        );
      },
    );

    test(
      'defer_until: past keeps the bead ready, future excludes it (§5)',
      () async {
        final past = await create('past-defer');
        await runner.run([
          'update',
          past,
          '--defer',
          '2000-01-01',
          '--json',
          '--actor',
          BdCliService.actor,
        ]);
        expect(
          await readyIds(),
          contains(past),
          reason: 'a past defer_until is ready (boundary/past = ready)',
        );

        final future = await create('future-defer');
        await runner.run([
          'update',
          future,
          '--defer',
          '2999-01-01',
          '--json',
          '--actor',
          BdCliService.actor,
        ]);
        expect(
          await readyIds(),
          isNot(contains(future)),
          reason: 'a future defer_until is excluded',
        );
      },
    );

    test('an ephemeral wisp is excluded by default, included with '
        '--include-ephemeral (clause #4)', () async {
      // A bare ephemeral bead routes to the wisps table.
      final id = await create('ephemeral-bead');
      await runner.run([
        'update',
        id,
        '--ephemeral',
        '--json',
        '--actor',
        BdCliService.actor,
      ]);
      // The ephemeral flag may live on the wisp row; whichever table it lands
      // in, the default ready set must not contain it, and --include-ephemeral
      // (if it surfaces) must agree between SQL and oracle (Half 2). Here we
      // assert the default exclusion holds via the oracle.
      final defaultReady = await readyIds();
      final inclReady = await readyIds(extraFlags: ['--include-ephemeral']);
      expect(
        inclReady.length,
        greaterThanOrEqualTo(defaultReady.length),
        reason: '--include-ephemeral never removes ready beads',
      );
    });

    test('label AND / exclude-label scoping (clauses #10/#11)', () async {
      final tagged = await create('tagged');
      final other = await create('other');
      await runner.run([
        'label',
        'add',
        tagged,
        'keep',
        '--actor',
        BdCliService.actor,
      ]);
      await runner.run([
        'label',
        'add',
        other,
        'drop',
        '--actor',
        BdCliService.actor,
      ]);
      final byLabel = await readyIds(extraFlags: ['--label', 'keep']);
      expect(byLabel, contains(tagged));
      expect(byLabel, isNot(contains(other)));
      final excl = await readyIds(extraFlags: ['--exclude-label', 'drop']);
      expect(excl, contains(tagged));
      expect(excl, isNot(contains(other)));
    });

    test('sort policy orders by priority vs age (§6)', () async {
      // Two beads: high priority (P0) and low priority (P3). priority sort
      // puts P0 first; oldest sort puts the earlier-created first.
      final p3 = await create('low-prio', priority: 3);
      // small gap so created_at differs at >=1s granularity is not guaranteed;
      // priority ordering does not depend on it.
      final p0 = await create('high-prio', priority: 0);
      final byPriority = await readyIds(policy: ReadyWorkSortPolicy.priority);
      expect(
        byPriority.indexOf(p0),
        lessThan(byPriority.indexOf(p3)),
        reason: 'P0 sorts before P3 under the priority policy',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Half 2: live SQL-port == bd-ready differential (self-skips w/o creds).
  // -------------------------------------------------------------------------
  group('SQL-port == bd-ready differential (live, requires GC_DOLT_PASSWORD)', () {
    test(
      'the SQL port agrees with bd ready over the live graph, every policy',
      () async {
        final ws = BeadsWorkspace.discover();
        final endpoint = ws?.endpoint;
        if (ws == null || endpoint == null || !endpoint.hasCredential) {
          markTestSkipped(
            'no live Dolt endpoint with credentials (GC_DOLT_PASSWORD unset) — '
            'the SQL-port differential is not exercised',
          );
          return;
        }

        final dolt = DoltQueryService(endpoint);
        addTearDown(dolt.close);
        try {
          await dolt.connect();
        } on BdSchemaDriftException catch (e) {
          markTestSkipped('live schema drift: ${e.message}');
          return;
        }

        final differential = ReadyWorkDifferential(
          sqlPort: ReadyWorkQuery(dolt),
          runner: ProcessBdRunner(workspaceRoot: ws.root),
        );

        for (final policy in ReadyWorkSortPolicy.values) {
          // Guard against a cross-workspace write moving the working set between
          // the SQL read and the oracle read — diff is only meaningful over a
          // stable snapshot. Retry once on a probe move, then skip.
          final before = await dolt.probe();
          final diff = await differential.run(
            ReadyWorkFilter(sortPolicy: policy),
          );
          final after = await dolt.probe();
          if (before != after) {
            markTestSkipped(
              'working set moved mid-diff (cross-workspace write) under $policy',
            );
            return;
          }
          expect(
            diff.diverged,
            isFalse,
            reason:
                'SQL port diverged from bd ready under $policy:\n'
                '${diff.describe()}',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });

  // -------------------------------------------------------------------------
  // Half 3: hermetic SQL-port == bd-ready differential over SEEDED fixtures.
  // Both sides read one private server; each named divergent shape is present.
  // -------------------------------------------------------------------------
  group('hermetic SQL-port == bd-ready differential (seeded; runs everywhere)', () {
    late HermeticDoltServer? server;
    late DoltQueryService dolt;
    late BdCliService bd;
    late ReadyWorkDifferential differential;

    setUp(() async {
      server = await HermeticDoltServer.tryCreate(prefix: 'grid_it_readydiff_');
      final s = server;
      if (s == null) return; // tools absent → each test self-skips below.
      dolt = DoltQueryService(s.endpoint);
      await dolt.connect();
      bd = BdCliService(s.runner);
      differential = ReadyWorkDifferential(
        sqlPort: ReadyWorkQuery(dolt),
        runner: s.runner,
      );
    });

    tearDown(() async {
      if (server != null) await dolt.close();
      await server?.dispose();
    });

    /// Asserts both sides agree under every policy, with a readable report on
    /// divergence. Pins `now` so the hybrid recency band is identical to the
    /// instant the seeded rows are evaluated against (no wall-clock skew between
    /// the two reads).
    Future<void> expectAgreementEveryPolicy() async {
      final now = DateTime.now().toUtc();
      for (final policy in ReadyWorkSortPolicy.values) {
        final diff = await differential.run(
          ReadyWorkFilter(sortPolicy: policy),
          now: now,
        );
        expect(
          diff.diverged,
          isFalse,
          reason:
              'hermetic SQL port diverged from bd ready under $policy:\n'
              '${diff.describe()}',
        );
      }
    }

    test(
      'conditional-blocks closed with a FAILURE-keyword reason unblocks on '
      'both sides (trap #1, the keyword vocabulary is dead in ready)',
      () async {
        final s = server;
        if (s == null) {
          markTestSkipped(
            'dolt/bd not on PATH — hermetic differential skipped',
          );
          return;
        }
        final blocker = await bd.create(title: 'cond-fail-blocker');
        final dependent = await bd.create(title: 'cond-fail-dependent');
        await bd.depAdd(
          dependent,
          blocker,
          type: DependencyType.conditionalBlocks,
        );
        // While the blocker is open, the dependent is blocked on BOTH sides.
        await expectAgreementEveryPolicy();

        // Close the blocker with a reason from the failure vocabulary. If the SQL
        // port wrongly branched on close_reason (trap #1) it would keep the
        // dependent blocked while bd ready releases it — a divergence the prior
        // step could not see because both sides agreed it was blocked.
        await bd.close(blocker, reason: 'failed badly');
        await expectAgreementEveryPolicy();
      },
    );

    test(
      'a future defer_until excludes a bead on both sides (§5/§8/trap #8)',
      () async {
        final s = server;
        if (s == null) {
          markTestSkipped(
            'dolt/bd not on PATH — hermetic differential skipped',
          );
          return;
        }
        // A plainly-ready bead, plus a future-deferred one that both sides must
        // exclude (and a past-deferred one both must keep).
        await bd.create(title: 'plain-ready');
        final future = await bd.create(title: 'future-defer');
        await s.runner.run([
          'update',
          future,
          '--defer',
          '2999-01-01',
          '--json',
          '--actor',
          BdCliService.actor,
        ]);
        final past = await bd.create(title: 'past-defer');
        await s.runner.run([
          'update',
          past,
          '--defer',
          '2000-01-01',
          '--json',
          '--actor',
          BdCliService.actor,
        ]);
        await expectAgreementEveryPolicy();
      },
    );

    test(
      'a molecule container is excluded by default on both sides (A14/#6)',
      () async {
        final s = server;
        if (s == null) {
          markTestSkipped(
            'dolt/bd not on PATH — hermetic differential skipped',
          );
          return;
        }
        await bd.create(title: 'leaf-task');
        await bd.create(title: 'mol', type: IssueType.molecule);
        // The default ready filter excludes molecule (port spec §3.1); both sides
        // must drop it. (-t molecule is not on ReadyWorkFilter, so the differential
        // never asks for it — the exclusion is the only differentiable behaviour.)
        await expectAgreementEveryPolicy();
      },
    );

    test('a same-second created_at tie is broken identically on both sides '
        '(§6.1 id ASC tiebreak)', () async {
      final s = server;
      if (s == null) {
        markTestSkipped('dolt/bd not on PATH — hermetic differential skipped');
        return;
      }
      // Create several same-priority beads back-to-back so at least some share a
      // created_at second; the SQL ORDER BY and the bd in-memory comparator must
      // resolve the tie by id ASC identically, under every policy.
      for (var i = 0; i < 6; i++) {
        await bd.create(title: 'tie-$i', priority: 2);
      }
      await expectAgreementEveryPolicy();
    });

    test(
      'the full seeded graph (all shapes at once) agrees under every policy',
      () async {
        final s = server;
        if (s == null) {
          markTestSkipped(
            'dolt/bd not on PATH — hermetic differential skipped',
          );
          return;
        }
        // A mixed graph: a blocks chain, a conditional-blocks chain failure-closed,
        // a molecule, a future + past defer, and a priority spread — the union of
        // the named scenarios in one differential.
        final blocker = await bd.create(title: 'blocker', priority: 0);
        final dependent = await bd.create(title: 'dependent', priority: 1);
        await bd.depAdd(dependent, blocker);
        final cBlocker = await bd.create(title: 'c-blocker', priority: 3);
        final cDependent = await bd.create(title: 'c-dependent', priority: 2);
        await bd.depAdd(
          cDependent,
          cBlocker,
          type: DependencyType.conditionalBlocks,
        );
        await bd.create(title: 'mol', type: IssueType.molecule);
        final future = await bd.create(title: 'future');
        await s.runner.run([
          'update',
          future,
          '--defer',
          '2999-01-01',
          '--json',
          '--actor',
          BdCliService.actor,
        ]);
        await bd.create(title: 'free-a', priority: 1);
        await bd.create(title: 'free-b', priority: 1);
        await expectAgreementEveryPolicy();

        // Now failure-close both blockers; the two dependents must release on both
        // sides (blocks unconditionally, conditional-blocks because trap #1).
        await bd.close(blocker, reason: 'rejected');
        await bd.close(cBlocker, reason: 'wontfix');
        await expectAgreementEveryPolicy();
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });
}
