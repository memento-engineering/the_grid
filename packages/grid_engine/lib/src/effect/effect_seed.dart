import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:meta/meta.dart';

import '../domain/session_bead.dart';
import '../domain/session_projection.dart';
import '../domain/work_phase.dart';
import '../kernel/idle.dart';
import 'effect_context.dart';

/// The runtime heart of the M4 tree engine (ADR-0007 / M4-P0-BUILD-ORDER
/// Track C): a tree node whose Branch lifecycle IS the work-process lifecycle.
///
/// - **mount** (`initState`) → mint the session bead if needed, then spawn the
///   process for [phase] via the injected [EffectContext.provider];
/// - **a `SessionStarted` event** → persist the spawned process identity
///   (pgid/pid/token) on the session bead;
/// - **a clean completion** (`Exited` / `Died`) → advance the session cursor to
///   [advanceTo] (or close the session bead when [advanceTo] is null — a
///   positive terminal, e.g. after `land`);
/// - **unmount** (`dispose`) → kill the process.
///
/// Concrete capabilities (Track E/F's `DefaultExtension`) subclass this and
/// implement [buildConfig] (what to spawn) and [advanceTo] (the cursor on clean
/// completion). `build()` is a pure [Idle] leaf — all effect work happens in
/// `initState`/`dispose`, never in `build` (A39: observation is pull-free,
/// `build` never acts).
///
/// The effect MUST be keyed `ValueKey('${bead.id}.${phase.capId}')` by whoever
/// constructs it (Track A's resolver does) so a phase advance *swaps* the
/// effect child — unmount the old capability (its `dispose` kills), mount the
/// new (its `initState` spawns) — while the owning work node keeps its branch
/// identity. This class does NOT re-key.
abstract class EffectSeed extends StatefulSeed {
  /// Configures the effect for [bead] in [phase], with the bead's linked
  /// [session] projection (null when no session exists yet — the `implement`
  /// effect then mints one; `verify`/`land` reuse the existing
  /// [SessionProjection.sessionId] to advance the cursor pull-free, A39).
  const EffectSeed({
    required this.bead,
    required this.phase,
    this.session,
    super.key,
  });

  /// The work bead this effect drives.
  final Bead bead;

  /// The live work phase this effect mounts for (`implement` | `verify` |
  /// `land`).
  final WorkPhase phase;

  /// The bead's linked session projection, injected pull-free; null only before
  /// the `implement` effect has minted the session bead.
  final SessionProjection? session;

  /// The process to spawn for this phase — what executable, in which worktree,
  /// with what argv/lifecycle. Given the resolved [ctx] so a capability can
  /// derive the per-bead worktree path ([EffectContext.worktreeFor]). The
  /// engine layers the per-incarnation `GRID_BEAD_ID` + `GRID_INSTANCE_TOKEN`
  /// over this config's `env`.
  @protected
  RuntimeConfig buildConfig(EffectContext ctx);

  /// The cursor to write on a CLEAN completion, or null to CLOSE the session
  /// bead (a positive terminal — e.g. after `land`, there is no next phase).
  @protected
  WorkPhase? get advanceTo;

  @override
  State<EffectSeed> createState() => EffectSeedState();
}

/// The pinned [EffectSeed] lifecycle (ADR-0007 / M4-P0-BUILD-ORDER Track C).
///
/// The guards are load-bearing — Track D/E-F build on them. [_cancelled] (set
/// first in [dispose]) together with [TreeContext.mounted] (the never-throwing
/// async-gap probe) drop an out-of-band completion/started event that reaches an
/// already-unmounted (or mid-dispose) Branch. The captured [_ctx] avoids
/// touching `context` (which throws post-unmount) for the provider/writer across
/// an async gap. The engine-minted [_token] is the per-incarnation half of the
/// freshness fence; the full token-match across a controller RESTART is
/// Track D's job — Track C persists the token and provides the per-incarnation
/// subscription + these guards.
class EffectSeedState extends State<EffectSeed> {
  EffectContext? _ctx;
  String _token = '';
  String? _sessionId;
  String? _sessionName;
  StreamSubscription<RuntimeEvent>? _sub;
  bool _cancelled = false;
  bool _started = false;
  bool _completed = false;

  @override
  void didChangeDependencies() {
    // Resolve + CAPTURE the context once, into a field, so async callbacks never
    // re-resolve via `context` across an async gap (which throws after unmount).
    _ctx ??= context.dependOnInheritedSeedOfExactType<EffectContext>();
    assert(_ctx != null, 'EffectSeed mounted without an InheritedSeed<EffectContext>');
  }

  @override
  void initState() {
    _token = newInstanceToken();
    unawaited(_run());
  }

  Future<void> _run() async {
    // Yield once so `didChangeDependencies` (which captures `_ctx`) has run:
    // genesis drives `initState` THEN `didChangeDependencies` synchronously
    // within one `performRebuild`, and `initState`'s `unawaited(_run())` body
    // would otherwise touch `_ctx` before it is captured. A disposal in this
    // window is caught by the `_cancelled` / `context.mounted` guards below.
    await null;
    if (_cancelled || !context.mounted) return;
    _sessionId = seed.session?.sessionId;
    // The IMPLEMENT phase mints the session bead; verify/land reuse it.
    _sessionId ??= await _ctx!.writer.createSession(
      rig: _ctx!.stateRig,
      title: 'grid session ${seed.bead.id}',
      workBeadId: seed.bead.id,
    );
    // Disposed during the async create — abort before spawning.
    if (_cancelled || !context.mounted) return;
    // The provider session name = the session bead id.
    _sessionName = _sessionId;
    _sub = _ctx!.provider.events
        .where((e) => e.name == _sessionName)
        .listen(_onEvent);
    final base = seed.buildConfig(_ctx!);
    final config = base.copyWith(
      env: {
        ...base.env,
        // The engine-minted per-incarnation env — injected via config.env so it
        // WINS LAST over the provider's internal IncarnationEnv mint.
        'GRID_BEAD_ID': seed.bead.id,
        'GRID_INSTANCE_TOKEN': _token,
      },
    );
    _started = true;
    try {
      await _ctx!.provider.start(_sessionName!, config);
    } on SessionAlreadyExists {
      // Already live (e.g. a re-fired ready event raced the spawn) — fine.
    }
  }

  void _onEvent(RuntimeEvent e) {
    switch (e) {
      case SessionStarted s:
        unawaited(_persistIdentity(s));
      case Exited() || Died():
        unawaited(_onComplete());
      // Respawned / ActivityChanged are not lifecycle terminals here.
      default:
        break;
    }
  }

  Future<void> _persistIdentity(SessionStarted s) async {
    if (_cancelled || !context.mounted || _sessionId == null) return;
    await _ctx!.writer.update(
      _sessionId!,
      metadata: startedIdentityMetadata(
        pgid: s.pgid,
        pid: s.pid,
        token: _token,
      ),
    );
  }

  Future<void> _onComplete() async {
    if (_cancelled || !context.mounted || _sessionId == null || _completed) {
      return;
    }
    // Once-only: latch before the await so a second terminal in one incarnation
    // (a provider quirk) can't double-write the cursor. The cross-restart stale
    // completion is Track D's token-match fence.
    _completed = true;
    final target = seed.advanceTo;
    if (target != null) {
      await _ctx!.writer.update(
        _sessionId!,
        metadata: phaseCursorMetadata(target),
      );
    } else {
      // A positive terminal — no next phase; close the session bead.
      await _ctx!.writer.close(_sessionId!);
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_sub?.cancel());
    _sub = null;
    final name = _sessionName;
    // Use the captured _ctx (never `context`, which throws post-unmount). Only
    // kill if we actually reached the spawn.
    if (_started && name != null) unawaited(_ctx?.provider.stop(name));
  }

  @override
  Seed build(TreeContext context) => const Idle();
}
