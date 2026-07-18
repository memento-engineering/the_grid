/// The molecule model's bead-metadata schema (`DESIGN-tg-pm6.md` §4, R1) — the
/// key namespaces + declarative value vocabulary a `type=molecule`/`type=step`
/// bead carries. Constants only: the write/read builders (`stepBeadMetadata`,
/// `projectMoleculeCursor`) and `instantiateMolecule` (cook's role) live in
/// `molecule_codec.dart`, which depends on this file — never the reverse.
///
/// Zero dependencies, like `bead_path_key.dart`: cross-references to types that
/// live elsewhere (`NodeCursor`, `StepKind`, `depTerminalPath`, …) are written
/// as plain code text, not dartdoc `[links]`, so this file never has to import
/// the rest of the package just to document itself.
///
/// Never edits `domain/session_bead.dart`. `ResultKeys` there is reused
/// VERBATIM on the step bead — only its host bead moves, from the session to
/// the step — so this file does not re-declare a result namespace.
library;

/// Metadata keys on a `type=molecule` bead — one bead per circuit instance
/// (the root circuit a session mints, or a nested `SubCircuitStep`'s own
/// circuit, recursively).
abstract final class MoleculeCircuitKeys {
  /// The flat-key namespace prefix (a scan/grep anchor, like every other
  /// namespace in this file).
  static const prefix = 'grid.circuit.';

  /// The `Circuit.id` this bead instantiates — the FORMULA identity (Decided
  /// item 8: a circuit is a Dart-implemented formula; mounting it plays cook's
  /// role).
  static const formula = 'grid.circuit.formula';

  /// The owning session bead id — the JOIN key R5a's read projection buckets
  /// molecule/step beads by (mirrors `MoleculeStepKeys.session`).
  static const session = 'grid.circuit.session';

  /// The canonical `BeadPathKey.canonical` string identifying this molecule's
  /// place in the breadcrumb (R7). Declared here, NOT stamped by
  /// `instantiateMolecule`: the bead id this molecule receives does not exist
  /// until the `bd create --graph` pour returns it (R6), so the crumb is a
  /// POST-POUR write — out of a pure plan-builder's reach by construction.
  static const crumb = 'grid.circuit.crumb';
}

/// Metadata keys on a `type=step` bead — one bead per leaf `CapabilityStep`.
///
/// NO `{nodePath}` infix anywhere in this namespace — unlike the flat model's
/// `grid.cursor.{nodePath}.{field}` keys, the bead itself IS the node, so
/// there is nothing left to disambiguate per-key. And deliberately NO
/// `rewindCount` key (Decided item 7): the incarnation axis is DERIVED, never
/// persisted — `live_frontier.dart` (R4) layers it into the projected
/// `NodeCursor.rewindCount` in memory only, every time the effective cursor is
/// computed.
abstract final class MoleculeStepKeys {
  static const prefix = 'grid.step.';

  /// The sibling-unique step id (Decided item 4, Flutter's rule inherited): a
  /// swarm member's distinguisher (e.g. the rubric id) IS its step id — never
  /// the bare capability role, which a same-capability fan-out would collide
  /// on.
  static const stepId = 'grid.step.id';

  /// The `CapabilityRegistry` id this step resolves to.
  static const capability = 'grid.step.capability';

  /// `StepKind.job` or `StepKind.daemon`, by `.name`.
  static const kind = 'grid.step.kind';

  /// The engine `nodePath` coordinate (`stepPath`-joined — `sdk/frontier.dart`)
  /// — the SAME in-run address space the flat model's cursor already uses.
  /// `projectMoleculeCursor` keys the returned `CircuitCursor` by this field,
  /// and its `beadIdByNodePath` reverse-lookup resolves it back to this bead's
  /// id.
  static const path = 'grid.step.path';

  /// The fine `StepState` name (6-valued). bd's OWN open/closed STATUS is the
  /// coarse axis (2-valued) — `projectMoleculeCursor` falls back to it when
  /// this key is absent (a freshly-minted step bead has no fine state yet;
  /// that is honest, native "nothing has run" — not a bug to paper over with a
  /// stamped default).
  static const state = 'grid.step.state';

  /// The supervised-restart counter (D-5) — unchanged semantics from the flat
  /// model's `CursorKeys.restartCount`, just re-homed onto the step bead
  /// itself.
  static const restartCount = 'grid.step.restartCount';

  /// The backoff cooldown deadline (ISO-8601 UTC), unchanged semantics.
  static const cooldownUntil = 'grid.step.cooldownUntil';

  /// The truncated failure diagnostic (capture-only prose — see
  /// `truncateReason` in `domain/session_bead.dart`, reused verbatim). Never
  /// gates orchestration; nothing that decides what runs next reads this key.
  static const failureReason = 'grid.step.failureReason';

  /// The swarm TYPE this step is a fan-out member of — an OPEN string
  /// vocabulary (`'committee'` first, Decided item 11: never a closed enum, so
  /// a new swarm type is new circuit content, not new engine code). Absent
  /// for a non-swarm step.
  static const swarm = 'grid.step.swarm';

  /// The owning session bead id (the JOIN key; mirrors
  /// `MoleculeCircuitKeys.session`).
  static const session = 'grid.step.session';

  /// The canonical `BeadPathKey.canonical` string (R7) — a POST-POUR write,
  /// same reasoning as `MoleculeCircuitKeys.crumb`.
  static const crumb = 'grid.step.crumb';

  /// Capture-only FLOW TELEMETRY (FT-1 parity with the flat model) — never
  /// read on a build/orchestration path.
  static const startedAt = 'grid.step.startedAt';

  /// Capture-only flow telemetry — the terminal-transition instant.
  static const finishedAt = 'grid.step.finishedAt';

  /// Capture-only flow telemetry — the derived `finishedAt - startedAt`
  /// milliseconds.
  static const durationMs = 'grid.step.durationMs';
}

/// The vendor-owned adopt breadcrumb (R3, a later rung) — pgid/pid/token as a
/// LEASE addressed by the stable step-bead id, rather than node-owned durable
/// state (Decided item 5). A DISTINCT namespace from `MoleculeStepKeys`: ONLY
/// the process-lease vendor ever writes these keys, and the molecule codec
/// (`molecule_codec.dart`) NEVER reads them — structurally proven in
/// `molecule_codec_test.dart` so a future edit cannot quietly wire the two
/// together and reintroduce node-owned process identity.
abstract final class LeaseKeys {
  static const prefix = 'grid.lease.';
  static const pgid = 'grid.lease.pgid';
  static const pid = 'grid.lease.pid';
  static const token = 'grid.lease.token';
}

/// The declarative params convention naming a critic→build-target VALIDATES
/// edge (Decided item 8): a `CircuitStep` whose `params[kValidatesParam]`
/// names a sibling step id gets a `DependencyType.validates` edge to it at
/// `instantiateMolecule` time. Circuit CONTENT declares this (a power_station
/// opinion, e.g. the code asset's committee circuit); the engine only ever
/// reads the key by name, keeping it domain-free — `CircuitStep` itself
/// declares no critic→target relation.
const String kValidatesParam = 'validates';

/// The declarative params convention marking a step a member of a fan-out
/// SWARM (Decided item 11): its value is the open swarm-type vocabulary word
/// (`'committee'` first) `instantiateMolecule` stamps onto
/// `MoleculeStepKeys.swarm`. Absent for a non-swarm step — never a closed
/// enum; a new swarm type is new circuit content, not new engine code.
const String kSwarmParam = 'swarm';

/// `DependencyType.supersedes` and `DependencyType.until` are RESERVED
/// bd-native dependency vocabulary for a future rounds-materialization /
/// daemon-lifetime model (`DESIGN-tg-pm6.md` §3 conflict 7) — NOT minted
/// anywhere by this model. A rework round demotes and re-keys the SAME step
/// bead (the derived generation, R4); minting a fresh incarnation bead per
/// round would grow the molecule unboundedly and reshape identity, which
/// Decided item 2 (topology-stable breadcrumb identity) forbids. Documented
/// here, beside the vocabulary constants it sits next to, so a future reader
/// finds the reservation without having to go back to the design doc prose.
