import 'package:beads_dart/beads_dart.dart' show BeadsWorkspace, GraphSnapshot;
import 'package:grid_engine/grid_engine.dart' show SessionBeadKeys;
import 'package:grid_runtime/grid_runtime.dart'
    show BeadOwnershipPredicate, GridIssueTypes;
import 'package:path/path.dart' as p;
import 'package:state_notifier/state_notifier.dart';

import '../stores/stores.dart'
    show StoreLocator, StoreRefusal, requireAbsoluteRoot;
import '../work/work_assembly.dart' show SubstationWorkSpec;
import 'roster_outcome.dart';
import 'roster_seat.dart';

/// Owns the off-tree half of a live substation attachment.
abstract interface class SubstationProvisioner {
  /// Starts [spec]'s controller, membership, writer, root, and ownership.
  Future<void> provision(SubstationWorkSpec spec);

  /// Tears down [name]'s resources and returns the reaped worktree count.
  Future<int> decommission(String name);

  /// Every identity token the station currently owns.
  Set<String> get ownedIdentityTokens;
}

/// The mutable runtime-appended substation roster.
class SubstationRoster extends StateNotifier<AttachedRoster> {
  /// Creates a roster over [provisioner] and injected store seams.
  SubstationRoster({
    required SubstationProvisioner provisioner,
    StoreLocator? locator,
    BeadsWorkspace? Function(String root)? discoverWorkspace,
  }) : _provisioner = provisioner,
       _locator = locator ?? StoreLocator(),
       _discover =
           discoverWorkspace ??
           ((String root) => BeadsWorkspace.discover(start: root)),
       super(AttachedRoster.empty);

  final SubstationProvisioner _provisioner;
  final StoreLocator _locator;
  final BeadsWorkspace? Function(String root) _discover;

  /// Attaches a live seat after validating its identities and exact root.
  Future<RosterOutcome> attach({
    required String name,
    required String root,
    String? prefix,
  }) async {
    final resolvedPrefix = prefix == null || prefix.trim().isEmpty
        ? name
        : prefix;
    for (final token in <String>[name, resolvedPrefix]) {
      if (token.trim().isEmpty ||
          token != token.trim() ||
          token.contains(RegExp(r'\s')) ||
          token.contains('/') ||
          token.contains(r'\')) {
        return RosterOutcome.refused(
          code: 'invalid_identity',
          message:
              'attach "$name": "$token" is not a usable substation '
              'identity — names and prefixes are single tokens with no '
              'whitespace or path separators.',
        );
      }
    }

    final collisions =
        <String>{name, resolvedPrefix}
            .where(_provisioner.ownedIdentityTokens.contains)
            .toList(growable: false)
          ..sort();
    if (collisions.isNotEmpty) {
      return RosterOutcome.refused(
        code: 'identity_collision',
        message:
            'attach "$name": the station already owns '
            '${collisions.join(', ')} — ownership matches a name or prefix, '
            'so every substation must have disjoint {name, prefix} sets.',
      );
    }

    final canonicalRoot = p.canonicalize(root);
    try {
      requireAbsoluteRoot(root, 'attach "$name"');
      _locator.locateWorkStore(root: canonicalRoot, substationName: name);
    } on ArgumentError catch (error) {
      return RosterOutcome.refused(
        code: 'root_invalid',
        message: 'attach "$name": ${error.message}',
      );
    } on StoreRefusal catch (error) {
      return RosterOutcome.refused(
        code: 'store_absent',
        message: 'attach "$name": $error',
      );
    }
    final workspace = _discover(root);
    if (workspace == null ||
        !p.equals(p.canonicalize(workspace.root), canonicalRoot)) {
      return RosterOutcome.refused(
        code: 'store_unparsed',
        message:
            'attach "$name": could not parse the work store at $root/.beads '
            '(resolved: ${workspace?.root ?? 'nothing'}).',
      );
    }

    final spec = SubstationWorkSpec(
      name: name,
      root: root,
      prefix: resolvedPrefix,
    );
    try {
      await _provisioner.provision(spec);
    } on Object catch (error) {
      return RosterOutcome.refused(
        code: 'provision_failed',
        message: 'attach "$name": $error',
      );
    }
    state = AttachedRoster(<RosterSeat>[...state.seats, RosterSeat(spec)]);
    return RosterOutcome.attached(
      name: name,
      prefix: resolvedPrefix,
      root: root,
    );
  }

  /// Detaches an attached seat, refusing live sessions unless [force].
  Future<RosterOutcome> detach({
    required String name,
    required Set<String> Function(SubstationWorkSpec spec) inFlightOf,
    bool force = false,
  }) async {
    final seat = state.seatOf(name);
    if (seat == null) {
      return RosterOutcome.refused(
        code: 'not_attached',
        message:
            'detach "$name": no attached seat has that name. Runtime '
            'attach/detach mutate the appended roster layer only; coded '
            'substations are changed in code and bounced.',
      );
    }
    if (seat.isDraining) {
      return RosterOutcome.refused(
        code: 'already_draining',
        message: 'detach "$name": the substation is already draining.',
      );
    }
    final inFlight = Set<String>.unmodifiable(inFlightOf(seat.spec));
    if (inFlight.isNotEmpty && !force) {
      final ids = inFlight.toList(growable: false)..sort();
      return RosterOutcome.refused(
        code: 'sessions_live',
        message:
            'detach "$name": ${ids.length} live session(s) on '
            '${ids.join(', ')} — refused unless idle. Pass --force to drain.',
      );
    }
    if (inFlight.isNotEmpty) {
      state = AttachedRoster(<RosterSeat>[
        for (final other in state.seats)
          if (other.spec.name == name) other.draining(inFlight) else other,
      ]);
      return RosterOutcome.draining(name: name, inFlight: inFlight);
    }
    return _finalize(name);
  }

  /// Finalises draining seats that have become idle.
  Future<void> settleDrains(
    Set<String> Function(SubstationWorkSpec spec) inFlightOf,
  ) async {
    for (final seat in state.seats.toList(growable: false)) {
      if (!seat.isDraining) continue;
      final inFlight = inFlightOf(seat.spec);
      if (inFlight.isEmpty) {
        await _finalize(seat.spec.name);
        continue;
      }
      if (SubstationDrain(inFlight) == SubstationDrain(seat.drainIds)) {
        continue;
      }
      state = AttachedRoster(<RosterSeat>[
        for (final other in state.seats)
          if (other.spec.name == seat.spec.name)
            other.draining(inFlight)
          else
            other,
      ]);
    }
  }

  Future<RosterOutcome> _finalize(String name) async {
    state = AttachedRoster(<RosterSeat>[
      for (final seat in state.seats)
        if (seat.spec.name != name) seat,
    ]);
    final reaped = await _provisioner.decommission(name);
    return RosterOutcome.detached(name: name, reapedWorktrees: reaped);
  }
}

/// Returns open-session work beads owned by [spec], stripping rework rounds.
Set<String> liveWorkBeadsFor(SubstationWorkSpec spec, GraphSnapshot state) {
  final owned = <String>{spec.name, spec.prefix};
  final ids = <String>{};
  for (final bead in state.beads) {
    if (bead.issueType != GridIssueTypes.session || bead.isClosed) continue;
    final key = bead.metadata[SessionBeadKeys.workBead];
    if (key is! String || key.isEmpty) continue;
    final workBeadId = key.split('#').first;
    if (BeadOwnershipPredicate.ownedPrefixOf(workBeadId, owned) != null) {
      ids.add(workBeadId);
    }
  }
  return ids;
}
