// Track C2 — the critic capability (one rubric, in isolation).
//
// `code-validation` is the GATING lane: it runs the bead's OWN Validation Plan
// via `sh`, capturing the plan's exit code so the step always `complete`s and
// the grade (A iff zero, else F) rides `result()`. The three LLM lanes spawn
// `claude` with ONLY their own rubric (anti-anchoring) and write a verdict JSON
// `result()` parses. Zero I/O — no real `claude`/`sh`: the spawn config is
// inspected directly and `result()` reads files a test writes into a temp dir.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

CapabilityContext _ctx({
  required String rubric,
  String workspaceDir = '/w/tg-1',
  Bead? beadOverride,
  String? nodePath,
}) => CapabilityContext(
  params: {'rubric': rubric},
  bead: beadOverride ?? bead('tg-1'),
  workspaceDir: workspaceDir,
  branch: 'grid/tg-1',
  baseBranch: 'main',
  services: const ServiceBundle(),
  cancel: CancelToken(),
  nodePath: nodePath ?? 'tg-1/review/$rubric',
);

void main() {
  group('Track C2 — code-validation (the GATING lane)', () {
    test('spawns `sh -c` running the bead\'s Validation Plan, capturing its rc',
        () {
      final withPlan = bead('tg-1').copyWith(
        metadata: const {'validation_plan': 'melos analyze && melos test'},
      );
      final cfg = const CriticCapability()
          .spawn(_ctx(rubric: kGatingRubric, beadOverride: withPlan));
      expect(cfg.command, 'sh');
      expect(cfg.args[0], '-c');
      expect(cfg.args[1], contains('melos analyze && melos test'));
      // The rc is captured to the critique dir so result() can read the grade.
      expect(cfg.args[1], contains('.grid/critique/code-validation.rc'));
      expect(cfg.args[1], contains(r'echo $?'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
    });

    test('a plan-less bead defaults to an explicit `false` (never silently '
        'passes)', () {
      final cfg = const CriticCapability().spawn(_ctx(rubric: kGatingRubric));
      // `( false )` ⇒ a non-zero rc ⇒ result() grades F.
      expect(cfg.args[1], contains('( false )'));
    });

    test('ANY terminal exit completes the gating step (the grade rides '
        'result()); a death fails', () {
      const cap = CriticCapability();
      const name = 'tgdog-s/tg-1/review/code-validation';
      expect(
        cap.interpretEvent(const Exited(name: name, exitCode: 0)),
        StepSignal.complete,
      );
      // A non-zero plan still COMPLETES (the route decides via the F grade) —
      // not `failed`, so there is no retry storm on a deterministic failure.
      expect(
        cap.interpretEvent(const Exited(name: name, exitCode: 1)),
        StepSignal.complete,
      );
      expect(
        cap.interpretEvent(const Died(name: name)),
        StepSignal.failed,
      );
    });

    test('result() grades A on rc 0, F on a non-zero rc, F when the rc is '
        'absent (fail-closed)', () async {
      final dir = Directory.systemTemp.createTempSync('critic-gate-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const cap = CriticCapability();

      // Absent rc ⇒ fail-closed F.
      expect(await cap.result(_ctx(rubric: kGatingRubric, workspaceDir: dir.path)),
          {'grade': 'F'});

      // rc "0" ⇒ A.
      final rcFile = File('${dir.path}/.grid/critique/code-validation.rc')
        ..createSync(recursive: true)
        ..writeAsStringSync('0\n');
      expect(await cap.result(_ctx(rubric: kGatingRubric, workspaceDir: dir.path)),
          {'grade': 'A'});

      // rc non-zero ⇒ F.
      rcFile.writeAsStringSync('1\n');
      expect(await cap.result(_ctx(rubric: kGatingRubric, workspaceDir: dir.path)),
          {'grade': 'F'});
    });
  });

  group('Track C2 — the LLM critics (one rubric each, isolated)', () {
    test('spawns `claude --dangerously-skip-permissions -p <prompt>` in the '
        'workspace', () {
      final cfg = const CriticCapability().spawn(_ctx(rubric: 'spec-adherence'));
      expect(cfg.command, 'claude');
      expect(cfg.args[0], '--dangerously-skip-permissions');
      expect(cfg.args[1], '-p');
      expect(cfg.args[2], contains('spec-adherence'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
    });

    test('a clean exit completes; a non-zero exit / death fails', () {
      const cap = CriticCapability();
      const name = 'tgdog-s/tg-1/review/spec-adherence';
      expect(cap.interpretEvent(const Exited(name: name, exitCode: 0)),
          StepSignal.complete);
      expect(cap.interpretEvent(const Exited(name: name, exitCode: 2)),
          StepSignal.failed);
      expect(cap.interpretEvent(const Died(name: name)), StepSignal.failed);
    });

    test('the prompt names ONLY its own rubric (anti-anchoring)', () {
      final prompt =
          const CriticCapability().buildCriticPrompt(_ctx(rubric: 'spec-adherence'));
      expect(prompt, contains('spec-adherence'));
      // The other lanes' concerns must NOT leak into this critic's prompt.
      expect(prompt, isNot(contains('regression-risk')));
      expect(prompt, isNot(contains('test-coverage')));
      expect(prompt, isNot(contains('code-validation')));
      // It carries the verdict-file instruction for its own rubric only.
      expect(prompt, contains('.grid/critique/spec-adherence.json'));
    });

    test('the prompt carries the full bead', () {
      final rich = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        description: 'Connect The Studio to The Dashboard.',
        design: 'A lossy inter-station gossip bus.',
      );
      final prompt = const CriticCapability()
          .buildCriticPrompt(_ctx(rubric: 'test-coverage', beadOverride: rich));
      expect(prompt, contains('Wire the federation bus'));
      expect(prompt, contains('Connect The Studio to The Dashboard.'));
      expect(prompt, contains('A lossy inter-station gossip bus.'));
    });

    test('result() parses a written verdict JSON into a grade + rationale', () async {
      final dir = Directory.systemTemp.createTempSync('critic-llm-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/.grid/critique/regression-risk.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'rubric': 'regression-risk',
          'version': 1,
          'grade': 'b',
          'rationale': 'a narrow blast radius',
        }));
      final out = await const CriticCapability().result(
        _ctx(rubric: 'regression-risk', workspaceDir: dir.path),
      );
      expect(out, {'grade': 'B', 'rationale': 'a narrow blast radius'});
    });

    test('result() fail-closes to F on a missing or malformed verdict', () async {
      final dir = Directory.systemTemp.createTempSync('critic-llm-bad-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const cap = CriticCapability();
      // Missing verdict ⇒ F.
      expect(await cap.result(_ctx(rubric: 'test-coverage', workspaceDir: dir.path)),
          {'grade': 'F'});
      // Malformed verdict ⇒ F.
      File('${dir.path}/.grid/critique/test-coverage.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('not json');
      expect(await cap.result(_ctx(rubric: 'test-coverage', workspaceDir: dir.path)),
          {'grade': 'F'});
    });

    test('an injected rubric source replaces the inline placeholder', () {
      final cap = CriticCapability(
        rubrics: (id) => 'CUSTOM BANDS for $id',
      );
      final prompt = cap.buildCriticPrompt(_ctx(rubric: 'spec-adherence'));
      expect(prompt, contains('CUSTOM BANDS for spec-adherence'));
      expect(prompt, isNot(contains('Packaged-AI-Asset loader')));
    });
  });
}
