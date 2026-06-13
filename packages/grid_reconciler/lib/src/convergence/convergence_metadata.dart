import 'package:freezed_annotation/freezed_annotation.dart';

import 'convergence_state.dart';
import 'field_reading.dart';
import 'gate_mode.dart';
import 'gate_outcome.dart';
import 'gate_timeout_action.dart';
import 'go_duration.dart';
import 'go_scalars.dart';
import 'verdict.dart';

part 'convergence_metadata.freezed.dart';

/// Every metadata key in gc's `convergence.*` namespace — the **complete**
/// 31-key set from `gascity/internal/convergence/metadata.go:12-44` (the
/// build order's "16 keys" undercounts; see goAmbiguities in the Track A
/// report).
abstract final class ConvergenceFields {
  static const state = 'convergence.state'; // metadata.go:13
  static const iteration = 'convergence.iteration'; // metadata.go:14
  static const maxIterations = 'convergence.max_iterations'; // metadata.go:15
  static const formula = 'convergence.formula'; // metadata.go:16
  static const target = 'convergence.target'; // metadata.go:17
  static const gateMode = 'convergence.gate_mode'; // metadata.go:18
  static const gateCondition = 'convergence.gate_condition'; // metadata.go:19
  static const gateTimeout = 'convergence.gate_timeout'; // metadata.go:20
  static const gateTimeoutAction =
      'convergence.gate_timeout_action'; // metadata.go:21
  static const activeWisp = 'convergence.active_wisp'; // metadata.go:22
  static const lastProcessedWisp =
      'convergence.last_processed_wisp'; // metadata.go:23
  static const agentVerdict = 'convergence.agent_verdict'; // metadata.go:24
  static const agentVerdictWisp =
      'convergence.agent_verdict_wisp'; // metadata.go:25
  static const gateOutcome = 'convergence.gate_outcome'; // metadata.go:26
  static const gateExitCode = 'convergence.gate_exit_code'; // metadata.go:27
  static const gateOutcomeWisp =
      'convergence.gate_outcome_wisp'; // metadata.go:28
  static const gateRetryCount =
      'convergence.gate_retry_count'; // metadata.go:29
  static const terminalReason = 'convergence.terminal_reason'; // metadata.go:30
  static const terminalActor = 'convergence.terminal_actor'; // metadata.go:31
  static const waitingReason = 'convergence.waiting_reason'; // metadata.go:32
  static const retrySource = 'convergence.retry_source'; // metadata.go:33
  static const cityPath = 'convergence.city_path'; // metadata.go:34
  static const rig = 'convergence.rig'; // metadata.go:35
  static const evaluatePrompt = 'convergence.evaluate_prompt'; // metadata.go:36
  static const gateStdout = 'convergence.gate_stdout'; // metadata.go:37
  static const gateStderr = 'convergence.gate_stderr'; // metadata.go:38
  static const gateDurationMs =
      'convergence.gate_duration_ms'; // metadata.go:39
  static const gateTruncated = 'convergence.gate_truncated'; // metadata.go:40
  static const pendingNextWisp =
      'convergence.pending_next_wisp'; // metadata.go:41
  static const trigger = 'convergence.trigger'; // metadata.go:42
  static const triggerCondition =
      'convergence.trigger_condition'; // metadata.go:43

  /// metadata.go:47 — `VarPrefix = "var."` (template variables).
  static const varPrefix = 'var.';

  /// All 31 namespaced keys, in metadata.go declaration order.
  static const all = <String>[
    state,
    iteration,
    maxIterations,
    formula,
    target,
    gateMode,
    gateCondition,
    gateTimeout,
    gateTimeoutAction,
    activeWisp,
    lastProcessedWisp,
    agentVerdict,
    agentVerdictWisp,
    gateOutcome,
    gateExitCode,
    gateOutcomeWisp,
    gateRetryCount,
    terminalReason,
    terminalActor,
    waitingReason,
    retrySource,
    cityPath,
    rig,
    evaluatePrompt,
    gateStdout,
    gateStderr,
    gateDurationMs,
    gateTruncated,
    pendingNextWisp,
    trigger,
    triggerCondition,
  ];
}

/// A terminal reason for `convergence.terminal_reason`.
///
/// Open-set extension type: the canonical values are constants
/// (metadata.go:81-86) but gc consumes the stored string **verbatim** —
/// recovery re-emits it unvalidated (reconcile.go:266-273) — so unknown
/// values must flow through unharmed.
extension type const TerminalReason(String wire) {
  /// metadata.go:82 — `TerminalApproved = "approved"`.
  static const approved = TerminalReason('approved');

  /// metadata.go:83 — `TerminalNoConvergence = "no_convergence"`.
  static const noConvergence = TerminalReason('no_convergence');

  /// metadata.go:84 — `TerminalStopped = "stopped"`.
  static const stopped = TerminalReason('stopped');

  /// metadata.go:85 — `TerminalPartialCreation = "partial_creation"`.
  static const partialCreation = TerminalReason('partial_creation');
}

/// A waiting reason for `convergence.waiting_reason`.
///
/// Open-set extension type: canonical values metadata.go:97-102; consumed
/// verbatim (re-emitted in events, repaired with [manual] as the default —
/// reconcile.go:360-369).
extension type const WaitingReason(String wire) {
  /// metadata.go:98 — `WaitManual = "manual"`.
  static const manual = WaitingReason('manual');

  /// metadata.go:99 — `WaitHybridNoCondition = "hybrid_no_condition"`.
  static const hybridNoCondition = WaitingReason('hybrid_no_condition');

  /// metadata.go:100 — `WaitTimeout = "timeout"`.
  static const timeout = WaitingReason('timeout');

  /// metadata.go:101 — `WaitSlingFailure = "sling_failure"`.
  static const slingFailure = WaitingReason('sling_failure');
}

/// The trigger mode for `convergence.trigger` (metadata.go:60-63).
///
/// A closed two-value set where **none IS the empty string**: gc's
/// `TriggerNone = ""` is a valid mode (the default wisp-close iteration
/// semantic), and `ParseTriggerConfig` errors on anything else
/// (trigger.go:30-40), so unknown values are typed decode failures.
enum TriggerMode {
  /// metadata.go:61 — `TriggerNone = ""`.
  none(''),

  /// metadata.go:62 — `TriggerEvent = "event"`.
  event('event');

  const TriggerMode(this.wire);

  /// The exact string gc writes to `convergence.trigger`.
  final String wire;

  /// Port of `TriggerConfig.Enabled` (trigger.go:19-21).
  bool get enabled => this == event;
}

/// One typed decode failure inside a convergence metadata map.
@freezed
abstract class ConvergenceMetadataFailure with _$ConvergenceMetadataFailure {
  const ConvergenceMetadataFailure._();

  const factory ConvergenceMetadataFailure({
    /// The metadata key that failed to decode.
    required String key,

    /// The offending raw value, preserved verbatim.
    required Object? rawValue,

    /// Human-readable reason.
    required String reason,
  }) = _ConvergenceMetadataFailure;

  @override
  String toString() => 'ConvergenceMetadataFailure($key: $rawValue — $reason)';
}

/// The typed codec over a convergence bead's metadata map.
///
/// Follows the A13 pattern: the **entire** input map — every unknown or extra
/// key, every malformed value — is preserved verbatim in [raw], typed getters
/// read *from* [raw], and [encode] returns [raw], so
/// `encode(decode(m)) == m` holds for **any** input map by construction.
///
/// Every typed read applies gc's `StringMap` wire coercion first
/// ([coerceWireValue]): bd 1.0.5 type-infers metadata values on write, so
/// gc-written ints/bools arrive as JSON numbers/booleans and must read as
/// their text form, exactly as gc reads them (metadata-keys.md §5.6,
/// porting trap 2).
///
/// Decode is **total**: [decode] never throws and no getter throws. Failure
/// granularity is two-layer (see [FieldReading]):
///
/// * per-field — each typed accessor returns a reading
///   ([FieldValue]/[FieldAbsent]/[FieldMalformed], or the dedicated
///   [ConvergenceStateReading] for state), so consumers handle exactly the
///   fields they touch;
/// * codec-level — [failures] aggregates every malformed field in the map for
///   shadow-mode diagnostics, without blocking access to well-formed fields
///   (a single bad key must not poison the whole bead).
///
/// Where gc's own reads *collapse* bad values (`DecodeInt` → "no value"),
/// matching `...OrZero`/`...OrNull` helpers reproduce the exact Go read,
/// each citing its call site — so Track B can be byte-faithful without
/// re-deriving Go semantics.
@freezed
abstract class ConvergenceMetadata with _$ConvergenceMetadata {
  const ConvergenceMetadata._();

  const factory ConvergenceMetadata({
    @Default(<String, dynamic>{}) Map<String, dynamic> raw,
  }) = _ConvergenceMetadata;

  /// Wraps a bead's metadata map. Total — never throws, preserves everything.
  factory ConvergenceMetadata.decode(Map<String, dynamic> metadata) =>
      ConvergenceMetadata(raw: Map<String, dynamic>.unmodifiable(metadata));

  /// gc's default gate timeout, 5 minutes (`DefaultGateTimeout`, gate.go:11).
  static const GoDuration defaultGateTimeout = GoDuration(300000000000);

  /// The verbatim metadata map back — `encode(decode(m)) == m` for any input.
  Map<String, dynamic> encode() => raw;

  // ---------------------------------------------------------------------------
  // Reading primitives
  // ---------------------------------------------------------------------------

  /// gc's `StringMap` coercion (gascity/internal/beads/bdstore.go:497-522)
  /// replicated at the read boundary.
  ///
  /// bd 1.0.5 type-infers `--set-metadata` values (beads/cmd/bd/update.go
  /// `toJSONValue`): `"3"` is stored as JSON number `3`, `"true"` as JSON
  /// bool `true` — so **every int and bool gc itself wrote arrives as a
  /// non-String JSON scalar** on the wire. gc reads them back through
  /// `StringMap`, which coerces non-strings to their JSON text; this is the
  /// equivalent Dart read. [raw] stays verbatim, so
  /// `encode(decode(m)) == m` still holds (metadata-keys.md §5.6).
  ///
  /// * JSON `null` → `''` — Go's `json.Unmarshal` of `null` into a string
  ///   is a no-op, so `StringMap` yields the zero value `""`. Null reads as
  ///   absent/cleared, **not** as the text `"null"`.
  /// * `bool`/`int` → their JSON text (`3` → `'3'`, `true` → `'true'`).
  /// * `double` → Dart `toString()`. ⚠ Residual gap, documented not closed:
  ///   gc coerces from the *raw JSON text* (`strings.TrimSpace(string(v))`),
  ///   which is gone after `json.decode` — a stored `1e5` reads `"1e5"` in
  ///   gc but `"100000.0"` here. Unreachable for gc-written data (gc only
  ///   ever writes integers and strings).
  /// * `Map`/`List` → returned unchanged (post-decode re-serialization
  ///   cannot be byte-faithful); they surface in [failures].
  static Object? coerceWireValue(Object? value) => switch (value) {
    null => '',
    final bool b => b ? 'true' : 'false',
    final num n => n.toString(),
    _ => value,
  };

  /// String read with gc map semantics: absent and empty are
  /// indistinguishable to gc (`meta[key]` yields `""` for both), so both
  /// read as null. Non-String JSON scalars coerce to their text form
  /// ([coerceWireValue]); non-coercible values read null (and are reported
  /// in [failures]).
  String? _str(String key) {
    final Object? value = coerceWireValue(raw[key]);
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// gc's bare `meta[key]` read: the stored string verbatim, `''` for
  /// absent (Go map zero value) — no emptiness collapse, no validation.
  /// The replay-branch read primitive (handler.go:280-298).
  String _verbatim(String key) => switch (coerceWireValue(raw[key])) {
    final String value => value,
    _ => '',
  };

  FieldReading<int> _int(String key) {
    if (!raw.containsKey(key)) return FieldAbsent<int>();
    final Object? original = raw[key];
    final Object? value = coerceWireValue(original);
    if (value is! String) {
      return FieldMalformed<int>(
        key,
        original,
        'expected a JSON scalar encoding an integer, '
        'got ${original.runtimeType}',
      );
    }
    if (value.isEmpty) return FieldAbsent<int>(); // DecodeInt("") → no value
    final n = goAtoi(value);
    if (n == null) {
      return FieldMalformed<int>(key, original, 'not a valid integer');
    }
    return FieldValue<int>(n);
  }

  FieldReading<T> _enum<T>(String key, T? Function(String wire) fromWire) {
    if (!raw.containsKey(key)) return FieldAbsent<T>();
    final Object? original = raw[key];
    final Object? value = coerceWireValue(original);
    if (value is! String) {
      return FieldMalformed<T>(
        key,
        original,
        'expected a JSON scalar, got ${original.runtimeType}',
      );
    }
    if (value.isEmpty) return FieldAbsent<T>();
    final parsed = fromWire(value);
    if (parsed == null) {
      return FieldMalformed<T>(key, original, 'unrecognized value "$value"');
    }
    return FieldValue<T>(parsed);
  }

  // ---------------------------------------------------------------------------
  // Typed fields (metadata.go declaration order)
  // ---------------------------------------------------------------------------

  /// `convergence.state` — see [ConvergenceStateReading] for the
  /// known / not-adopted / unrecognized trichotomy. The raw value passes
  /// through [coerceWireValue] first (a JSON `null` state reads notAdopted,
  /// exactly as gc's `StringMap` → `""` read would).
  ConvergenceStateReading get state => ConvergenceStateReading.decode(
    coerceWireValue(raw[ConvergenceFields.state]),
    present: raw.containsKey(ConvergenceFields.state),
  );

  /// `convergence.iteration` — int (gc `EncodeInt`, create.go:167).
  FieldReading<int> get iteration => _int(ConvergenceFields.iteration);

  /// gc's collapsing read of [iteration]: `DecodeInt` discards the ok flag
  /// (handler.go:208 `storedIteration, _ := DecodeInt(...)`) so absent **and
  /// malformed** read as 0.
  int get iterationOrZero => iteration.valueOrNull ?? 0;

  /// `convergence.max_iterations` — int (create.go:106).
  FieldReading<int> get maxIterations => _int(ConvergenceFields.maxIterations);

  /// gc's collapsing read of [maxIterations] (handler.go:216).
  int get maxIterationsOrZero => maxIterations.valueOrNull ?? 0;

  /// `convergence.formula` — the formula name/path (create.go:104).
  String? get formula => _str(ConvergenceFields.formula);

  /// `convergence.target` — the target agent (create.go:105).
  String? get target => _str(ConvergenceFields.target);

  /// `convergence.gate_mode` — [GateMode]; absent reads as absent here, and
  /// gc defaults it to manual at parse time ([GateMode.defaultMode]).
  FieldReading<GateMode> get gateMode =>
      _enum(ConvergenceFields.gateMode, GateMode.fromWire);

  /// `convergence.gate_condition` — gate script path (empty for manual-only).
  String? get gateCondition => _str(ConvergenceFields.gateCondition);

  /// `convergence.gate_timeout` — a Go duration string
  /// (`EncodeDuration`/`DecodeDuration`, metadata.go:159-174); absent means
  /// gc applies [defaultGateTimeout].
  FieldReading<GoDuration> get gateTimeout {
    const key = ConvergenceFields.gateTimeout;
    if (!raw.containsKey(key)) return const FieldAbsent<GoDuration>();
    final Object? original = raw[key];
    final Object? value = coerceWireValue(original);
    if (value is! String) {
      return FieldMalformed<GoDuration>(
        key,
        original,
        'expected a Go duration String, got ${original.runtimeType}',
      );
    }
    if (value.isEmpty) return const FieldAbsent<GoDuration>();
    final d = GoDuration.parse(value);
    if (d == null) {
      return FieldMalformed<GoDuration>(
        key,
        original,
        'not a valid Go duration',
      );
    }
    return FieldValue<GoDuration>(d);
  }

  /// `convergence.gate_timeout_action` — [GateTimeoutAction]; gc defaults to
  /// iterate when absent ([GateTimeoutAction.defaultAction]).
  FieldReading<GateTimeoutAction> get gateTimeoutAction =>
      _enum(ConvergenceFields.gateTimeoutAction, GateTimeoutAction.fromWire);

  /// `convergence.active_wisp` — the in-flight wisp id; gc *clears* it by
  /// writing `""` (handler.go:442), so empty reads as null.
  String? get activeWisp => _str(ConvergenceFields.activeWisp);

  /// `convergence.last_processed_wisp` — the dedup/commit marker (ADR-0003
  /// invariant 2: always written LAST).
  String? get lastProcessedWisp => _str(ConvergenceFields.lastProcessedWisp);

  /// `convergence.agent_verdict` — the raw verdict string, **not**
  /// normalized; see [verdictFor].
  String? get agentVerdict => _str(ConvergenceFields.agentVerdict);

  /// `convergence.agent_verdict_wisp` — the wisp the verdict is scoped to.
  String? get agentVerdictWisp => _str(ConvergenceFields.agentVerdictWisp);

  /// Port of gc's scoped verdict read (handler.go:319-324): the normalized
  /// verdict when it is scoped to [wispId], else null (gc substitutes
  /// `block` on the gate path and `""` on event payloads — the caller picks).
  Verdict? verdictFor(String wispId) {
    if (agentVerdictWisp != wispId) return null;
    return Verdict.normalize(agentVerdict ?? '');
  }

  /// `convergence.gate_outcome` — [GateOutcome]. gc replays this verbatim
  /// without validation (handler.go:282); an out-of-set value is surfaced as
  /// malformed here while the raw string stays available in [raw]. The
  /// replay branch must use [gateOutcomeWire], never this reading.
  FieldReading<GateOutcome> get gateOutcome =>
      _enum(ConvergenceFields.gateOutcome, GateOutcome.fromWire);

  /// The VERBATIM replay read of `convergence.gate_outcome` — gc rebuilds
  /// the replay `GateResult` straight off `meta[FieldGateOutcome]` with NO
  /// validation (handler.go:282), so a persisted garbage outcome flows
  /// through step-7's literal compares and into the event payload
  /// unchanged. Absent/null reads `''` (Go map semantics). Use THIS for
  /// `GateResult.outcomeWire` on the replay branch:
  /// `gateOutcome.valueOrNull?.wire ?? ''` compiles, looks right, and
  /// silently rewrites garbage to `''` (no-gate-ran) — changing the
  /// replayed payload's `gate_outcome` from the garbage string to null vs
  /// gc (`GateResultToPayload` returns nil for an empty outcome,
  /// events.go:195-206).
  String get gateOutcomeWire => _verbatim(ConvergenceFields.gateOutcome);

  /// `convergence.gate_exit_code` — int; gc writes `""` when not applicable
  /// (handler.go:780-784).
  FieldReading<int> get gateExitCode => _int(ConvergenceFields.gateExitCode);

  /// gc's collapsing read of [gateExitCode] (handler.go:283-287): absent or
  /// malformed reads as "no exit code".
  int? get gateExitCodeOrNull => gateExitCode.valueOrNull;

  /// `convergence.gate_outcome_wisp` — the gate-persistence idempotency
  /// marker, written LAST in `persistGateOutcome` (handler.go:806-807).
  String? get gateOutcomeWisp => _str(ConvergenceFields.gateOutcomeWisp);

  /// `convergence.gate_retry_count` — int (handler.go:787).
  FieldReading<int> get gateRetryCount =>
      _int(ConvergenceFields.gateRetryCount);

  /// gc's collapsing read of [gateRetryCount] (handler.go:288-290).
  int get gateRetryCountOrZero => gateRetryCount.valueOrNull ?? 0;

  /// `convergence.terminal_reason` — open set, consumed verbatim.
  TerminalReason? get terminalReason {
    final value = _str(ConvergenceFields.terminalReason);
    return value == null ? null : TerminalReason(value);
  }

  /// `convergence.terminal_actor` — `"controller"`, `"operator:<user>"`, or
  /// `"recovery"` (handler.go:389, manual.go:27, reconcile.go:217).
  String? get terminalActor => _str(ConvergenceFields.terminalActor);

  /// `convergence.waiting_reason` — open set, consumed verbatim.
  WaitingReason? get waitingReason {
    final value = _str(ConvergenceFields.waitingReason);
    return value == null ? null : WaitingReason(value);
  }

  /// `convergence.retry_source` — provenance marker for retry-created loops.
  String? get retrySource => _str(ConvergenceFields.retrySource);

  /// `convergence.city_path` — set during create (handler.go:743).
  String? get cityPath => _str(ConvergenceFields.cityPath);

  /// `convergence.rig` — the owning rig scope; empty means city/HQ
  /// (create.go:27-31).
  String? get rig => _str(ConvergenceFields.rig);

  /// `convergence.evaluate_prompt` — prompt for the injected evaluate step.
  String? get evaluatePrompt => _str(ConvergenceFields.evaluatePrompt);

  /// `convergence.gate_stdout` — captured/truncated gate stdout
  /// (handler.go:790). gc reads it verbatim on replay; null means absent or
  /// empty (identical to gc).
  String? get gateStdout => _str(ConvergenceFields.gateStdout);

  /// Verbatim-`''` replay read of [gateStdout] (`GateResult.Stdout` takes
  /// `meta[FieldGateStdout]` directly, handler.go:291) — the exact value
  /// for `GateResult.stdout` on the replay branch.
  String get gateStdoutWire => _verbatim(ConvergenceFields.gateStdout);

  /// `convergence.gate_stderr` — captured/truncated gate stderr
  /// (handler.go:793).
  String? get gateStderr => _str(ConvergenceFields.gateStderr);

  /// Verbatim-`''` replay read of [gateStderr] (handler.go:292) — the
  /// exact value for `GateResult.stderr` on the replay branch.
  String get gateStderrWire => _verbatim(ConvergenceFields.gateStderr);

  /// `convergence.gate_duration_ms` — int milliseconds
  /// (`strconv.FormatInt(result.Duration.Milliseconds(), 10)`,
  /// handler.go:796).
  FieldReading<int> get gateDurationMs =>
      _int(ConvergenceFields.gateDurationMs);

  /// gc's collapsing replay read of [gateDurationMs] (handler.go:293-296):
  /// absent/malformed reads as zero duration.
  Duration get gateDurationOrZero =>
      Duration(milliseconds: gateDurationMs.valueOrNull ?? 0);

  /// `convergence.gate_truncated` — gc writes `"true"` or the **empty
  /// string** (handler.go:799-803) and replays with strict `== "true"`
  /// (handler.go:298). bd stores gc's `"true"` as JSON bool `true`
  /// (toJSONValue), so the value passes through [coerceWireValue] before
  /// the strict compare — a Dart `bool true` reads true, exactly as gc's
  /// `StringMap` read does. Total — never malformed.
  bool get gateTruncated =>
      goDecodeBool(coerceWireValue(raw[ConvergenceFields.gateTruncated]));

  /// `convergence.pending_next_wisp` — the speculative-pour recovery marker
  /// (ADR-0003 invariant 5; handler.go:268, cleared at handler.go:565).
  String? get pendingNextWisp => _str(ConvergenceFields.pendingNextWisp);

  /// `convergence.trigger` — [TriggerMode]; absent **and** empty both read
  /// as [TriggerMode.none] (gc's `TriggerNone = ""` is a valid mode, not an
  /// unset key — trigger.go:30-32).
  FieldReading<TriggerMode> get trigger {
    const key = ConvergenceFields.trigger;
    if (!raw.containsKey(key)) return const FieldValue(TriggerMode.none);
    final Object? original = raw[key];
    final Object? value = coerceWireValue(original);
    if (value is! String) {
      return FieldMalformed<TriggerMode>(
        key,
        original,
        'expected a JSON scalar, got ${original.runtimeType}',
      );
    }
    if (value.isEmpty) return const FieldValue(TriggerMode.none);
    if (value == TriggerMode.event.wire) {
      return const FieldValue(TriggerMode.event);
    }
    return FieldMalformed<TriggerMode>(
      key,
      original,
      'invalid trigger mode "$value"',
    );
  }

  /// Port of `TriggerConfig.Enabled` over the stored mode (trigger.go:19-21);
  /// malformed reads as not-enabled (gc would refuse the config instead).
  bool get triggerEnabled => trigger.valueOrNull == TriggerMode.event;

  /// `convergence.trigger_condition` — trigger script path (required when
  /// trigger is `event`, trigger.go:33-37).
  String? get triggerCondition => _str(ConvergenceFields.triggerCondition);

  /// Port of `ExtractVars` (template.go:43-51): every `var.`-prefixed key
  /// with the prefix stripped. Values pass through [coerceWireValue] (bd
  /// stores `var.depth=2` as JSON number `2`; gc reads it back as `"2"`).
  /// Non-coercible values (objects/arrays) are skipped here and reported in
  /// [failures].
  Map<String, String> get vars {
    final out = <String, String>{};
    for (final entry in raw.entries) {
      if (!entry.key.startsWith(ConvergenceFields.varPrefix)) continue;
      final Object? value = coerceWireValue(entry.value);
      if (value is! String) continue;
      out[entry.key.substring(ConvergenceFields.varPrefix.length)] = value;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Codec-level failure aggregation
  // ---------------------------------------------------------------------------

  /// Every typed decode failure in this map: malformed field values, an
  /// unrecognized state, non-coercible values (objects/arrays — see
  /// [coerceWireValue]) under typed `convergence.*` keys or `var.*` keys.
  /// Empty for anything gc could have written **as it actually arrives off
  /// bd's wire** — including gc-written ints/bools that bd's type
  /// inference stored as JSON numbers/booleans (metadata-keys.md §5.6).
  /// Unknown *keys* are never failures — they pass through [raw] verbatim
  /// (A13).
  List<ConvergenceMetadataFailure> get failures {
    final out = <ConvergenceMetadataFailure>[];

    if (state case UnrecognizedConvergenceState(:final rawValue)) {
      out.add(
        ConvergenceMetadataFailure(
          key: ConvergenceFields.state,
          rawValue: rawValue,
          reason: rawValue is String
              ? 'unknown convergence state "$rawValue"'
              : 'expected a String, got ${rawValue.runtimeType}',
        ),
      );
    }

    void collect<T>(FieldReading<T> reading) {
      if (reading case FieldMalformed<T>(
        :final key,
        :final rawValue,
        :final reason,
      )) {
        out.add(
          ConvergenceMetadataFailure(
            key: key,
            rawValue: rawValue,
            reason: reason,
          ),
        );
      }
    }

    collect(iteration);
    collect(maxIterations);
    collect(gateMode);
    collect(gateTimeout);
    collect(gateTimeoutAction);
    collect(gateOutcome);
    collect(gateExitCode);
    collect(gateRetryCount);
    collect(gateDurationMs);
    collect(trigger);

    // Plain-string convergence.* keys and var.* keys must coerce to Strings
    // (gc's StringMap coerces every JSON scalar; objects/arrays cannot be
    // gc-written and cannot be coerced byte-faithfully post-decode).
    for (final key in _stringFields) {
      if (!raw.containsKey(key)) continue;
      final Object? value = raw[key];
      if (coerceWireValue(value) is! String) {
        out.add(
          ConvergenceMetadataFailure(
            key: key,
            rawValue: value,
            reason: 'expected a JSON scalar, got ${value.runtimeType}',
          ),
        );
      }
    }
    for (final entry in raw.entries) {
      if (!entry.key.startsWith(ConvergenceFields.varPrefix)) continue;
      final Object? value = entry.value;
      if (coerceWireValue(value) is! String) {
        out.add(
          ConvergenceMetadataFailure(
            key: entry.key,
            rawValue: value,
            reason: 'expected a JSON scalar, got ${value.runtimeType}',
          ),
        );
      }
    }
    return out;
  }

  /// True when every field gc would read decodes cleanly.
  bool get decodesCleanly => failures.isEmpty;

  static const _stringFields = <String>[
    ConvergenceFields.formula,
    ConvergenceFields.target,
    ConvergenceFields.gateCondition,
    ConvergenceFields.activeWisp,
    ConvergenceFields.lastProcessedWisp,
    ConvergenceFields.agentVerdict,
    ConvergenceFields.agentVerdictWisp,
    ConvergenceFields.gateOutcomeWisp,
    ConvergenceFields.terminalReason,
    ConvergenceFields.terminalActor,
    ConvergenceFields.waitingReason,
    ConvergenceFields.retrySource,
    ConvergenceFields.cityPath,
    ConvergenceFields.rig,
    ConvergenceFields.evaluatePrompt,
    ConvergenceFields.gateStdout,
    ConvergenceFields.gateStderr,
    ConvergenceFields.gateTruncated,
    ConvergenceFields.pendingNextWisp,
    ConvergenceFields.triggerCondition,
  ];
}
