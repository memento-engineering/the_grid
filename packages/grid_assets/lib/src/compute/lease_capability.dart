/// Lease-as-Capability — the COMPUTE domain's engine wrapper (ADR-0011 D3 + the
/// SCRATCH "Lease ≈ a Capability" call; M6 DoD-1's engine wrapper).
///
/// A [LeaseCapability] mounts at the engine's `SessionResolver`/Capability seam
/// (resolved by the registry like every other [Capability], mirroring
/// `code_capabilities.dart`). Its Branch lifecycle IS the lease lifecycle: on
/// MOUNT (`run`) it ACQUIRES a lease on a peer's slot and DISPATCHES the bounded
/// compute "use"; on UNMOUNT/dispose (`teardown`) it RELEASES the lease. "A
/// remote agent is just a capability that runs elsewhere."
///
/// Lifecycle is guarded like the engine's `EffectSeed` (cancelled/completed):
///  - it polls [CapabilityContext.cancel] across every async gap (a dispose mid-
///    acquire releases immediately + skips the dispatch);
///  - it RELEASES on dispose EVEN IF cancelled;
///  - release is once-only + idempotent (a re-reaped lease is fine).
///
/// The per-mount lease handle lives in an [Expando] keyed by the
/// [CapabilityContext] (the SAME instance the host hands to `run` + `teardown`),
/// so this capability stays a stateless, const-shareable description — two
/// concurrent mounts never clobber each other's grant.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_federation/grid_federation.dart';

import 'compute_command.dart';

void _noLog(String _) {}

/// The mutable, per-mount lease hold (keyed off the [CapabilityContext]).
class _LeaseHold {
  LeaseGrant? grant;
}

/// Leases a compute slot from a peer ([client]) and dispatches a bounded
/// [command] there, holding the lease for the node's lifetime.
class LeaseCapability extends ServiceCapability {
  /// Creates a lease capability over the bus [client], dispatching [command]
  /// (the bounded compute use the lessor runs) on the leased slot. [kind]
  /// defaults to [kComputeKind]; [lessee] defaults to the work bead id at mount.
  LeaseCapability({
    required this.client,
    required this.command,
    this.kind = kComputeKind,
    this.lessee = '',
    void Function(String)? onLog,
  }) : _onLog = onLog ?? _noLog;

  /// The bus to the lessor peer (the pluggable, kind-agnostic transport seam).
  final StationClient client;

  /// The bounded compute use dispatched on the leased slot.
  final DispatchCommand command;

  /// The resource-asset kind to lease.
  final String kind;

  /// The lessee station id (empty ⇒ the work bead id at mount).
  final String lessee;

  final void Function(String) _onLog;

  /// Per-mount lease state, keyed by the unique [CapabilityContext] the host
  /// builds (the same instance reaches `run` + `teardown`), so this capability
  /// holds NO mutable cross-mount state and is safe to share across nodes.
  static final Expando<_LeaseHold> _holds = Expando<_LeaseHold>('grid-lease-hold');

  @override
  Future<StepOutcome> run(CapabilityContext ctx) async {
    final hold = _holds[ctx] = _LeaseHold();
    final who = lessee.isEmpty ? ctx.beadId : lessee;
    // A stable per-node idempotency key so a retried lease/dispatch dedups at the
    // owner (never a second grant or a second run — ADR-0011 lossy-bus hazard).
    final idem = '$who/${ctx.nodePath}';

    // ACQUIRE on mount.
    final LeaseGrant grant;
    try {
      grant = await client.requestLease(
        LeaseRequest(lessee: who, kind: kind, idempotencyKey: idem),
      );
    } on LeaseDeniedException catch (e) {
      return Failed('lease denied: ${e.message}');
    }
    // A dispose raced the acquire: release the just-granted slot now (teardown
    // saw no grant) and skip the dispatch.
    if (ctx.cancel.isCancelled) {
      await _safeRelease(grant);
      return const Failed('cancelled');
    }
    hold.grant = grant; // teardown releases this on unmount/dispose
    _onLog(
      'leased ${grant.leaseId} on ${grant.station} (fence ${grant.fencingToken})',
    );

    // DISPATCH the bounded compute use on the leased slot.
    final Map<String, dynamic> raw;
    try {
      raw = await client.dispatch(grant, command.toJson(), idempotencyKey: idem);
    } on LeaseInvalidException catch (e) {
      return Failed('dispatch failed: ${e.message}');
    }
    if (ctx.cancel.isCancelled) return const Failed('cancelled');

    final result = CommandResult.fromJson(raw);
    return result.ok
        ? Ok({
            'lease': grant.leaseId,
            'exitCode': '${result.exitCode}',
            'durationMs': '${result.durationMs}',
          })
        : Failed('compute exit ${result.exitCode}: ${result.stderr.trim()}');
  }

  @override
  Future<void> teardown(CapabilityContext ctx) async {
    final hold = _holds[ctx];
    final grant = hold?.grant;
    if (grant == null) return; // never acquired, or already released
    hold!.grant = null; // once-only: guard a double release
    await _safeRelease(grant);
  }

  /// Releases [grant], swallowing a federation error so release stays idempotent
  /// for the holder (an already-reaped/invalid lease is not an error).
  Future<void> _safeRelease(LeaseGrant grant) async {
    try {
      await client.release(grant);
      _onLog('released ${grant.leaseId}');
    } on FederationException {
      // Already reaped/invalid — release is idempotent for the holder.
    }
  }
}
