import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

/// Every gate/trigger/terminal/waiting/verdict value domain asserted against
/// HARDCODED wire strings with their gascity/internal/convergence source
/// lines — never against the code's own constants.
void main() {
  group('GateMode (metadata.go:66-70)', () {
    test('wire literals', () {
      expect(GateMode.manual.wire, 'manual'); // metadata.go:67
      expect(GateMode.condition.wire, 'condition'); // metadata.go:68
      expect(GateMode.hybrid.wire, 'hybrid'); // metadata.go:69
      expect(GateMode.values, hasLength(3));
    });

    test('default is manual (gate.go:46-48, create.go:55-57)', () {
      expect(GateMode.defaultMode, GateMode.manual);
    });

    test('fromWire rejects out-of-set values (gate.go:50-55)', () {
      expect(GateMode.fromWire('manual'), GateMode.manual);
      expect(GateMode.fromWire('condition'), GateMode.condition);
      expect(GateMode.fromWire('hybrid'), GateMode.hybrid);
      expect(GateMode.fromWire('Manual'), isNull);
      expect(GateMode.fromWire('auto'), isNull);
      expect(GateMode.fromWire(''), isNull);
    });
  });

  group('GateOutcome (metadata.go:89-94)', () {
    test('wire literals', () {
      expect(GateOutcome.pass.wire, 'pass'); // metadata.go:90
      expect(GateOutcome.fail.wire, 'fail'); // metadata.go:91
      expect(GateOutcome.timeout.wire, 'timeout'); // metadata.go:92
      expect(GateOutcome.error.wire, 'error'); // metadata.go:93
      expect(GateOutcome.values, hasLength(4));
    });

    test('fromWire rejects out-of-set values', () {
      expect(GateOutcome.fromWire('pass'), GateOutcome.pass);
      expect(GateOutcome.fromWire('fail'), GateOutcome.fail);
      expect(GateOutcome.fromWire('timeout'), GateOutcome.timeout);
      expect(GateOutcome.fromWire('error'), GateOutcome.error);
      expect(GateOutcome.fromWire('passed'), isNull);
      expect(GateOutcome.fromWire('PASS'), isNull);
    });
  });

  group('GateTimeoutAction (metadata.go:73-78)', () {
    test('wire literals', () {
      expect(GateTimeoutAction.iterate.wire, 'iterate'); // metadata.go:74
      expect(GateTimeoutAction.retry.wire, 'retry'); // metadata.go:75
      expect(GateTimeoutAction.manual.wire, 'manual'); // metadata.go:76
      expect(GateTimeoutAction.terminate.wire, 'terminate'); // metadata.go:77
      expect(GateTimeoutAction.values, hasLength(4));
    });

    test(
      'default action is iterate; retry budget 3 (gate.go:69, gate.go:14)',
      () {
        expect(GateTimeoutAction.defaultAction, GateTimeoutAction.iterate);
        expect(GateTimeoutAction.maxGateRetries, 3);
      },
    );

    test('fromWire rejects out-of-set values (gate.go:70-77)', () {
      expect(GateTimeoutAction.fromWire('iterate'), GateTimeoutAction.iterate);
      expect(GateTimeoutAction.fromWire('retry'), GateTimeoutAction.retry);
      expect(GateTimeoutAction.fromWire('manual'), GateTimeoutAction.manual);
      expect(
        GateTimeoutAction.fromWire('terminate'),
        GateTimeoutAction.terminate,
      );
      expect(GateTimeoutAction.fromWire('stop'), isNull);
    });
  });

  group('TriggerMode (metadata.go:60-63)', () {
    test('none IS the empty string; event is "event"', () {
      expect(TriggerMode.none.wire, ''); // metadata.go:61 — TriggerNone = ""
      expect(TriggerMode.event.wire, 'event'); // metadata.go:62
      expect(TriggerMode.values, hasLength(2));
      expect(TriggerMode.none.enabled, isFalse); // trigger.go:19-21
      expect(TriggerMode.event.enabled, isTrue);
    });
  });

  group('TerminalReason (metadata.go:81-86)', () {
    test('canonical wire literals', () {
      expect(TerminalReason.approved.wire, 'approved'); // metadata.go:82
      expect(
        TerminalReason.noConvergence.wire,
        'no_convergence', // metadata.go:83
      );
      expect(TerminalReason.stopped.wire, 'stopped'); // metadata.go:84
      expect(
        TerminalReason.partialCreation.wire,
        'partial_creation', // metadata.go:85
      );
    });

    test('open set: unknown values flow through unharmed', () {
      expect(const TerminalReason('custom_reason').wire, 'custom_reason');
    });
  });

  group('WaitingReason (metadata.go:97-102)', () {
    test('canonical wire literals', () {
      expect(WaitingReason.manual.wire, 'manual'); // metadata.go:98
      expect(
        WaitingReason.hybridNoCondition.wire,
        'hybrid_no_condition', // metadata.go:99
      );
      expect(WaitingReason.timeout.wire, 'timeout'); // metadata.go:100
      expect(
        WaitingReason.slingFailure.wire,
        'sling_failure', // metadata.go:101
      );
    });
  });

  group('Verdict + normalize (metadata.go:105-138)', () {
    test('canonical wire literals', () {
      expect(Verdict.approve.wire, 'approve'); // metadata.go:106
      expect(
        Verdict.approveWithRisks.wire,
        'approve-with-risks', // metadata.go:107
      );
      expect(Verdict.block.wire, 'block'); // metadata.go:108
    });

    test('normalize: canonical values pass through', () {
      expect(Verdict.normalize('approve'), Verdict.approve);
      expect(Verdict.normalize('approve-with-risks'), Verdict.approveWithRisks);
      expect(Verdict.normalize('block'), Verdict.block);
    });

    test('normalize: every past-tense mapping (metadata.go:113-119)', () {
      expect(Verdict.normalize('approved'), Verdict.approve);
      expect(Verdict.normalize('blocked'), Verdict.block);
      expect(Verdict.normalize('approve-with-risk'), Verdict.approveWithRisks);
      expect(
        Verdict.normalize('approved-with-risks'),
        Verdict.approveWithRisks,
      );
      expect(Verdict.normalize('approved-with-risk'), Verdict.approveWithRisks);
    });

    test('normalize: lowercase + trim before mapping (metadata.go:125)', () {
      expect(Verdict.normalize('  APPROVED  '), Verdict.approve);
      expect(Verdict.normalize('Block'), Verdict.block);
    });

    test('normalize: empty and unknown collapse to block '
        '(metadata.go:126-128, 135-136)', () {
      expect(Verdict.normalize(''), Verdict.block);
      expect(Verdict.normalize('   '), Verdict.block);
      expect(Verdict.normalize('lgtm'), Verdict.block);
    });

    test('normalize: trims the Go unicode.IsSpace set, NOT Dart trim — '
        'U+FEFF survives the trim and the verdict reads block '
        '(differential vs go1.26.4 NormalizeVerdict)', () {
      // Go strings.TrimSpace does not strip the BOM (category Cf), so a
      // BOM-prefixed approve is an UNKNOWN verdict → block. Dart's
      // String.trim() strips it → approve: the exact gc-divergence this
      // pins shut. The verdict gates iterate-vs-terminate
      // (handler.go:317-324), and agents write this key via bd meta set
      // (acl.go:10-13), so arbitrary bytes are reachable.
      expect(Verdict.normalize('\uFEFFapprove'), Verdict.block);
      expect(Verdict.normalize('approve\uFEFF'), Verdict.block);
      // U+200B (zero-width space) is Cf too — not trimmed by either side.
      expect(Verdict.normalize('\u200Bapprove'), Verdict.block);
      // Everything Go DOES trim still trims: Latin-1 fast path + Zs/Zl/Zp.
      expect(Verdict.normalize('\u0085\u00A0approve'), Verdict.approve);
      expect(Verdict.normalize('\u2028\u2029approve\u3000'), Verdict.approve);
      expect(Verdict.normalize('\v\fAPPROVED\u202F'), Verdict.approve);
    });

    test('normalize: lowercase matches Go simple case mapping on the one '
        'outcome-relevant rune (U+0130)', () {
      // go1.26.4: strings.ToLower("approve-wİth-risks") ==
      // "approve-with-risks" (simple mapping İ → i). Full-mapping
      // lowercase (İ → i + combining dot) would diverge to block.
      expect(Verdict.normalize('approve-wİth-risks'), Verdict.approveWithRisks);
      expect(Verdict.normalize('İ'), Verdict.block); // "i" — unknown
    });
  });

  group('CloseReasons (handler.go:47-55)', () {
    test('exact canonical strings (each ≥20 chars for bd validation)', () {
      expect(
        CloseReasons.createRollback,
        'convergence: bead-create rollback after error', // handler.go:48
      );
      expect(
        CloseReasons.retryRollback,
        'convergence: retry-create rollback after error', // handler.go:49
      );
      expect(
        CloseReasons.manualApprove,
        'convergence: iteration closed by manual approve', // handler.go:50
      );
      expect(
        CloseReasons.manualSupersede,
        'convergence: active wisp superseded during manual stop', // handler.go:51
      );
      expect(
        CloseReasons.manualStop,
        'convergence: iteration closed by manual stop', // handler.go:52
      );
      expect(
        CloseReasons.reconcileDone,
        'convergence reconcile: terminated-state bead closed', // handler.go:53
      );
      expect(
        CloseReasons.handlerCleanup,
        'convergence: terminated state observed; closing root', // handler.go:54
      );
      expect(
        CloseReasons.handlerRoot,
        'convergence: workflow handler closing root after terminate', // handler.go:55
      );
      for (final reason in [
        CloseReasons.createRollback,
        CloseReasons.retryRollback,
        CloseReasons.manualApprove,
        CloseReasons.manualSupersede,
        CloseReasons.manualStop,
        CloseReasons.reconcileDone,
        CloseReasons.handlerCleanup,
        CloseReasons.handlerRoot,
      ]) {
        expect(reason.length, greaterThanOrEqualTo(20), reason: reason);
      }
    });
  });
}
