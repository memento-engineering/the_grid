import 'package:grid_controller/grid_controller.dart';

/// The bead-shaped ownership gate (ADR-0006 Decision 1; ADR-0000 A32) — the
/// dispatch-side analog of grid_reconciler's `OwnsRigs.owns(Convergence)`.
///
/// M2's `OwnsRigs` reads `convergence.metadata.rig`, a key gc stamps **only**
/// into convergence beads, so it is structurally uncallable on a plain ready
/// work [Bead] (`readyBeads` returns `List<Bead>`). The dogfood dispatcher and
/// the [GridBeadWriter] chokepoint both need to classify ownership of a plain
/// bead, so this predicate derives the bead's rig from the **same axis the
/// dogfood rig uses** — the **issue-id PREFIX** (primary, ADR-0006 ratified)
/// and, optionally, `metadata.rig` (belt-and-suspenders).
///
/// **The shared artifact with the M2 actuator is the rig allow-set
/// `Set<String>`, not this object** (ADR-0000 A32): the SAME `Set<String>`
/// instance feeds both `OwnsRigs(Convergence)` (actuation) and this predicate
/// (dispatch + the write chokepoint), so the two gates cannot drift. The
/// dogfood seeds it `{tgdog}` (A35).
///
/// **Fail-closed.** A bead with no owned prefix and no owned `metadata.rig` is
/// **not owned** — never dispatched, never mutated. The empty allow-set owns
/// nothing.
class BeadOwnershipPredicate {
  /// Builds a predicate over [rigs] — the shared allow-set. Each entry is both
  /// a rig name (matched against `metadata.rig`) and an issue-id prefix
  /// (matched against the id's leading dash-delimited segment), so the dogfood
  /// rig `tgdog` accepts both `metadata.rig == "tgdog"` and an id like
  /// `tgdog-abc123`.
  ///
  /// When [requireRigMarker] is true, a bead must ALSO carry
  /// `metadata.rig == <owned>` to be owned — the belt-and-suspenders posture
  /// ADR-0006 offers (prefix primary + optional marker). Default false: the
  /// id-prefix alone is sufficient (a freshly minted session bead may carry the
  /// marker only after its first metadata stamp, but its id prefix is owned
  /// from birth).
  BeadOwnershipPredicate(Iterable<String> rigs, {this.requireRigMarker = false})
    : _rigs = rigs.toSet();

  final Set<String> _rigs;
  final bool requireRigMarker;

  /// The shared rig allow-set (read-only view) — exposed so the dispatcher and
  /// the chokepoint can be constructed from the identical instance.
  Set<String> get rigs => Set<String>.unmodifiable(_rigs);

  /// Whether the_grid owns [bead] — may dispatch against it and mutate it.
  bool owns(Bead bead) => _ownsRig(rigOf(bead), markerOf(bead.metadata));

  /// Whether the_grid owns a bead with the given [id] and [metadata], without a
  /// full [Bead] in hand — the form the chokepoint uses on a freshly minted
  /// session bead it is about to write (it knows the id + the metadata it is
  /// stamping).
  bool ownsTarget({
    required String id,
    Map<String, dynamic> metadata = const {},
  }) => _ownsRig(prefixOf(id), markerOf(metadata));

  bool _ownsRig(String? prefix, String? marker) {
    if (requireRigMarker) {
      // Belt-and-suspenders: BOTH the prefix and the marker must be owned.
      return prefix != null &&
          _rigs.contains(prefix) &&
          marker != null &&
          _rigs.contains(marker);
    }
    // Prefix OR an explicit owned marker (a bead may be owned by either axis).
    if (prefix != null && _rigs.contains(prefix)) return true;
    if (marker != null && _rigs.contains(marker)) return true;
    return false;
  }

  /// The bead's rig as derived from its axes (the owned prefix if any, else the
  /// `metadata.rig` marker) — for diagnostics / logging.
  String? rigOf(Bead bead) => prefixOf(bead.id) ?? markerOf(bead.metadata);

  /// The leading dash-delimited segment of an issue id (gc's rig prefix axis,
  /// ADR-0002 D2). `tgdog-abc123` → `tgdog`; a bare id with no dash → null.
  static String? prefixOf(String id) {
    final dash = id.indexOf('-');
    if (dash <= 0) return null;
    return id.substring(0, dash);
  }

  /// The explicit `metadata.rig` marker (the alternative axis), or null.
  static String? markerOf(Map<String, dynamic> metadata) {
    final rig = metadata['rig'];
    if (rig is String && rig.isNotEmpty) return rig;
    return null;
  }
}
