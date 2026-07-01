/// Lease-as-Capability — the COMPUTE domain's engine wrapper (ADR-0011 D3 + the
/// SCRATCH "Lease ≈ a Capability" call; M6 DoD-1's engine wrapper).
///
/// A HELD lease as an [Allocation] (ADR-0009 D6): the engine drives a
/// [LeaseCapability] as a [LeaseAllocation] (via [LeasePlan]) — [acquire]
/// requests a slot on a peer, [dispatchOn] runs the bounded compute "use" there.
/// It is a JOB lease (bounded, respawn-or-skip): the dispatch runs to completion
/// and the allocation reports `complete`; `dispose` (unmount) RELEASES the lease.
/// "A remote agent is just a capability that runs elsewhere."
///
/// The per-mount grant lives as a [LeaseAllocation] instance field (the old
/// `Expando<_LeaseHold>` — the ADR-0009 D1 smell — dissolved). Cancellation +
/// once-only release are the [LeaseAllocation]'s discipline: a dispose racing the
/// acquire releases the just-bound slot; a re-reaped lease is a no-op.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_federation/grid_federation.dart';

import '../lease/lease_allocation.dart';
import 'compute_command.dart';

void _noLog(String _) {}

/// Leases a compute slot from a peer ([client]) and dispatches a bounded
/// [command] there, holding the lease for the node's lifetime.
class LeaseCapability extends ServiceCapability with LeasePlan {
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

  /// A stable per-node idempotency key so a retried lease/dispatch dedups at the
  /// owner (never a second grant or a second run — the lossy-bus hazard).
  String _idem(CapabilityContext ctx) =>
      '${lessee.isEmpty ? ctx.beadId : lessee}/${ctx.nodePath}';

  @override
  Future<LeaseResolution> acquire(CapabilityContext ctx) async {
    final who = lessee.isEmpty ? ctx.beadId : lessee;
    final LeaseGrant grant;
    try {
      grant = await client.requestLease(
        LeaseRequest(lessee: who, kind: kind, idempotencyKey: _idem(ctx)),
      );
    } on LeaseDeniedException catch (e) {
      return LeaseUnavailable('lease denied: ${e.message}');
    }
    _onLog(
      'leased ${grant.leaseId} on ${grant.station} (fence ${grant.fencingToken})',
    );
    return LeaseBound(client, grant);
  }

  @override
  Future<StepOutcome> dispatchOn(
    StationClient c,
    LeaseGrant grant,
    CapabilityContext ctx,
  ) async {
    final Map<String, dynamic> raw;
    try {
      raw = await c.dispatch(grant, command.toJson(), idempotencyKey: _idem(ctx));
    } on LeaseInvalidException catch (e) {
      return Failed('dispatch failed: ${e.message}');
    }
    final result = CommandResult.fromJson(raw);
    return result.ok
        ? Ok({
            'lease': grant.leaseId,
            'exitCode': '${result.exitCode}',
            'durationMs': '${result.durationMs}',
          })
        : Failed('compute exit ${result.exitCode}: ${result.stderr.trim()}');
  }
}
