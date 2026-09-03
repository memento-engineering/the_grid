/// One derived-obligation query and its repair (§5, "follow-up repairs, not
/// tails").
///
/// The §5 invariant every implementation must hold: the query keys off the
/// EXTERNAL state it repairs, never off the projection the repair itself
/// mutates — a failed downstream write has to leave the obligation OPEN, and
/// gate obligations need a query in both directions.
library;

import 'package:meta/meta.dart';

import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';

/// A standing query over the projections plus the repair it authorizes.
///
/// [repair] may do external work (a bd write, a GitHub probe); it returns the
/// records that make the repair auditable, and the tick — never the query —
/// owns the fenced append.
abstract class ObligationQuery {
  const ObligationQuery();

  /// Stable identifier, used in telemetry and in the Stage-1 stuck-obligation
  /// accounting.
  String get name;

  /// The standing SELECT over the projections.
  String get sql;

  /// Bind parameters for [sql].
  Map<String, Object?> get parameters => const {};

  /// Turns the query's rows into the records to append. Returning an empty
  /// list is the fixpoint signal for this query.
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows);
}

/// One record a repair wants appended, with the envelope provenance that
/// repair carries.
///
/// Provenance is the QUERY's call, not the tick's: a gate closed because the
/// session is terminal is `observed`; a settling `effect.ack` recovered from a
/// GitHub probe is `inferred` with a basis (§2, `ck_prov`).
@immutable
final class ObligationAppend {
  const ObligationAppend(
    this.record, {
    this.substation,
    this.provenance = TrajectoryProvenance.observed,
    this.provenanceBasis,
  });

  final TrajectoryRecord record;

  /// The derivation layer's substation for this record when the repair derived
  /// one (stage1-wiring §2.2's substation row: `ownedPrefixOf` over the
  /// allowSet, plus
  /// the deterministic `unowned` fallback). Null falls back to the appender's
  /// own prefix derivation — a repair's substation must not differ from the
  /// substation the same record would carry had it been derived at an
  /// observation site.
  final String? substation;

  final TrajectoryProvenance provenance;
  final String? provenanceBasis;
}

/// Stage 0's obligation set: EMPTY, by design (§9).
///
/// Each obligation arms with its record family's stage — the attempt/step
/// queries at Stage 1, the admission/grant queries at Stage 3 — so Stage 0
/// ships the loop and nothing to run in it.
const List<ObligationQuery> kStage0ObligationQueries = <ObligationQuery>[];
