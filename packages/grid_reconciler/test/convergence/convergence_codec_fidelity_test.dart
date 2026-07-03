// Codec-fidelity oracle (Track I — ADR-0000 A29). The DATA GAP is closed:
// `fixtures/upstream/2026-06-11-bd-1.0.5/convergence/` holds REAL gc-produced
// `convergence.*` metadata (gc's CreateHandler / HandleWispClosed / gate eval,
// bd-export round-tripped). This suite proves Track A's codec + projections
// decode that real output — not synthetic data.
//
// Four properties per fixture (the prompt's a/b/c/d):
//   (a) decode is TOTAL — never throws; the fixture (everything gc could write)
//       decodes cleanly (no `failures`); populated typed reads are well-formed;
//   (b) round-trip — encode(decode(m)) == m for the convergence.* keys;
//   (c) HARDCODED typed reads match the REAL captured values, scenario by
//       scenario;
//   (d) the projections (Convergence/Wisp) build from the flattened subgraph.
//
// The fixtures are the oracle: a decode failure here is a REAL codec bug.

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import '../fixtures/convergence_fixtures.dart';

void main() {
  // ---------------------------------------------------------------------------
  // (a) + (b) — totality, clean decode, and round-trip for EVERY fixture.
  // ---------------------------------------------------------------------------
  group('codec totality + round-trip (every real fixture)', () {
    for (final fixture in loadAllScenarios()) {
      group(fixture.scenario, () {
        test('decode is total and clean — no failures', () {
          // Total: never throws.
          final m = ConvergenceMetadata.decode(fixture.rootMetadata);
          // Everything gc actually wrote decodes cleanly: no malformed field,
          // no unrecognized state, no non-coercible value. A non-empty
          // `failures` here is a REAL codec bug against real bytes.
          expect(
            m.failures,
            isEmpty,
            reason:
                'real gc output must decode cleanly; failures=${m.failures}',
          );
          expect(m.decodesCleanly, isTrue);
          // The state is one of the five known states (the capture covers
          // active / waiting_manual / waiting_trigger / terminated).
          expect(
            m.state,
            isA<KnownConvergenceState>(),
            reason: 'every captured scenario carries a known convergence.state',
          );
        });

        test('round-trip — encode(decode(m)) == m for convergence.* keys', () {
          final m = ConvergenceMetadata.decode(fixture.rootMetadata);
          final encoded = m.encode();
          // By construction the whole map round-trips; assert it explicitly,
          // and (the prompt's framing) assert every convergence.* key survives
          // byte-for-byte.
          expect(encoded, equals(fixture.rootMetadata));
          for (final entry in fixture.rootMetadata.entries) {
            if (!entry.key.startsWith('convergence.')) continue;
            expect(
              encoded[entry.key],
              equals(entry.value),
              reason: '${entry.key} must round-trip verbatim',
            );
          }
        });
      });
    }
  });

  // ---------------------------------------------------------------------------
  // (c) — HARDCODED typed reads, scenario by scenario, against the REAL values.
  // ---------------------------------------------------------------------------
  group('typed reads match real captured values (hardcoded)', () {
    test('01-active-manual — active loop, active wisp gc-2', () {
      final m = ConvergenceMetadata.decode(
        loadScenario('01-active-manual.json').rootMetadata,
      );
      expect(m.state.stateOrNull, ConvergenceState.active);
      expect(m.iteration, const FieldValue<int>(1));
      expect(m.iterationOrZero, 1);
      expect(m.maxIterations, const FieldValue<int>(3));
      expect(m.formula, 'test-formula');
      expect(m.target, 'test-agent');
      expect(m.gateMode, const FieldValue<GateMode>(GateMode.manual));
      expect(m.activeWisp, 'gc-2');
      // Unset keys read as absent/null (gc writes "" for unset).
      expect(m.gateCondition, isNull);
      expect(m.lastProcessedWisp, isNull);
      expect(m.rig, isNull);
      expect(m.terminalReason, isNull);
      expect(m.waitingReason, isNull);
      // trigger: "" → TriggerMode.none (gc's TriggerNone is a valid mode).
      expect(m.trigger, const FieldValue<TriggerMode>(TriggerMode.none));
      expect(m.triggerEnabled, isFalse);
    });

    test('02-waiting-manual — waiting_manual, last_processed_wisp set', () {
      final m = ConvergenceMetadata.decode(
        loadScenario('02-waiting-manual.json').rootMetadata,
      );
      expect(m.state.stateOrNull, ConvergenceState.waitingManual);
      expect(m.waitingReason?.wire, 'manual');
      expect(m.waitingReason, WaitingReason.manual);
      // active_wisp was cleared ("") → null; last_processed_wisp now set.
      expect(m.activeWisp, isNull);
      expect(m.lastProcessedWisp, 'gc-2');
      expect(m.iteration, const FieldValue<int>(0));
      expect(m.iterationOrZero, 0);
      expect(m.maxIterations, const FieldValue<int>(3));
      expect(m.terminalReason, isNull);
    });

    test('03-terminated-approved — operator approve', () {
      final fixture = loadScenario('03-terminated-approved.json');
      final m = ConvergenceMetadata.decode(fixture.rootMetadata);
      expect(m.state.stateOrNull, ConvergenceState.terminated);
      expect(m.terminalReason, TerminalReason.approved);
      expect(m.terminalReason?.wire, 'approved');
      // Real operator actor verbatim.
      expect(m.terminalActor, 'operator:nico');
      expect(m.lastProcessedWisp, 'gc-2');
      // waiting_reason was cleared ("") on terminate → null.
      expect(m.waitingReason, isNull);
      // Non-convergence key survives in raw (close_reason).
      expect(
        m.encode()['close_reason'],
        'convergence: iteration closed by manual approve',
      );
    });

    test('04-gate-pass-terminated — full 28-key gate-pass payload', () {
      final m = ConvergenceMetadata.decode(
        loadScenario('04-gate-pass-terminated.json').rootMetadata,
      );
      // The prompt's exact 04 expectations.
      expect(m.state.stateOrNull, ConvergenceState.terminated);
      expect(m.gateOutcome, const FieldValue<GateOutcome>(GateOutcome.pass));
      // gate_exit_code parses to int 0 (stored "0", a STRING on the wire).
      expect(m.gateExitCode, const FieldValue<int>(0));
      expect(m.gateExitCodeOrNull, 0);
      // gate_duration_ms "143" → 143ms as a GoDuration.
      expect(m.gateDurationMs, const FieldValue<int>(143));
      expect(m.gateDurationOrZero, const Duration(milliseconds: 143));
      expect(
        GoDuration(m.gateDurationMs.valueOrNull! * 1000 * 1000).encode(),
        '143ms',
      );
      // gate_truncated "" → false (A17/D4: gc writes "" for false, never
      // "false").
      expect(m.gateTruncated, isFalse);
      expect(m.terminalReason, TerminalReason.approved);
      expect(m.terminalActor, 'controller');
      expect(m.iteration, const FieldValue<int>(0));
      expect(m.iterationOrZero, 0);
      expect(m.maxIterations, const FieldValue<int>(2));
      expect(m.gateMode, const FieldValue<GateMode>(GateMode.condition));
      expect(m.gateOutcomeWisp, 'gc-2');
      expect(m.gateRetryCount, const FieldValue<int>(0));
      expect(m.gateRetryCountOrZero, 0);
      // gate_condition is the real captured script path.
      expect(m.gateCondition, contains('gate.sh'));
      // Replay-branch verbatim reads ("" stdout/stderr).
      expect(m.gateStdoutWire, '');
      expect(m.gateStderrWire, '');
      expect(m.gateOutcomeWire, 'pass');
      expect(m.pendingNextWisp, isNull);
    });

    test('05-no-convergence-at-max — gate fail ×2 at max → no_convergence', () {
      final m = ConvergenceMetadata.decode(
        loadScenario('05-no-convergence-at-max.json').rootMetadata,
      );
      expect(m.state.stateOrNull, ConvergenceState.terminated);
      expect(m.terminalReason, TerminalReason.noConvergence);
      expect(m.terminalReason?.wire, 'no_convergence');
      expect(m.terminalActor, 'controller');
      expect(m.gateOutcome, const FieldValue<GateOutcome>(GateOutcome.fail));
      expect(m.gateExitCode, const FieldValue<int>(1));
      expect(m.gateExitCodeOrNull, 1);
      expect(m.gateDurationMs, const FieldValue<int>(13));
      expect(m.gateDurationOrZero, const Duration(milliseconds: 13));
      expect(m.maxIterations, const FieldValue<int>(2));
      expect(m.gateMode, const FieldValue<GateMode>(GateMode.condition));
      expect(m.gateTruncated, isFalse);
    });

    test('06-waiting-trigger — trigger=event, waiting_trigger', () {
      final m = ConvergenceMetadata.decode(
        loadScenario('06-waiting-trigger.json').rootMetadata,
      );
      expect(m.state.stateOrNull, ConvergenceState.waitingTrigger);
      expect(m.trigger, const FieldValue<TriggerMode>(TriggerMode.event));
      expect(m.triggerEnabled, isTrue);
      expect(m.triggerCondition, contains('gate.sh'));
      expect(m.gateMode, const FieldValue<GateMode>(GateMode.manual));
      expect(m.maxIterations, const FieldValue<int>(3));
      // No gate ran yet — gate outcome/exit absent.
      expect(m.gateOutcome.isAbsent, isTrue);
      expect(m.gateExitCode.isAbsent, isTrue);
      expect(m.terminalReason, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // (c, cont.) — bd WIRE round-trip: gc writes convergence.* through
  // `SetMetadata`/`SetMetadataBatch` → `bd update --json <id> --set-metadata
  // key=value` (bdstore.go:1347-1357, handler.go:211), the **type-INFERRING**
  // form. bd 1.0.5 runs `toJSONValue` on each value (beads/cmd/bd/update.go:619)
  // so a string "0" lands in the JSON metadata column as the NUMBER 0,
  // "143" as 143, "true" as the bool true; only non-numeric/non-bool strings
  // (paths, "pass", and the empty string) stay strings. gc reads them back
  // through the tolerant `StringMap` coercion (metadata-keys.md §5.6), which the
  // codec replicates via `coerceWireValue` — so the codec MUST decode the real
  // coerced wire form, not just verbatim strings.
  //
  // NOTE on the pinned fixture: `bd-export-roundtrip.jsonl` was captured via the
  // non-gc `bd update --metadata '{...}'` JSON-blob form (update.go:255-271),
  // which takes the blob verbatim and therefore preserves every value as a
  // STRING. That is NOT gc's write path and does NOT model the live `tg` wire
  // form. We keep loading it only to assert that property explicitly (a string
  // witness, captured via the blob form), and we derive the REAL wire form here
  // by porting bd's `toJSONValue` inference and applying it to 04's gc-internal
  // metadata — the form `--set-metadata` actually produces. (Re-capture of the
  // jsonl through gc's real path is a porting-skill task; the fixture dir is
  // read-only here.)
  // ---------------------------------------------------------------------------
  group('bd wire round-trip == 04 (real --set-metadata type inference)', () {
    test('codec decodes 04 in the REAL coerced wire form (numbers/bools)', () {
      final fixture04 = loadScenario('04-gate-pass-terminated.json');
      final from04 = ConvergenceMetadata.decode(fixture04.rootMetadata);

      // gc's actual write path: every value goes through bd `toJSONValue`, so
      // the metadata column holds inferred JSON scalars, not strings.
      final wire = bdSetMetadataWireForm(fixture04.rootMetadata);
      final fromWire = ConvergenceMetadata.decode(wire);

      // The REAL wire form: type-inferred fields land as JSON number / bool,
      // NOT strings. This is what `bd export --all` yields for gc-written beads
      // in live tg — directly exercising `coerceWireValue` on the happy path.
      expect(wire['convergence.iteration'], 0);
      expect(wire['convergence.max_iterations'], 2);
      expect(wire['convergence.gate_exit_code'], 0);
      expect(wire['convergence.gate_duration_ms'], 143);
      expect(wire['convergence.gate_retry_count'], 0);
      // gate_truncated is "" here (gc writes "" for false, never "false";
      // A17/D4) — empty string is not %f-parsable, so it stays a string.
      expect(wire['convergence.gate_truncated'], '');
      // Non-numeric strings (paths, the outcome literal, the city path) stay
      // strings.
      expect(wire['convergence.gate_outcome'], 'pass');
      expect(wire['convergence.terminal_reason'], 'approved');
      expect(wire['convergence.gate_condition'], endsWith('gate.sh'));

      // `coerceWireValue` collapses the inferred scalars back to gc's text form,
      // so the typed reads are IDENTICAL whether the field arrived as a string
      // (04's captured internal form) or as the inferred scalar (the live wire
      // form). Decode stays total and clean across both.
      expect(fromWire.failures, isEmpty);
      expect(fromWire.decodesCleanly, isTrue);
      expect(fromWire.iteration, from04.iteration);
      expect(fromWire.iteration, const FieldValue<int>(0));
      expect(fromWire.maxIterations, from04.maxIterations);
      expect(fromWire.maxIterations, const FieldValue<int>(2));
      expect(fromWire.gateExitCode, from04.gateExitCode);
      expect(fromWire.gateExitCode, const FieldValue<int>(0));
      expect(fromWire.gateDurationMs, from04.gateDurationMs);
      expect(fromWire.gateDurationMs, const FieldValue<int>(143));
      expect(fromWire.gateRetryCount, from04.gateRetryCount);
      expect(fromWire.gateTruncated, from04.gateTruncated);
      expect(fromWire.gateTruncated, isFalse);
      expect(fromWire.state.stateOrNull, from04.state.stateOrNull);
      expect(fromWire.gateOutcome, from04.gateOutcome);
      expect(fromWire.terminalReason, from04.terminalReason);
      expect(fromWire.terminalActor, from04.terminalActor);
    });

    test('a JSON bool true (gate_truncated written "true") reads true', () {
      // The one inferred-bool field gc can produce: `--set-metadata
      // gate_truncated=true` → bd stores the bool `true` → `coerceWireValue`
      // → "true" → strict `== "true"` (handler.go:298).
      final m = ConvergenceMetadata.decode(<String, dynamic>{
        ConvergenceFields.gateTruncated: true,
      });
      expect(m.gateTruncated, isTrue);
      expect(m.failures, isEmpty);
    });

    test('the JSON-blob fixture is the string witness, NOT gc\'s wire form', () {
      // `bd-export-roundtrip.jsonl` was written via `bd update --metadata`
      // (blob form), which preserves strings verbatim — useful only to pin that
      // the blob path does NOT coerce. It is explicitly NOT the type-inferred
      // form gc's `--set-metadata` path produces (asserted above).
      final exported = Bead.fromJson(loadExportRoundtrip());
      expect(exported.metadata['convergence.gate_exit_code'], '0');
      expect(exported.metadata['convergence.gate_duration_ms'], '143');
      expect(exported.metadata['convergence.gate_truncated'], '');
      // Even from the string-form blob, the codec decodes cleanly (coercion is
      // an identity for strings) and reads the same typed values.
      final fromBlob = ConvergenceMetadata.decode(exported.metadata);
      expect(fromBlob.failures, isEmpty);
      expect(fromBlob.gateExitCode, const FieldValue<int>(0));
      expect(fromBlob.gateDurationMs, const FieldValue<int>(143));
    });
  });

  // ---------------------------------------------------------------------------
  // (d) — projections build from the flattened subgraph. The capture nests
  // children + sets `parent`; the fixture loader converts that to the
  // parent-child DEPENDENCY edges the projection resolves through (A15).
  // ---------------------------------------------------------------------------
  group('projections over the real subgraph', () {
    test('01 subgraph → Convergence projects; wisp idempotency_key parses', () {
      final fixture = loadScenario('01-active-manual.json');
      final snapshot = fixture.toSnapshot();
      final rootBead = snapshot.bead(fixture.convergenceRoot)!;

      final result = Convergence.project(
        rootBead,
        dependencies: snapshot.dependencies,
        beadsById: snapshot.beadsById,
      );
      expect(result, isA<ProjectionOk<Convergence>>());
      final convergence = (result as ProjectionOk<Convergence>).value;

      expect(convergence.id, 'gc-1');
      expect(convergence.state.stateOrNull, ConvergenceState.active);

      // Exactly one wisp (gc-2, the molecule), resolved through the synthesized
      // parent-child edge.
      expect(convergence.wisps, hasLength(1));
      final wisp = convergence.wisps.single;
      expect(wisp.id, 'gc-2');
      expect(wisp.idempotencyKey, 'converge:gc-1:iter:1');
      // The key parses to iteration 1.
      expect(wisp.iteration, 1);
      expect(parseIterationFromKey(wisp.idempotencyKey), 1);

      // active_wisp resolves to the projected wisp.
      expect(convergence.activeWisp?.id, 'gc-2');

      // findByIdempotencyKey hits on the real key (the prompt's exact probe).
      expect(convergence.findByIdempotencyKey('converge:gc-1:iter:1'), 'gc-2');
      // A miss returns null (a key for an iteration that was never poured).
      expect(convergence.findByIdempotencyKey('converge:gc-1:iter:9'), isNull);
    });

    test('01 wisp subtree is the post-order subtree (gc-3 → gc-2)', () {
      final fixture = loadScenario('01-active-manual.json');
      final snapshot = fixture.toSnapshot();
      final wispBead = snapshot.bead('gc-2')!;

      final result = Wisp.project(
        wispBead,
        dependencies: snapshot.dependencies,
        beadsById: snapshot.beadsById,
      );
      expect(result, isA<ProjectionOk<Wisp>>());
      final wisp = (result as ProjectionOk<Wisp>).value;

      // Post-order: the step child (gc-3) before the wisp root (gc-2).
      expect(wisp.subtreeIds, ['gc-3', 'gc-2']);

      // The real step is resolved as a Step child (issue_type=step).
      expect(wisp.steps.map((s) => s.id), ['gc-3']);
      // No deferred keys in this direct (non-speculative) pour.
      expect(wisp.speculativeNodes, isEmpty);
    });

    test('terminal-state subgraphs (02–06) carry no wisp children but still '
        'project the root', () {
      // 02–06 captured only the root node (the wisp subgraph is not re-serialized
      // once the loop advances); the Convergence projection must still succeed
      // with zero wisps and the right typed state.
      for (final name in const [
        '02-waiting-manual.json',
        '03-terminated-approved.json',
        '04-gate-pass-terminated.json',
        '05-no-convergence-at-max.json',
        '06-waiting-trigger.json',
      ]) {
        final fixture = loadScenario(name);
        final snapshot = fixture.toSnapshot();
        final rootBead = snapshot.bead(fixture.convergenceRoot)!;
        final result = Convergence.project(
          rootBead,
          dependencies: snapshot.dependencies,
          beadsById: snapshot.beadsById,
        );
        expect(
          result,
          isA<ProjectionOk<Convergence>>(),
          reason: '$name root must project',
        );
        final convergence = (result as ProjectionOk<Convergence>).value;
        expect(
          convergence.wisps,
          isEmpty,
          reason:
              '$name has no re-captured '
              'wisp subgraph',
        );
        expect(convergence.metadata.failures, isEmpty);
      }
    });
  });
}

/// Faithful Dart port of bd 1.0.5's `toJSONValue`
/// (beads/cmd/bd/update.go:617-638) — the type inference `bd update
/// --set-metadata key=value` applies to every value before it is stored in the
/// JSON metadata column. This is gc's REAL write path
/// (`SetMetadata`/`SetMetadataBatch` → `--set-metadata`, bdstore.go:1347-1387),
/// so a `bd export` of a gc-written bead in live `tg` returns the inferred
/// scalars this produces, NOT the input strings.
///
/// Rules (update.go:619-638):
///  * `"null"` → JSON null;
///  * `"true"`/`"false"` → JSON bool;
///  * anything `Sscanf(s, "%f")`-parsable that also round-trips through
///    `json.Valid` → JSON number (int stays int, float stays double);
///  * everything else (including `""`) → JSON string.
Object? bdToJsonValue(String s) {
  if (s == 'null') return null;
  if (s == 'true') return true;
  if (s == 'false') return false;
  // Go: fmt.Sscanf(s, "%f", &f) — succeeds for a leading numeric token — AND
  // json.Valid([]byte(s)) — rejects "1abc", "0x1", trailing junk, etc. The
  // combination admits exactly the strings that are valid JSON numbers.
  if (_looksFloatParsable(s)) {
    final parsed = num.tryParse(s);
    if (parsed != null && _isValidJsonNumber(s)) {
      // bd keeps the raw token; an integer token decodes back to an int.
      return parsed is double && parsed == parsed.truncate() && !s.contains('.')
          ? parsed.toInt()
          : parsed;
    }
  }
  return s; // default: JSON string
}

/// Applies [bdToJsonValue] to every value of a gc-internal metadata map,
/// modelling the metadata column after gc's `--set-metadata` writes — the wire
/// form `bd export --all` returns.
Map<String, dynamic> bdSetMetadataWireForm(Map<String, dynamic> internal) => {
  for (final entry in internal.entries)
    entry.key: entry.value is String
        ? bdToJsonValue(entry.value as String)
        : entry.value,
};

/// Approximates Go's `fmt.Sscanf(s, "%f")` success: a non-empty string whose
/// leading token parses as a float. We require the WHOLE trimmed string to be
/// numeric (the `json.Valid` guard below rejects trailing junk anyway).
bool _looksFloatParsable(String s) {
  if (s.isEmpty) return false;
  return double.tryParse(s) != null;
}

/// Go's `json.Valid([]byte(s))` for the numeric branch: the string must be a
/// syntactically valid JSON number on its own (no leading zeros beyond "0", no
/// trailing characters). Dart's `num.tryParse` is close; we additionally reject
/// forms JSON disallows that `double.tryParse` would accept (hex, infinity).
bool _isValidJsonNumber(String s) {
  // JSON number grammar: -?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?
  return RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$').hasMatch(s);
}
