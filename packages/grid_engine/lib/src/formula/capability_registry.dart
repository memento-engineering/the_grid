/// The engine's capability/formula resolution seam (ADR-0008 D4 / M4-P1 §3,
/// Track D).
///
/// The `FormulaScope` inflater resolves THREE things through one stable ambient
/// [CapabilityRegistry] (`updateShouldNotify => false`, D-6): a (sub-)formula by
/// id, the engine leaf Seed for an eligible [CapabilityStep] (a `CapabilityHost`
/// in the default registry — Track E; a fake in Track D tests), and the wall
/// clock the frontier predicate reads (injectable so the predicate stays pure).
///
/// The author never sees this — it is the engine's opinion bundle (the
/// depth-analogue of the P0 `SessionResolver`). Provided via
/// `InheritedSeed<CapabilityRegistry>` typed to the INTERFACE (genesis's
/// exact-type lookup means a concrete subtype could not be found as
/// `CapabilityRegistry`).
library;

import 'package:genesis_tree/genesis_tree.dart';

import '../sdk/cursor.dart';
import '../sdk/formula.dart';
import 'session_handle.dart';

/// Everything the registry's [CapabilityRegistry.host] needs to mount one
/// eligible [CapabilityStep] as an engine leaf.
///
/// Slimmed 2026-07-02 (the context rip-out): the work `Bead` and the session
/// `SiblingView` are AMBIENT (mounted by `WorkBead`/`SessionScope`) — an effect
/// reads them with the non-binding lookup, so the mount threads only the
/// step's own identity + supervision params.
class StepMount {
  /// Bundles the [step], its full [nodePath], the resolved [session], the
  /// step's current [node] cursor (identity/incarnation for respawn — D-4), the
  /// incarnation-keyed reconcile [key], and the owning formula's supervision
  /// params ([backoff]/[maxRestarts]) the host uses to author the
  /// supervised-restart cursor on failure (D-5).
  const StepMount({
    required this.step,
    required this.nodePath,
    required this.session,
    required this.node,
    required this.key,
    this.backoff = Backoff.standard,
    this.maxRestarts = 3,
  });

  /// The eligible step to mount.
  final CapabilityStep step;

  /// The step's FULL path within the formula tree (`'$parentNodePath/$stepId'`)
  /// — the cursor key + the per-step provider-name segment.
  final String nodePath;

  /// The adopt-or-minted session this leaf writes its cursor onto.
  final SessionHandle session;

  /// The step's current cursor entry (drives respawn-or-skip + the incarnation).
  final NodeCursor node;

  /// The incarnation-keyed reconcile identity (`ValueKey('$nodePath#$restartCount')`)
  /// — a supervised restart bumps `restartCount`, changing the key, so keyed
  /// reconcile unmounts the old incarnation and mounts the new.
  final Key key;

  /// The owning formula's backoff schedule (D-5) — the host computes the
  /// cooldown for the next restart attempt from it on failure.
  final Backoff backoff;

  /// The owning formula's restart budget (D-5) — at `restartCount >= maxRestarts`
  /// the host writes the exhausted failure (no cooldown) and SessionScope
  /// escalates.
  final int maxRestarts;
}

/// The engine's capability/formula/clock resolution seam (Track D). The default
/// impl ships in the extension (Track E/H); tests inject a fake.
abstract interface class CapabilityRegistry {
  /// Resolves a (sub-)formula by [formulaId]; null when unknown (fail-closed —
  /// the predicate then never satisfies a dep on it, and the inflater skips it).
  Formula? formula(String formulaId);

  /// Builds the engine leaf Seed for the eligible [mount.step] — a
  /// `CapabilityHost` in the default registry (Track E), a recording fake in
  /// Track D tests. NEVER a Seed the author authored; the carrier is
  /// engine-private (ADR-0008 D2).
  Seed host(StepMount mount);

  /// The wall clock the frontier predicate reads (the supervised-restart
  /// cooldown gate). Injectable so the predicate stays pure (the kernel owns the
  /// real clock + backoff timer — D-6/Track G).
  DateTime now();
}
