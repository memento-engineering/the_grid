import 'package:beads_dart/beads_dart.dart';

import 'eligibility_basis_revision.dart';
import 'mount_eligibility.dart';

/// The frontier's reading of bd's NATIVE cross-project dependency rows
/// (`the_grid#the-grid-is-a-beads-controller`, tg-xh5d).
///
/// The grid authors no second representation of "this bead is blocked". A
/// consumer's blocker is a `bd dep` row on `external:<project>:<capability>`;
/// the capability is satisfied when the named project's store holds a CLOSED
/// bead labelled `provides:<capability>`, which is what `bd ship` writes. This
/// library adds ONLY what bd lacks: the roster resolution of `<project>` and
/// the frontier's admission decision over the union of member snapshots.

/// One `external:` row the frontier could not resolve because the roster does
/// not arm its project — the Q4 HARD refusal.
///
/// A refusal BLOCKS: an edge naming a store this station is not arming is
/// never a silent pass, and never a silent skip either.
class ExternalDepRefusal {
  /// Records that [consumerId]'s row on [ref] names an unarmed project.
  const ExternalDepRefusal({required this.consumerId, required this.ref});

  /// The blocked bead — held out of ready, fail-closed.
  final String consumerId;

  /// The unresolvable reference, exactly as bd stores it.
  final ExternalDepRef ref;

  /// The rising-edge identity of the authored row, so a resident frontier
  /// reports one authored row ONCE however often the union recomputes.
  String get edgeKey => '$consumerId->${ref.wire}';

  /// The LOUD operator line, naming both ends and [armedRoster] — the answer
  /// to "which projects could have resolved this?".
  String message(String armedRoster) =>
      'grid: REFUSED the external dependency "${ref.wire}" on "$consumerId" — '
      'this station does not arm a substation named "${ref.project}" '
      '(armed: $armedRoster). Holding $consumerId out of ready (fail-closed). '
      'Arm that substation, or re-point the row at a project the roster '
      'carries.';
}

/// What [applyExternalDeps] decided.
class ExternalDepVerdict {
  /// Creates the verdict.
  const ExternalDepVerdict({required this.admitted, required this.refusals});

  /// The candidates that survive every external row authored over them.
  final Set<String> admitted;

  /// Every unarmed-project row OBSERVED in this pass (not deduped — the caller
  /// owns the rising edge, because only it knows what it reported last pass).
  final List<ExternalDepRefusal> refusals;
}

final class _ExternalDepTarget {
  const _ExternalDepTarget({
    required this.consumerId,
    required this.ref,
    required this.target,
  });

  final String consumerId;
  final ExternalDepRef ref;
  final Bead target;
}

Iterable<_ExternalDepTarget> _externalDepTargets(
  Iterable<BeadDependency> dependencies,
  Bead? Function(ExternalDepRef ref) targetFor,
) sync* {
  for (final dependency in dependencies) {
    if (!dependency.type.affectsBlocking) continue;
    final ref = ExternalDepRef.parse(dependency.dependsOnId);
    if (ref == null) continue;
    final target = targetFor(ref);
    if (target == null || target.id != ref.capability) continue;
    yield _ExternalDepTarget(
      consumerId: dependency.issueId,
      ref: ref,
      target: target,
    );
  }
}

/// The row-named bare closes the admission pass can heal.
///
/// Only an id-shaped blocking row qualifies: its capability must exactly name
/// a core bead in the referenced member store, that bead must be CLOSED, and
/// it must still omit `provides:<its-own-id>`. Named capabilities, missing
/// projects or targets, open/non-core targets, already-provided targets and
/// non-blocking rows are deliberately absent. Results are unique and sorted by
/// their external wire spelling so the settle rail writes deterministically.
List<ExternalDepRef> healableExternalDepTargets(
  Map<String, GraphSnapshot> snapshotsByProject,
) {
  final byWire = <String, ExternalDepRef>{};
  for (final snapshot in snapshotsByProject.values) {
    for (final row in _externalDepTargets(
      snapshot.dependencies,
      (ref) => snapshotsByProject[ref.project]?.beadsById[ref.capability],
    )) {
      final target = row.target;
      if (!target.issueType.isCore ||
          !target.isClosed ||
          target.labels.contains(providesLabel(target.id))) {
        continue;
      }
      byWire[row.ref.wire] = row.ref;
    }
  }
  final refs = byWire.values.toList(growable: false)
    ..sort((left, right) => left.wire.compareTo(right.wire));
  return refs;
}

/// Makes an otherwise invisible stamped exact-id hold an eligibility refusal.
///
/// A named capability has no exact target bead in the joined graph and keeps
/// its ordinary silent-until-shipped behaviour. A CLOSED exact target is also
/// eligible at this clause: the unchanged external-dependency frontier keeps
/// the consumer out of `readyIds` until the settle rail writes `provides:` and
/// a refreshed snapshot observes it.
MountEligibilityPredicate externalDepOpenTargetClause(GraphSnapshot graph) =>
    (consumer) {
      final approval = consumer.metadata[kEligibilityApprovalKey];
      if (approval is! String || approval.isEmpty) {
        return const MountEligibilityDecision.eligible();
      }
      final openTargets = <String>{};
      for (final row in _externalDepTargets(
        graph.dependencies,
        (ref) => graph.beadsById[ref.capability],
      )) {
        if (row.consumerId == consumer.id &&
            row.target.status == BeadStatus.open) {
          openTargets.add('${row.ref.project}:${row.ref.capability}');
        }
      }
      if (openTargets.isEmpty) {
        return const MountEligibilityDecision.eligible();
      }
      final ordered = openTargets.toList()..sort();
      return MountEligibilityDecision.refused(
        clause: 'external-unshipped: ${ordered.first} (target open)',
      );
    };

/// Whether [consumer] is stamped and held by an exact-id OPEN external target.
///
/// This is intentionally only a reading of [externalDepOpenTargetClause], so
/// WorkList participation and the canonical mount-eligibility policy cannot
/// drift into two definitions of the hold.
bool hasStampedOpenExternalTargetHold(GraphSnapshot graph, Bead consumer) =>
    externalDepOpenTargetClause(graph)(consumer) is MountRefused;

/// Applies every blocking `external:` row in [dependencies] to [candidates].
///
/// A candidate is held out when any of its external rows is unsatisfied:
///
/// * the project is not armed — a REFUSAL, blocked and reported (Q4);
/// * the project is armed but the capability is not shipped — blocked
///   SILENTLY, exactly as an open local blocker blocks: "not yet" is the
///   ordinary state of a prerequisite, not a diagnosis.
///
/// Rows that are not `external:` are left entirely alone: a same-store row is
/// the origin store's own `bd ready` business, and re-judging it here would
/// double-count bd's native semantics. Non-blocking dependency types
/// (`related`, `discovered-from`, …) never hold anything out.
ExternalDepVerdict applyExternalDeps({
  required Set<String> candidates,
  required Iterable<BeadDependency> dependencies,
  required bool Function(String project) isArmed,
  required bool Function(String project, String capability) isShipped,
}) {
  final blocked = <String>{};
  final refusals = <ExternalDepRefusal>[];
  final seen = <String>{};
  for (final dep in dependencies) {
    if (!dep.type.affectsBlocking) continue;
    final ref = ExternalDepRef.parse(dep.dependsOnId);
    if (ref == null) continue;
    if (!isArmed(ref.project)) {
      final refusal = ExternalDepRefusal(consumerId: dep.issueId, ref: ref);
      if (seen.add(refusal.edgeKey)) refusals.add(refusal);
      blocked.add(dep.issueId);
      continue;
    }
    if (!isShipped(ref.project, ref.capability)) blocked.add(dep.issueId);
  }
  if (blocked.isEmpty) {
    return ExternalDepVerdict(admitted: candidates, refusals: refusals);
  }
  return ExternalDepVerdict(
    admitted: {
      for (final id in candidates)
        if (!blocked.contains(id)) id,
    },
    refusals: refusals,
  );
}

/// True when [beads] prove [capability] SHIPPED — a CLOSED bead carrying
/// `provides:<capability>`.
///
/// Closed-ness is re-checked here rather than trusted from the label alone:
/// `bd ship --force` can publish a capability off an OPEN issue, and an
/// unfinished prerequisite must keep blocking.
bool capabilityShipped(String capability, Iterable<Bead> beads) {
  final label = providesLabel(capability);
  for (final bead in beads) {
    if (bead.isClosed && bead.labels.contains(label)) return true;
  }
  return false;
}

/// The LOUD diagnostic for a station roster and a bd store that disagree about
/// which external projects exist, or `null` when [project] is in both.
///
/// The station resolves `<project>` by ROSTER NAME; bd resolves the same token
/// through its own `external_projects` config (written by the `beads
/// configure` verb). The two maps are the SAME roster, so a row bd cannot
/// resolve is a configuration gap an operator must see — never a silent skip.
String? externalProjectConfigRefusal({
  required String project,
  required Set<String> configured,
  required String store,
}) {
  if (configured.contains(project)) return null;
  return 'grid: the store "$store" has no '
      '`external_projects.$project` entry in the effective bd config rendered '
      'by `bd config show --json`, so `bd ready` there cannot resolve an '
      '"${ExternalDepRef.scheme}$project:…" row on its own (the grid frontier '
      'still blocks on it, by roster name). Configured: '
      '${configured.isEmpty ? '<none>' : (configured.toList()..sort()).join(', ')}. '
      'Run the beads configure verb for this store.';
}
