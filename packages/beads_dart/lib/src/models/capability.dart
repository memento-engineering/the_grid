/// bd's NATIVE cross-project capability vocabulary — three conventions the
/// `bd` binary itself implements, modelled here so callers spell them once.
///
/// * a consumer carries a dependency row on `external:<project>:<capability>`
///   (`bd dep add <issue> external:<project>:<capability>`);
/// * the provider bead carries the label `export:<capability>`;
/// * `bd ship <capability>` validates that the provider is CLOSED and adds
///   `provides:<capability>`, which is what resolves the consumer's row.
///
/// These live in `beads_dart` because they are bd facts, not the_grid
/// opinions: the engine's frontier, the station's writer and the authoring
/// verb all read the SAME strings, and none of them may invent a second
/// spelling (`the_grid#the-grid-is-a-beads-controller`).
library;

/// The `external:` dependency-row form: a blocker that lives in another bd
/// project, named by a capability rather than by a foreign bead id.
class ExternalDepRef {
  /// Creates the reference `external:[project]:[capability]`.
  const ExternalDepRef({required this.project, required this.capability});

  /// The wire prefix every external dependency row carries.
  static const String scheme = 'external:';

  /// The bd project the capability is shipped from. bd resolves it through its
  /// own `external_projects` config; the grid resolves it by roster NAME.
  final String project;

  /// The capability token. By convention (tg-xh5d) it is the provider bead's
  /// own id; a NAMED capability is the fan-in form — one container bead
  /// carrying `export:<name>` whose own blockers are the prerequisites.
  final String capability;

  /// Parses [dependsOnId] as an `external:` row, or returns `null` when it is
  /// an ordinary same-store dependency target.
  ///
  /// A malformed `external:` spelling (an empty project or capability, or a
  /// missing separator) returns `null` — the caller then treats the row as a
  /// local id, which is exactly what bd does with it.
  static ExternalDepRef? parse(String dependsOnId) {
    if (!dependsOnId.startsWith(scheme)) return null;
    final rest = dependsOnId.substring(scheme.length);
    final separator = rest.indexOf(':');
    if (separator <= 0) return null;
    final project = rest.substring(0, separator);
    final capability = rest.substring(separator + 1);
    if (capability.isEmpty) return null;
    return ExternalDepRef(project: project, capability: capability);
  }

  /// The exact string bd stores in the dependency row.
  String get wire => '$scheme$project:$capability';

  @override
  bool operator ==(Object other) =>
      other is ExternalDepRef &&
      other.project == project &&
      other.capability == capability;

  @override
  int get hashCode => Object.hash(project, capability);

  @override
  String toString() => wire;
}

/// The label a bead carries to declare it OWNS [capability] — what
/// `bd ship <capability>` looks the bead up by.
String exportLabel(String capability) => 'export:$capability';

/// The label `bd ship` adds once the exporting bead is closed — the fact that
/// resolves every consumer's `external:` row.
String providesLabel(String capability) => 'provides:$capability';

/// Every capability [labels] declares an export of, in the order given.
Iterable<String> exportedCapabilities(Iterable<String> labels) sync* {
  for (final label in labels) {
    if (label.startsWith('export:') && label.length > 'export:'.length) {
      yield label.substring('export:'.length);
    }
  }
}

/// Every capability [labels] proves SHIPPED.
Iterable<String> providedCapabilities(Iterable<String> labels) sync* {
  for (final label in labels) {
    if (label.startsWith('provides:') && label.length > 'provides:'.length) {
      yield label.substring('provides:'.length);
    }
  }
}
