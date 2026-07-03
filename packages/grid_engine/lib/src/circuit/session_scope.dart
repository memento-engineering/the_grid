/// The engine-private session lifecycle owner (ADR-0008 D4 / M4-P1 D-2).
///
/// `SessionScope` is mounted by `WorkBead` ABOVE the circuit fan-out (the
/// resolver returns it). It **adopt-or-mints** the the_grid session bead, holds
/// `{resolving | ready | failed}`, and on `ready` provides a stable
/// `InheritedSeed<SessionHandle>` over the `CircuitScope` so the inflater + every
/// `CapabilityHost` attach to the SAME session — establishing the session is a
/// tree *state* (a loading state, `const Idle()` until resolved), not a
/// synchronous id injection. This is the "Route resolves before its Page
/// attaches" shape (an abstraction, not a literal router). It is ALSO where the
/// per-session ambient values mount (2026-07-02): the `Workspace` (computed from
/// the per-substation `SourceControl`) and the `SiblingView` (this session's
/// cursor + results) — the values an effect reads with the non-binding lookup.
///
/// It owns the session lifecycle END-TO-END: it also CLOSES the session on the
/// circuit's positive terminal (D-2 — one owner for open+close, not the terminal
/// step's host). The close is SCHEDULED off `build` (never a write IN `build` —
/// invariant 2) and latched once. Breaker-exhaustion close + escalation fold in
/// at Track G.
///
/// Why above the fan-out (the D-2 break it fixes): P0 minted lazily at
/// first-leaf-mount and named the provider session = the bead id, one per work
/// bead. `MultiChildBranch` mounts all frontier children in one pass, so two
/// concurrent leaves would each see `session == null` → two mints, and both
/// would call `provider.start` with the same name → collisions. Minting ONCE,
/// above the fan-out, is the fix.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';

import '../domain/session_bead.dart';
import '../domain/session_projection.dart';
import '../kernel/station_services.dart';
import '../kernel/idle.dart';
import '../sdk/capability.dart';
import '../sdk/cursor.dart';
import '../sdk/circuit.dart';
import '../sdk/frontier.dart';
import 'capability_registry.dart';
import 'circuit_scope.dart';
import 'session_handle.dart';

/// The adopt-or-mint session lifecycle owner for one work [bead]'s [circuit]
/// (D-2). Key it `ValueKey('${bead.id}:session')` so it persists across cursor
/// ticks while the work node keeps its branch identity.
class SessionScope extends StatefulSeed {
  /// Creates the scope for [bead] running [circuit], with the bead's linked
  /// [existingSession] (null until a session exists — then `SessionScope` mints
  /// one; non-null → it adopts).
  const SessionScope({
    required this.bead,
    required this.circuit,
    this.existingSession,
    super.key,
  });

  /// The work bead this session drives (its id is the circuit's root nodePath
  /// and the mint's `work_bead` linkage).
  final Bead bead;

  /// The root circuit for this work bead.
  final Circuit circuit;

  /// The bead's linked session projection (the JOIN row) — null when no session
  /// exists yet (mint), non-null once the bridge projects one (adopt). Its
  /// [SessionProjection.cursor] threads the per-node cursor down to
  /// `CircuitScope` pull-free (A39).
  final SessionProjection? existingSession;

  @override
  State<SessionScope> createState() => SessionScopeState();
}

/// The `{resolving | ready | failed}` lifecycle (D-2). The async-gap guards
/// (`_cancelled` set first in `dispose`, `context.mounted` after every await,
/// the captured `_ctx`) are the same discipline as `CapabilityHostState`.
class SessionScopeState extends State<SessionScope> {
  /// The the_grid-internal escalation marker key (NOT a codec-boundary key) — a
  /// human picks it up when a circuit's breaker exhausts (D-5).
  static const _escalationKey = 'grid.escalation';

  /// The capture-only escalation-diagnostic key (FT-1, tg-pez) — the final
  /// failing node + its truncated reason, recorded beside [_escalationKey] in
  /// the SAME write so a human sees WHAT exhausted, not just THAT it did.
  static const _escalationReasonKey = 'grid.escalation_reason';

  StationServices? _ctx;
  String? _sessionId;
  bool _resolving = true;
  bool _failed = false;
  bool _cancelled = false;
  bool _terminalScheduled = false;

  /// The nodePaths whose gate re-arm has already been scheduled — latched so a
  /// resolved gate flips its parked node back to `pending` exactly once (D-7).
  final Set<String> _rearmed = {};

  @override
  void didChangeDependencies() {
    // ALWAYS re-read (D-H rule 1) — the captured field exists for async-gap use
    // (`context` throws post-unmount), never as a read-once cache.
    final ctx = context.dependOnInheritedSeedOfExactType<StationServices>();
    assert(
      ctx != null,
      'SessionScope requires an ambient InheritedSeed<StationServices>',
    );
    _ctx = ctx;
  }

  @override
  void initState() {
    final existing = seed.existingSession?.sessionId;
    if (existing != null && existing.isNotEmpty) {
      // ADOPT — synchronous, no mint (the restoration adopt seam is the same
      // resolving→ready transition on restart).
      _sessionId = existing;
      _resolving = false;
    } else {
      // MINT — once, above the fan-out.
      unawaited(_mint());
    }
  }

  Future<void> _mint() async {
    // Yield so didChangeDependencies captures _ctx (genesis runs initState then
    // didChangeDependencies within one performRebuild).
    await null;
    if (_cancelled || !context.mounted) return;
    try {
      final id = await _ctx!.writer.createSession(
        substation: _ctx!.stateSubstation,
        title: 'grid session ${seed.bead.id}',
        workBeadId: seed.bead.id,
      );
      if (_cancelled || !context.mounted) return;
      setState(() {
        _sessionId = id;
        _resolving = false;
      });
    } on Object {
      if (_cancelled || !context.mounted) return;
      setState(() {
        _failed = true;
        _resolving = false;
      });
    }
  }

  /// Schedules the session close on the positive terminal — latched once, run
  /// off `build` (never a write IN `build`).
  void _scheduleClose(String id) {
    if (_terminalScheduled) return;
    _terminalScheduled = true;
    scheduleMicrotask(() => unawaited(_ctx?.writer.close(id)));
  }

  /// Schedules the breaker-exhaustion escalation (D-5): write the human marker
  /// (+ the capture-only [reason] diagnostic, FT-1) onto the OWN session bead,
  /// then close — which tears the subtree down, killing any leaked daemons (the
  /// §9 failure path). Latched once, off `build`.
  void _scheduleEscalation(String id, String reason) {
    if (_terminalScheduled) return;
    _terminalScheduled = true;
    scheduleMicrotask(() => unawaited(_escalateAndClose(id, reason)));
  }

  /// Re-arms ONE parked node whose gate bead has closed (D-7): flips its cursor
  /// `gated` → `pending` through the chokepoint so the route re-runs. Latched per
  /// node (`_rearmed`), scheduled off `build` (never a write IN `build`).
  void _scheduleRearm(String id, String nodePath) {
    if (_rearmed.contains(nodePath)) return;
    _rearmed.add(nodePath);
    scheduleMicrotask(
      () => unawaited(
        _ctx?.writer.update(
          id,
          metadata: nodeStateMetadata(nodePath, StepState.pending),
        ),
      ),
    );
  }

  Future<void> _escalateAndClose(String id, String reason) async {
    // Runs to completion even if SessionScope is mid-dispose — the escalation
    // marker + close must be durable (uses the captured ctx, never `context`).
    final ctx = _ctx;
    if (ctx == null) return;
    await ctx.writer.update(
      id,
      metadata: {
        _escalationKey: 'breaker-exhausted',
        // Capture-only (FT-1): the failing node + reason, beside the marker.
        if (reason.isNotEmpty) _escalationReasonKey: reason,
      },
    );
    await ctx.writer.close(id, reason: 'breaker-exhausted');
  }

  @override
  void dispose() {
    _cancelled = true;
  }

  @override
  Seed build(TreeContext context) {
    if (_resolving || _failed || _sessionId == null) return const Idle();
    final id = _sessionId!;
    final cursor = seed.existingSession?.cursor ?? const <String, NodeCursor>{};
    final results =
        seed.existingSession?.results ?? const <String, Map<String, String>>{};

    // D-7: re-arm any node parked at a gate whose gate bead has CLOSED (its
    // nodePath left `openGateNodes`). Read-only here; the flip to `pending` is
    // scheduled off build (invariant 2), latched once per node. A still-open
    // gate is left parked.
    final openGates = seed.existingSession?.openGateNodes ?? const <String>{};
    cursor.forEach((nodePath, node) {
      if (node.state == StepState.gated && !openGates.contains(nodePath)) {
        _scheduleRearm(id, nodePath);
      }
    });

    // D-2/D-5: own the terminal. Read-only here (the predicates are pure); the
    // actual write is scheduled off build (never a write IN build, invariant 2).
    // Breaker-exhaustion (broken ANYWHERE in the subtree) escalates + tears
    // down; otherwise a positive terminal closes. Distinguishing
    // empty-because-broken from empty-because-complete is the whole point of D-5.
    final registry =
        context.dependOnInheritedSeedOfExactType<CapabilityRegistry>();
    if (registry != null && !_terminalScheduled) {
      final broken = firstBrokenNode(
        seed.circuit,
        cursor,
        seed.bead.id,
        circuitById: registry.circuit,
      );
      if (broken != null) {
        // Capture-only (FT-1): record WHICH node exhausted + its reason (read
        // from the cursor's persisted telemetry) beside the escalation marker.
        // Read-only here; the write is scheduled off build (invariant 2).
        final reason = truncateReason(
          '${broken.nodePath}: ${broken.node.failureReason ?? ''}',
        );
        _scheduleEscalation(id, reason);
      } else if (isCircuitComplete(
        seed.circuit,
        cursor,
        seed.bead.id,
        circuitById: registry.circuit,
      )) {
        _scheduleClose(id);
      }
    }

    // The per-session ambient values (ADR-0008 Decision 3, 2026-07-02 — the
    // context rip-out): the SessionHandle (value-equal, so a same-id re-provide
    // never notifies), the Workspace (computed HERE from the per-substation
    // SourceControl — the synthetic placeholder covers the no-source-control
    // offline case, where nothing provisions nor lands), and the SiblingView
    // (this session's whole cursor + results — capabilities read it with the
    // effect verb; nothing registers on it, so a fresh instance per build
    // notifies nobody).
    final services =
        context.dependOnInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    final sc = services.sourceControl;
    final beadId = seed.bead.id;
    final workspace = Workspace(
      workspaceDir: sc?.workspaceFor(beadId) ?? '/grid/workspaces/$beadId',
      branch: sc?.branchFor(beadId) ?? '',
      baseBranch: sc?.baseBranch ?? 'main',
    );
    return InheritedSeed<SessionHandle>(
      value: SessionHandle(id),
      child: InheritedSeed<Workspace>(
        value: workspace,
        child: InheritedSeed<SiblingView>(
          value: SiblingView(cursor: cursor, results: results),
          child: CircuitScope(
            circuit: seed.circuit,
            cursor: cursor,
            nodePath: seed.bead.id,
          ),
        ),
      ),
    );
  }
}
