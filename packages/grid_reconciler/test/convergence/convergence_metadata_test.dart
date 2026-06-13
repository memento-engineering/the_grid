import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

void main() {
  group('ConvergenceFields key literals (metadata.go:12-44)', () {
    test('every key string matches metadata.go exactly', () {
      // Hardcoded — the codec is only correct if these are the bytes gc
      // writes. Build-order note: this is the TRUE 31-key set, not the
      // 16 listed in M2-BUILD-ORDER Track A.
      expect(ConvergenceFields.state, 'convergence.state'); // :13
      expect(ConvergenceFields.iteration, 'convergence.iteration'); // :14
      expect(
        ConvergenceFields.maxIterations,
        'convergence.max_iterations', // :15
      );
      expect(ConvergenceFields.formula, 'convergence.formula'); // :16
      expect(ConvergenceFields.target, 'convergence.target'); // :17
      expect(ConvergenceFields.gateMode, 'convergence.gate_mode'); // :18
      expect(
        ConvergenceFields.gateCondition,
        'convergence.gate_condition', // :19
      );
      expect(ConvergenceFields.gateTimeout, 'convergence.gate_timeout'); // :20
      expect(
        ConvergenceFields.gateTimeoutAction,
        'convergence.gate_timeout_action', // :21
      );
      expect(ConvergenceFields.activeWisp, 'convergence.active_wisp'); // :22
      expect(
        ConvergenceFields.lastProcessedWisp,
        'convergence.last_processed_wisp', // :23
      );
      expect(
        ConvergenceFields.agentVerdict,
        'convergence.agent_verdict', // :24
      );
      expect(
        ConvergenceFields.agentVerdictWisp,
        'convergence.agent_verdict_wisp', // :25
      );
      expect(ConvergenceFields.gateOutcome, 'convergence.gate_outcome'); // :26
      expect(
        ConvergenceFields.gateExitCode,
        'convergence.gate_exit_code', // :27
      );
      expect(
        ConvergenceFields.gateOutcomeWisp,
        'convergence.gate_outcome_wisp', // :28
      );
      expect(
        ConvergenceFields.gateRetryCount,
        'convergence.gate_retry_count', // :29
      );
      expect(
        ConvergenceFields.terminalReason,
        'convergence.terminal_reason', // :30
      );
      expect(
        ConvergenceFields.terminalActor,
        'convergence.terminal_actor', // :31
      );
      expect(
        ConvergenceFields.waitingReason,
        'convergence.waiting_reason', // :32
      );
      expect(ConvergenceFields.retrySource, 'convergence.retry_source'); // :33
      expect(ConvergenceFields.cityPath, 'convergence.city_path'); // :34
      expect(ConvergenceFields.rig, 'convergence.rig'); // :35
      expect(
        ConvergenceFields.evaluatePrompt,
        'convergence.evaluate_prompt', // :36
      );
      expect(ConvergenceFields.gateStdout, 'convergence.gate_stdout'); // :37
      expect(ConvergenceFields.gateStderr, 'convergence.gate_stderr'); // :38
      expect(
        ConvergenceFields.gateDurationMs,
        'convergence.gate_duration_ms', // :39
      );
      expect(
        ConvergenceFields.gateTruncated,
        'convergence.gate_truncated', // :40
      );
      expect(
        ConvergenceFields.pendingNextWisp,
        'convergence.pending_next_wisp', // :41
      );
      expect(ConvergenceFields.trigger, 'convergence.trigger'); // :42
      expect(
        ConvergenceFields.triggerCondition,
        'convergence.trigger_condition', // :43
      );
      expect(ConvergenceFields.varPrefix, 'var.'); // :47
      expect(ConvergenceFields.all, hasLength(31));
      expect(ConvergenceFields.all.toSet(), hasLength(31));
    });
  });

  group('round-trip identity: encode(decode(m)) == m for ANY input', () {
    test('a fully-populated gc-shaped map', () {
      final input = <String, dynamic>{
        'convergence.state': 'active',
        'convergence.iteration': '2',
        'convergence.max_iterations': '5',
        'convergence.formula': 'mol-polish',
        'convergence.target': 'polisher',
        'convergence.gate_mode': 'condition',
        'convergence.gate_condition': 'gates/check.sh',
        'convergence.gate_timeout': '5m0s',
        'convergence.gate_timeout_action': 'retry',
        'convergence.active_wisp': 'gt-w2',
        'convergence.last_processed_wisp': 'gt-w1',
        'convergence.agent_verdict': 'approved',
        'convergence.agent_verdict_wisp': 'gt-w1',
        'convergence.gate_outcome': 'fail',
        'convergence.gate_exit_code': '1',
        'convergence.gate_outcome_wisp': 'gt-w1',
        'convergence.gate_retry_count': '0',
        'convergence.terminal_reason': '',
        'convergence.terminal_actor': '',
        'convergence.waiting_reason': '',
        'convergence.retry_source': '',
        'convergence.city_path': '/Users/nico/gascity',
        'convergence.rig': 'the_grid',
        'convergence.evaluate_prompt': 'judge the diff',
        'convergence.gate_stdout': 'ok\n',
        'convergence.gate_stderr': '',
        'convergence.gate_duration_ms': '742',
        'convergence.gate_truncated': '',
        'convergence.pending_next_wisp': 'gt-w3',
        'convergence.trigger': '',
        'convergence.trigger_condition': '',
        'var.doc_path': 'docs/PDR.md',
      };
      final decoded = ConvergenceMetadata.decode(input);
      expect(decoded.encode(), equals(input));
      expect(decoded.decodesCleanly, isTrue);
    });

    test('unknown and extra keys preserved verbatim (A13)', () {
      final input = <String, dynamic>{
        'convergence.state': 'active',
        'convergence.some_future_key': 'whatever',
        'gc.routed_to': 'rig/x',
        'totally_unrelated': 'kept',
      };
      final decoded = ConvergenceMetadata.decode(input);
      expect(decoded.encode(), equals(input));
      // Unknown keys are not failures — only malformed values are.
      expect(decoded.failures, isEmpty);
    });

    test('garbage values still round-trip exactly', () {
      final input = <String, dynamic>{
        'convergence.state': 'bogus-state',
        'convergence.iteration': 'NaN',
        'convergence.gate_timeout': 'five minutes',
        'convergence.gate_mode': 42,
        'var.broken': 17,
        'convergence.max_iterations': <String>['nope'],
      };
      final decoded = ConvergenceMetadata.decode(input);
      expect(decoded.encode(), equals(input));
    });

    test('empty map', () {
      final decoded = ConvergenceMetadata.decode(const {});
      expect(decoded.encode(), equals(const <String, dynamic>{}));
      expect(decoded.failures, isEmpty);
    });
  });

  group('typed decode — happy path', () {
    final meta = ConvergenceMetadata.decode(const {
      'convergence.state': 'waiting_manual',
      'convergence.iteration': '3',
      'convergence.max_iterations': '10',
      'convergence.formula': 'mol-polish',
      'convergence.target': 'polisher',
      'convergence.gate_mode': 'hybrid',
      'convergence.gate_condition': 'gates/check.sh',
      'convergence.gate_timeout': '90s',
      'convergence.gate_timeout_action': 'terminate',
      'convergence.active_wisp': 'gt-w3',
      'convergence.last_processed_wisp': 'gt-w2',
      'convergence.agent_verdict': 'Approved ',
      'convergence.agent_verdict_wisp': 'gt-w3',
      'convergence.gate_outcome': 'timeout',
      'convergence.gate_exit_code': '124',
      'convergence.gate_outcome_wisp': 'gt-w3',
      'convergence.gate_retry_count': '2',
      'convergence.terminal_reason': 'no_convergence',
      'convergence.terminal_actor': 'controller',
      'convergence.waiting_reason': 'hybrid_no_condition',
      'convergence.retry_source': 'gt-old',
      'convergence.city_path': '/city',
      'convergence.rig': 'rig-1',
      'convergence.evaluate_prompt': 'prompt',
      'convergence.gate_stdout': 'out',
      'convergence.gate_stderr': 'err',
      'convergence.gate_duration_ms': '1500',
      'convergence.gate_truncated': 'true',
      'convergence.pending_next_wisp': 'gt-w4',
      'convergence.trigger': 'event',
      'convergence.trigger_condition': 'triggers/poll.sh',
      'var.doc_path': 'docs/x.md',
      'var.depth': '2',
    });

    test('every field decodes to its typed value', () {
      expect(
        meta.state,
        const ConvergenceStateReading.known(ConvergenceState.waitingManual),
      );
      expect(meta.iteration, const FieldValue<int>(3));
      expect(meta.iterationOrZero, 3);
      expect(meta.maxIterations, const FieldValue<int>(10));
      expect(meta.maxIterationsOrZero, 10);
      expect(meta.formula, 'mol-polish');
      expect(meta.target, 'polisher');
      expect(meta.gateMode, const FieldValue(GateMode.hybrid));
      expect(meta.gateCondition, 'gates/check.sh');
      expect(meta.gateTimeout, const FieldValue(GoDuration(90000000000)));
      expect(
        meta.gateTimeoutAction,
        const FieldValue(GateTimeoutAction.terminate),
      );
      expect(meta.activeWisp, 'gt-w3');
      expect(meta.lastProcessedWisp, 'gt-w2');
      expect(meta.agentVerdict, 'Approved ');
      expect(meta.agentVerdictWisp, 'gt-w3');
      expect(meta.gateOutcome, const FieldValue(GateOutcome.timeout));
      expect(meta.gateExitCode, const FieldValue<int>(124));
      expect(meta.gateExitCodeOrNull, 124);
      expect(meta.gateOutcomeWisp, 'gt-w3');
      expect(meta.gateRetryCount, const FieldValue<int>(2));
      expect(meta.gateRetryCountOrZero, 2);
      expect(meta.terminalReason, TerminalReason.noConvergence);
      expect(meta.terminalActor, 'controller');
      expect(meta.waitingReason, WaitingReason.hybridNoCondition);
      expect(meta.retrySource, 'gt-old');
      expect(meta.cityPath, '/city');
      expect(meta.rig, 'rig-1');
      expect(meta.evaluatePrompt, 'prompt');
      expect(meta.gateStdout, 'out');
      expect(meta.gateStderr, 'err');
      expect(meta.gateDurationMs, const FieldValue<int>(1500));
      expect(meta.gateDurationOrZero, const Duration(milliseconds: 1500));
      expect(meta.gateTruncated, isTrue);
      expect(meta.pendingNextWisp, 'gt-w4');
      expect(meta.trigger, const FieldValue(TriggerMode.event));
      expect(meta.triggerEnabled, isTrue);
      expect(meta.triggerCondition, 'triggers/poll.sh');
      expect(meta.decodesCleanly, isTrue);
    });

    test('vars: var.* prefix stripped (template.go:43-51)', () {
      expect(meta.vars, {'doc_path': 'docs/x.md', 'depth': '2'});
    });

    test('verdictFor: scoped verdict normalizes (handler.go:319-324)', () {
      expect(
        meta.verdictFor('gt-w3'),
        Verdict.approve,
      ); // 'Approved ' → approve
      expect(meta.verdictFor('gt-w2'), isNull); // mismatched wisp
    });
  });

  group('absent vs empty distinctions', () {
    test('absent state vs empty state both read notAdopted; '
        'unknown reads unrecognized', () {
      expect(
        ConvergenceMetadata.decode(const {}).state,
        const ConvergenceStateReading.notAdopted(),
      );
      expect(
        ConvergenceMetadata.decode(const {'convergence.state': ''}).state,
        const ConvergenceStateReading.notAdopted(),
      );
      expect(
        ConvergenceMetadata.decode(const {'convergence.state': 'paused'}).state,
        const ConvergenceStateReading.unrecognized('paused'),
      );
    });

    test('ints: missing key and empty string are FieldAbsent '
        '(DecodeInt("") -> no value, metadata.go:147-149)', () {
      expect(
        ConvergenceMetadata.decode(const {}).iteration,
        const FieldAbsent<int>(),
      );
      expect(
        ConvergenceMetadata.decode(const {
          'convergence.iteration': '',
        }).iteration,
        const FieldAbsent<int>(),
      );
    });

    test('strings: absent and empty both read null (gc map semantics)', () {
      expect(ConvergenceMetadata.decode(const {}).activeWisp, isNull);
      expect(
        ConvergenceMetadata.decode(const {
          'convergence.active_wisp': '',
        }).activeWisp,
        isNull, // gc clears active_wisp by writing "" (handler.go:442)
      );
    });

    test('trigger: absent and empty are both the valid none mode '
        '(TriggerNone = "", metadata.go:61)', () {
      expect(
        ConvergenceMetadata.decode(const {}).trigger,
        const FieldValue(TriggerMode.none),
      );
      expect(
        ConvergenceMetadata.decode(const {'convergence.trigger': ''}).trigger,
        const FieldValue(TriggerMode.none),
      );
      expect(ConvergenceMetadata.decode(const {}).triggerEnabled, isFalse);
    });

    test('gate timeout: absent reads absent; gc applies the 5m default '
        '(gate.go:11)', () {
      expect(
        ConvergenceMetadata.decode(const {}).gateTimeout,
        const FieldAbsent<GoDuration>(),
      );
      expect(
        ConvergenceMetadata.defaultGateTimeout,
        const GoDuration(300000000000),
      );
      expect(ConvergenceMetadata.defaultGateTimeout.encode(), '5m0s');
    });
  });

  group('typed failures (decode is total — nothing throws)', () {
    test('garbage int -> FieldMalformed, and the Go-collapse helper '
        'reproduces gc (DecodeInt -> 0)', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.iteration': 'three',
      });
      expect(
        meta.iteration,
        const FieldMalformed<int>(
          'convergence.iteration',
          'three',
          'not a valid integer',
        ),
      );
      expect(meta.iterationOrZero, 0); // handler.go:208 collapse
    });

    test('int with whitespace/hex is malformed (Atoi grammar)', () {
      expect(
        ConvergenceMetadata.decode(const {
          'convergence.max_iterations': ' 5',
        }).maxIterations.isMalformed,
        isTrue,
      );
      expect(
        ConvergenceMetadata.decode(const {
          'convergence.gate_exit_code': '0x1',
        }).gateExitCode.isMalformed,
        isTrue,
      );
    });

    test('garbage duration -> FieldMalformed', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.gate_timeout': 'five minutes',
      });
      expect(meta.gateTimeout.isMalformed, isTrue);
      expect(meta.gateTimeout.valueOrNull, isNull);
    });

    test('out-of-set enum values -> FieldMalformed (gc errors on these: '
        'gate.go:50-55, 70-77; trigger.go:38-40)', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.gate_mode': 'auto',
        'convergence.gate_timeout_action': 'stop',
        'convergence.gate_outcome': 'passed',
        'convergence.trigger': 'poll',
      });
      expect(meta.gateMode.isMalformed, isTrue);
      expect(meta.gateTimeoutAction.isMalformed, isTrue);
      expect(meta.gateOutcome.isMalformed, isTrue);
      expect(meta.trigger.isMalformed, isTrue);
      expect(meta.triggerEnabled, isFalse);
    });

    test('non-coercible values (objects/arrays) under typed keys -> '
        'FieldMalformed / failures', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.iteration': <String>['nope'],
        'convergence.formula': {'a': 1},
        'var.depth': <int>[2],
      });
      expect(meta.iteration.isMalformed, isTrue);
      expect(meta.formula, isNull);
      expect(meta.vars, isEmpty); // non-coercible var skipped, reported below
      final keys = meta.failures.map((f) => f.key).toList();
      expect(
        keys,
        containsAll([
          'convergence.iteration',
          'convergence.formula',
          'var.depth',
        ]),
      );
    });

    test('gc-written data as bd actually stores it decodes CLEANLY — '
        'the StringMap coercion (bdstore.go:497-522; metadata-keys §5.6)', () {
      // bd's toJSONValue type-infers: gc's SetMetadata("…iteration", "3")
      // lands as JSON number 3; "gate_truncated" = "true" as bool true.
      final meta = ConvergenceMetadata.decode(const {
        'convergence.iteration': 3,
        'convergence.max_iterations': 5,
        'convergence.gate_exit_code': -1,
        'convergence.gate_retry_count': 0,
        'convergence.gate_duration_ms': 742,
        'convergence.gate_truncated': true,
        'convergence.formula': 'mol-polish',
        'var.depth': 2,
      });
      expect(meta.iteration, const FieldValue<int>(3));
      expect(meta.iterationOrZero, 3); // gc reads 3 — never 0
      expect(meta.maxIterationsOrZero, 5); // the iter>=max terminal check
      expect(meta.gateExitCodeOrNull, -1); // signal-killed gate (trap 19)
      expect(meta.gateRetryCountOrZero, 0);
      expect(meta.gateDurationOrZero, const Duration(milliseconds: 742));
      expect(meta.gateTruncated, isTrue); // bool true == gc's "true"
      expect(meta.vars, {'depth': '2'}); // ExtractVars over StringMap
      expect(meta.decodesCleanly, isTrue);
      // And the raw map is still returned verbatim — typed values intact.
      expect(meta.encode()['convergence.iteration'], 3);
      expect(meta.encode()['convergence.gate_truncated'], true);
    });

    test('JSON null coerces to "" — Go json.Unmarshal(null, &string) is a '
        'no-op, so StringMap yields the zero value (NOT the text "null")', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.state': null,
        'convergence.active_wisp': null,
        'convergence.iteration': null,
        'convergence.trigger': null,
        'convergence.gate_truncated': null,
      });
      expect(meta.state, const ConvergenceStateReading.notAdopted());
      expect(meta.activeWisp, isNull);
      expect(meta.iteration, const FieldAbsent<int>());
      expect(meta.trigger, const FieldValue(TriggerMode.none));
      expect(meta.gateTruncated, isFalse);
      expect(meta.decodesCleanly, isTrue);
    });

    test('coerced scalars that still fail the field grammar stay malformed '
        'with the ORIGINAL raw value preserved', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.iteration': 3.5, // "3.5" fails Atoi, like in gc
        'convergence.gate_mode': true, // "true" is not a gate mode
      });
      expect(meta.iteration.isMalformed, isTrue);
      expect(meta.iterationOrZero, 0); // gc's DecodeInt("3.5") collapse
      expect(meta.gateMode.isMalformed, isTrue);
      expect(meta.failures.map((f) => f.rawValue), containsAll([3.5, true]));
    });

    test('residual double gap is the documented Dart toString form', () {
      // gc would read the raw JSON text "1e5"; post-json.decode the text is
      // gone — coerceWireValue documents the divergence. Unreachable for
      // gc-written data (gc only writes integers/strings).
      expect(ConvergenceMetadata.coerceWireValue(1e5), '100000.0');
      expect(ConvergenceMetadata.coerceWireValue(3), '3');
      expect(ConvergenceMetadata.coerceWireValue(true), 'true');
      expect(ConvergenceMetadata.coerceWireValue(false), 'false');
      expect(ConvergenceMetadata.coerceWireValue(null), '');
      expect(ConvergenceMetadata.coerceWireValue('s'), 's');
    });

    test('gate_truncated mirrors gc exactly: == "true" only, never '
        'malformed (handler.go:298, 799-803)', () {
      expect(
        ConvergenceMetadata.decode(const {
          'convergence.gate_truncated': 'true',
        }).gateTruncated,
        isTrue,
      );
      for (final value in ['', 'false', 'yes', 'TRUE']) {
        expect(
          ConvergenceMetadata.decode({
            'convergence.gate_truncated': value,
          }).gateTruncated,
          isFalse,
          reason: '"$value"',
        );
      }
    });

    test('failures aggregates every malformed field; clean fields stay '
        'readable (one bad key never poisons the bead)', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.state': 'limbo',
        'convergence.iteration': 'x',
        'convergence.formula': 'still-fine',
      });
      expect(meta.decodesCleanly, isFalse);
      expect(meta.failures, hasLength(2));
      expect(
        meta.failures.map((f) => f.key),
        containsAll(['convergence.state', 'convergence.iteration']),
      );
      expect(meta.formula, 'still-fine');
    });

    test('a gc-writable map has zero failures', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.state': 'terminated',
        'convergence.terminal_reason': 'approved',
        'convergence.terminal_actor': 'operator:nico',
        'convergence.iteration': '4',
      });
      expect(meta.failures, isEmpty);
    });
  });

  group('encode helpers (gc wire encodings)', () {
    test('goEncodeInt is strconv.Itoa (metadata.go:141-143)', () {
      expect(goEncodeInt(0), '0');
      expect(goEncodeInt(42), '42');
      expect(goEncodeInt(-3), '-3');
    });

    test('goEncodeBool writes "true" / "" — never "false" '
        '(handler.go:799-803)', () {
      expect(goEncodeBool(value: true), 'true');
      expect(goEncodeBool(value: false), '');
    });

    test('GoDuration.encode writes the exact gate_timeout format '
        '(EncodeDuration = Duration.String(), metadata.go:159-161)', () {
      expect(const GoDuration(90000000000).encode(), '1m30s');
    });
  });

  group('verbatim replay readers (handler.go:280-298)', () {
    test('gateOutcomeWire passes a persisted garbage outcome through '
        'unvalidated, exactly like gc (handler.go:282) — where the typed '
        'reading reports malformed', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.gate_outcome': 'passed', // garbage — not in the set
      });
      expect(meta.gateOutcomeWire, 'passed'); // verbatim, like gc
      expect(meta.gateOutcome.isMalformed, isTrue); // typed view flags it
      // The foot-gun the verbatim reader exists to avoid: the collapsing
      // read rewrites garbage to '' (no-gate-ran), changing the replayed
      // payload vs gc.
      expect(meta.gateOutcome.valueOrNull?.wire ?? '', '');
    });

    test('absent keys read as Go map zero values: "" everywhere', () {
      final meta = ConvergenceMetadata.decode(const {});
      expect(meta.gateOutcomeWire, '');
      expect(meta.gateStdoutWire, '');
      expect(meta.gateStderrWire, '');
    });

    test('gateStdoutWire/gateStderrWire are the exact replay values '
        '(handler.go:291-292) — no empty-as-null collapse', () {
      final meta = ConvergenceMetadata.decode(const {
        'convergence.gate_stdout': 'all 7 checks green',
        'convergence.gate_stderr': '',
      });
      expect(meta.gateStdoutWire, 'all 7 checks green');
      expect(meta.gateStderrWire, ''); // GateResult.stderr wants '' not null
      expect(meta.gateStderr, isNull); // the gc-map-semantics reader differs
    });
  });
}
