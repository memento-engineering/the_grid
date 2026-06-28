/// The engine-private session lifecycle owner (ADR-0008 D4 / M4-P1 D-2).
///
/// `SessionScope` is mounted by `WorkBead` ABOVE the formula fan-out (the
/// resolver returns it). It **adopt-or-mints** the the_grid session bead, holds
/// `{resolving | ready | failed}`, and on `ready` provides a stable
/// `InheritedSeed<SessionHandle>` over the `FormulaScope` so the inflater + every
/// `CapabilityHost` attach to the SAME session — establishing the session is a
/// tree *state* (a loading state, `const Idle()` until resolved), not a
/// synchronous id injection. This is the "Route resolves before its Page
/// attaches" shape (an abstraction, not a literal router).
///
/// It owns the session lifecycle END-TO-END: it also CLOSES the session on the
/// formula's positive terminal (D-2 — one owner for open+close, not the terminal
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
import 'package:grid_controller/grid_controller.dart';

import '../domain/session_projection.dart';
import '../effect/effect_context.dart';
import '../kernel/idle.dart';
import '../sdk/cursor.dart';
import '../sdk/formula.dart';
import '../sdk/frontier.dart';
import 'capability_registry.dart';
import 'formula_scope.dart';
import 'session_handle.dart';
import 'stable_inherited.dart';

/// The adopt-or-mint session lifecycle owner for one work [bead]'s [formula]
/// (D-2). Key it `ValueKey('${bead.id}:session')` so it persists across cursor
/// ticks while the work node keeps its branch identity.
class SessionScope extends StatefulSeed {
  /// Creates the scope for [bead] running [formula], with the bead's linked
  /// [existingSession] (null until a session exists — then `SessionScope` mints
  /// one; non-null → it adopts).
  const SessionScope({
    required this.bead,
    required this.formula,
    this.existingSession,
    super.key,
  });

  /// The work bead this session drives (its id is the formula's root nodePath
  /// and the mint's `work_bead` linkage).
  final Bead bead;

  /// The root formula for this work bead.
  final Formula formula;

  /// The bead's linked session projection (the JOIN row) — null when no session
  /// exists yet (mint), non-null once the bridge projects one (adopt). Its
  /// [SessionProjection.cursor] threads the per-node cursor down to
  /// `FormulaScope` pull-free (A39).
  final SessionProjection? existingSession;

  @override
  State<SessionScope> createState() => SessionScopeState();
}

/// The `{resolving | ready | failed}` lifecycle (D-2). The async-gap guards
/// (`_cancelled` set first in `dispose`, `context.mounted` after every await,
/// the captured `_ctx`) mirror `EffectSeedState`.
class SessionScopeState extends State<SessionScope> {
  EffectContext? _ctx;
  String? _sessionId;
  bool _resolving = true;
  bool _failed = false;
  bool _cancelled = false;
  bool _closeScheduled = false;

  @override
  void didChangeDependencies() {
    // Capture the context once (the writer is used across async gaps; `context`
    // throws post-unmount).
    _ctx ??= context.dependOnInheritedSeedOfExactType<EffectContext>();
    assert(
      _ctx != null,
      'SessionScope requires an ambient InheritedSeed<EffectContext>',
    );
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
    if (_closeScheduled) return;
    _closeScheduled = true;
    scheduleMicrotask(() => unawaited(_ctx?.writer.close(id)));
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

    // D-2: own the close on the formula's positive terminal. Read-only here
    // (isFormulaComplete is pure); the actual write is scheduled off build.
    final registry =
        context.dependOnInheritedSeedOfExactType<CapabilityRegistry>();
    if (registry != null &&
        isFormulaComplete(
          seed.formula,
          cursor,
          seed.bead.id,
          formulaById: registry.formula,
        )) {
      _scheduleClose(id);
    }

    // STABLE (D-6): the resolving→ready transition is a structural child
    // appearance (this InheritedSeed mounts fresh), never an in-place value
    // swap — so it must never fan-rebuild the formula subtree.
    return StableInheritedSeed<SessionHandle>(
      value: SessionHandle(id),
      child: FormulaScope(
        formula: seed.formula,
        cursor: cursor,
        nodePath: seed.bead.id,
      ),
    );
  }
}
