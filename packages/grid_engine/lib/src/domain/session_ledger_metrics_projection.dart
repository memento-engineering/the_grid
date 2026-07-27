import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../molecule/molecule_codec.dart' show supersedesDepthByStepId;
import '../molecule/molecule_schema.dart' show MoleculeStepKeys;
import 'session_bead.dart';

part 'session_ledger_metrics_projection.freezed.dart';

enum LedgerGrade { a, b, c, d, e, f }

@freezed
sealed class ResultTransport with _$ResultTransport {
  const factory ResultTransport.absent() = ResultTransportAbsent;
  const factory ResultTransport.failClosedDefault() =
      ResultTransportFailClosedDefault;
  const factory ResultTransport.operatorRuling() =
      ResultTransportOperatorRuling;
  const factory ResultTransport.reported(String value) =
      ResultTransportReported;
}

@freezed
abstract class MetricsDecodeIssue with _$MetricsDecodeIssue {
  const factory MetricsDecodeIssue({
    required String beadId,
    String? sessionId,
    String? nodePath,
    required String field,
    required String wireValue,
    required String reason,
  }) = _MetricsDecodeIssue;
}

abstract final class ResultMetricFields {
  static const harness = 'harness';
  static const model = 'model';
  static const costUsd = 'costUsd';
  static const tokensIn = 'tokensIn';
  static const tokensOut = 'tokensOut';
  static const numTurns = 'numTurns';
  static const harnessDurationMs = 'harnessDurationMs';
  static const cacheReadInputTokens = 'cache_read_input_tokens';
  static const cacheCreationInputTokens = 'cache_creation_input_tokens';
  static const modelLatencyMs = 'model_latency_ms';
  static const transportReliability = 'transport_reliability';
}

@freezed
abstract class LedgerNodeMetrics with _$LedgerNodeMetrics {
  const factory LedgerNodeMetrics({
    required String beadId,
    required String nodePath,
    required String lane,
    LedgerGrade? grade,
    @Default(ResultTransport.absent()) ResultTransport transport,
    String? rationale,
    String? delivery,
    String? harness,
    String? model,
    double? costUsd,
    int? tokensIn,
    int? tokensOut,
    int? numTurns,
    int? harnessDurationMs,
    int? cacheReadInputTokens,
    int? cacheCreationInputTokens,
    int? modelLatencyMs,
    String? transportReliability,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? durationMs,
    @Default(<String, String>{}) Map<String, String> rawFields,
    @Default(<MetricsDecodeIssue>[]) List<MetricsDecodeIssue> issues,
  }) = _LedgerNodeMetrics;
}

@freezed
abstract class LedgerSessionMetrics with _$LedgerSessionMetrics {
  const factory LedgerSessionMetrics({
    required String sessionId,
    required String workBeadId,
    DateTime? startedAt,
    DateTime? closedAt,
    @Default(<LedgerNodeMetrics>[]) List<LedgerNodeMetrics> nodes,
    @Default(<String, List<LedgerNodeMetrics>>{})
    Map<String, List<LedgerNodeMetrics>> nodesByLane,
    @Default(<MetricsDecodeIssue>[]) List<MetricsDecodeIssue> issues,
  }) = _LedgerSessionMetrics;
}

@freezed
abstract class FalseFMetrics with _$FalseFMetrics {
  const factory FalseFMetrics({
    @Default(0) int total,
    @Default(0) int failClosedDefault,
    @Default(0) int realVerdict,
    double? rate,
  }) = _FalseFMetrics;
}

@freezed
abstract class SessionLedgerMetricsProjection
    with _$SessionLedgerMetricsProjection {
  const factory SessionLedgerMetricsProjection({
    @Default(<String, LedgerSessionMetrics>{})
    Map<String, LedgerSessionMetrics> sessionsById,
    @Default(<String, List<LedgerSessionMetrics>>{})
    Map<String, List<LedgerSessionMetrics>> sessionsByLane,
    @Default(FalseFMetrics()) FalseFMetrics falseFs,
    double? cacheHitRatio,
    @Default(<String, int>{}) Map<String, int> reworkRoundsByWorkBead,
    double? costPerLandedDelivery,
    @Default(<String, Map<LedgerGrade, int>>{})
    Map<String, Map<LedgerGrade, int>> gradeDistributionByLane,
    @Default(<MetricsDecodeIssue>[]) List<MetricsDecodeIssue> issues,
  }) = _SessionLedgerMetricsProjection;
}

typedef _ResultRow = ({String nodePath, Map<String, String> fields});

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

List<_ResultRow> _resultRows(
  Bead bead,
  String? sessionId,
  String? expectedPath,
  List<MetricsDecodeIssue> issues,
) {
  final grouped = <String, Map<String, String>>{};
  for (final entry in bead.metadata.entries) {
    if (!entry.key.startsWith(ResultKeys.prefix)) continue;
    final rest = entry.key.substring(ResultKeys.prefix.length);
    final dot = rest.lastIndexOf('.');
    if (dot <= 0 || dot == rest.length - 1) {
      issues.add(
        _issue(
          bead,
          sessionId,
          expectedPath,
          entry.key,
          entry.value.toString(),
          'result key requires node path and field',
        ),
      );
      continue;
    }
    final path = rest.substring(0, dot);
    if (expectedPath != null && path != expectedPath) {
      issues.add(
        _issue(
          bead,
          sessionId,
          path,
          entry.key,
          entry.value.toString(),
          'result node path does not match step path',
        ),
      );
      continue;
    }
    (grouped[path] ??= <String, String>{})[rest.substring(dot + 1)] = entry
        .value
        .toString();
  }
  return [
    for (final entry in grouped.entries)
      (nodePath: entry.key, fields: entry.value),
  ];
}

Map<String, String> _resultFieldsForNode(
  Bead bead,
  String sessionId,
  String nodePath,
  List<MetricsDecodeIssue> issues,
) {
  final rows = _resultRows(bead, sessionId, nodePath, issues);
  return rows.isEmpty ? <String, String>{} : rows.single.fields;
}

MetricsDecodeIssue _issue(
  Bead bead,
  String? sessionId,
  String? nodePath,
  String field,
  String wireValue,
  String reason,
) => MetricsDecodeIssue(
  beadId: bead.id,
  sessionId: sessionId,
  nodePath: nodePath,
  field: field,
  wireValue: wireValue,
  reason: reason,
);

LedgerGrade? _parseGrade(
  Bead bead,
  String sessionId,
  String nodePath,
  String? wire,
  List<MetricsDecodeIssue> issues,
) {
  if (wire == null) return null;
  final value = switch (wire) {
    'A' => LedgerGrade.a,
    'B' => LedgerGrade.b,
    'C' => LedgerGrade.c,
    'D' => LedgerGrade.d,
    'E' => LedgerGrade.e,
    'F' => LedgerGrade.f,
    _ => null,
  };
  if (value == null) {
    issues.add(
      _issue(
        bead,
        sessionId,
        nodePath,
        ResultKeys.grade,
        wire,
        'expected A through F',
      ),
    );
  }
  return value;
}

ResultTransport _parseTransport(String? wire) => switch (wire) {
  null || '' => const ResultTransport.absent(),
  'fail-closed-default' => const ResultTransport.failClosedDefault(),
  kOperatorRulingTransport => const ResultTransport.operatorRuling(),
  final value => ResultTransport.reported(value),
};

int? _parseInt(
  Bead bead,
  String sessionId,
  String nodePath,
  String field,
  String? wire,
  List<MetricsDecodeIssue> issues,
) {
  if (wire == null) return null;
  final value = int.tryParse(wire);
  if (value == null || value < 0) {
    issues.add(
      _issue(
        bead,
        sessionId,
        nodePath,
        field,
        wire,
        value == null ? 'expected integer' : 'must be non-negative integer',
      ),
    );
    return null;
  }
  return value;
}

double? _parseDouble(
  Bead bead,
  String sessionId,
  String nodePath,
  String field,
  String? wire,
  List<MetricsDecodeIssue> issues,
) {
  if (wire == null) return null;
  final value = double.tryParse(wire);
  if (value == null || !value.isFinite || value < 0) {
    issues.add(
      _issue(
        bead,
        sessionId,
        nodePath,
        field,
        wire,
        value == null || !value.isFinite
            ? 'expected finite number'
            : 'must be non-negative number',
      ),
    );
    return null;
  }
  return value;
}

DateTime? _parseDate(
  Bead bead,
  String? sessionId,
  String? nodePath,
  String field,
  Object? wire,
  List<MetricsDecodeIssue> issues,
) {
  if (wire == null) return null;
  final value = DateTime.tryParse(wire.toString());
  if (value == null) {
    issues.add(
      _issue(
        bead,
        sessionId,
        nodePath,
        field,
        wire.toString(),
        'expected ISO-8601 timestamp',
      ),
    );
    return null;
  }
  return value.toUtc();
}

LedgerNodeMetrics _decodeNode({
  required Bead bead,
  required String sessionId,
  required String nodePath,
  required Map<String, String> fields,
}) {
  final issues = <MetricsDecodeIssue>[];
  String? field(String key) => fields[key];
  int? integer(String key) =>
      _parseInt(bead, sessionId, nodePath, key, field(key), issues);
  return LedgerNodeMetrics(
    beadId: bead.id,
    nodePath: nodePath,
    lane: nodePath.split('/').where((part) => part.isNotEmpty).last,
    grade: _parseGrade(
      bead,
      sessionId,
      nodePath,
      field(ResultKeys.grade),
      issues,
    ),
    transport: _parseTransport(field(ResultKeys.transport)),
    rationale: field(ResultKeys.rationale),
    delivery: field(ResultKeys.delivery),
    harness: field(ResultMetricFields.harness),
    model: field(ResultMetricFields.model),
    costUsd: _parseDouble(
      bead,
      sessionId,
      nodePath,
      ResultMetricFields.costUsd,
      field(ResultMetricFields.costUsd),
      issues,
    ),
    tokensIn: integer(ResultMetricFields.tokensIn),
    tokensOut: integer(ResultMetricFields.tokensOut),
    numTurns: integer(ResultMetricFields.numTurns),
    harnessDurationMs: integer(ResultMetricFields.harnessDurationMs),
    cacheReadInputTokens: integer(ResultMetricFields.cacheReadInputTokens),
    cacheCreationInputTokens: integer(
      ResultMetricFields.cacheCreationInputTokens,
    ),
    modelLatencyMs: integer(ResultMetricFields.modelLatencyMs),
    transportReliability: field(ResultMetricFields.transportReliability),
    startedAt: bead.issueType == IssueType.step
        ? _parseDate(
            bead,
            sessionId,
            nodePath,
            MoleculeStepKeys.startedAt,
            bead.metadata[MoleculeStepKeys.startedAt],
            issues,
          )
        : null,
    finishedAt: bead.issueType == IssueType.step
        ? _parseDate(
            bead,
            sessionId,
            nodePath,
            MoleculeStepKeys.finishedAt,
            bead.metadata[MoleculeStepKeys.finishedAt],
            issues,
          )
        : null,
    durationMs: bead.issueType == IssueType.step
        ? _parseInt(
            bead,
            sessionId,
            nodePath,
            MoleculeStepKeys.durationMs,
            bead.metadata[MoleculeStepKeys.durationMs]?.toString(),
            issues,
          )
        : null,
    rawFields: Map<String, String>.of(fields),
    issues: issues,
  );
}

List<LedgerSessionMetrics> _buildSortedSessions(
  Map<String, Bead> owners,
  Map<String, List<LedgerNodeMetrics>> bySession,
) {
  final result = <LedgerSessionMetrics>[];
  for (final owner in owners.values) {
    final issues = <MetricsDecodeIssue>[];
    final nodes = [...bySession[owner.id] ?? const <LedgerNodeMetrics>[]]
      ..sort((a, b) {
        final byTime = (a.startedAt ?? _epoch).compareTo(b.startedAt ?? _epoch);
        if (byTime != 0) return byTime;
        final byPath = a.nodePath.compareTo(b.nodePath);
        return byPath != 0 ? byPath : a.beadId.compareTo(b.beadId);
      });
    final lanes = <String, List<LedgerNodeMetrics>>{};
    for (final node in nodes) {
      (lanes[node.lane] ??= <LedgerNodeMetrics>[]).add(node);
    }
    final immutableLanes = <String, List<LedgerNodeMetrics>>{
      for (final entry in lanes.entries)
        entry.key: List<LedgerNodeMetrics>.unmodifiable(entry.value),
    };
    final started = _parseDate(
      owner,
      owner.id,
      null,
      SessionBeadKeys.startedAt,
      owner.metadata[SessionBeadKeys.startedAt],
      issues,
    );
    result.add(
      LedgerSessionMetrics(
        sessionId: owner.id,
        workBeadId: owner.metadata[SessionBeadKeys.workBead]?.toString() ?? '',
        startedAt: started,
        closedAt: _parseDate(
          owner,
          owner.id,
          null,
          SessionBeadKeys.closedAt,
          owner.metadata[SessionBeadKeys.closedAt],
          issues,
        ),
        nodes: nodes,
        nodesByLane: immutableLanes,
        issues: [...issues, ...nodes.expand((node) => node.issues)],
      ),
    );
  }
  result.sort((a, b) {
    final byTime = (a.startedAt ?? _epoch).compareTo(b.startedAt ?? _epoch);
    return byTime != 0 ? byTime : a.sessionId.compareTo(b.sessionId);
  });
  return result;
}

int _sumInts(
  Iterable<LedgerNodeMetrics> nodes,
  int? Function(LedgerNodeMetrics) pick,
) => nodes.fold(0, (sum, node) => sum + (pick(node) ?? 0));

Map<String, List<LedgerSessionMetrics>> _sessionsByLane(
  List<LedgerSessionMetrics> sessions,
) {
  final result = <String, List<LedgerSessionMetrics>>{};
  for (final session in sessions) {
    for (final lane in session.nodesByLane.keys) {
      (result[lane] ??= <LedgerSessionMetrics>[]).add(session);
    }
  }
  return {
    for (final entry in result.entries)
      entry.key: List<LedgerSessionMetrics>.unmodifiable(entry.value),
  };
}

Map<String, Map<LedgerGrade, int>> _gradeDistribution(
  Iterable<LedgerNodeMetrics> nodes,
) {
  final result = <String, Map<LedgerGrade, int>>{};
  for (final node in nodes) {
    if (node.grade case final grade?) {
      final lane = result[node.lane] ??= <LedgerGrade, int>{};
      lane[grade] = (lane[grade] ?? 0) + 1;
    }
  }
  return {
    for (final entry in result.entries)
      entry.key: Map<LedgerGrade, int>.unmodifiable(entry.value),
  };
}

Map<String, int> _reworkRounds(
  List<LedgerSessionMetrics> sessions,
  Iterable<Bead> beads,
  Iterable<BeadDependency> dependencies,
) {
  final steps = <String, List<Bead>>{};
  for (final bead in beads.where((bead) => bead.issueType == IssueType.step)) {
    final owner = bead.metadata[MoleculeStepKeys.session]?.toString();
    if (owner != null) (steps[owner] ??= <Bead>[]).add(bead);
  }
  final result = <String, int>{};
  for (final session in sessions) {
    final depths = supersedesDepthByStepId(
      steps[session.sessionId] ?? const <Bead>[],
      dependencies,
    );
    final maximum = depths.values.fold(
      0,
      (current, depth) => depth > current ? depth : current,
    );
    final prior = result[session.workBeadId] ?? 0;
    result[session.workBeadId] = maximum > prior ? maximum : prior;
  }
  return result;
}

List<MetricsDecodeIssue> _sortedIssues(Iterable<MetricsDecodeIssue> issues) =>
    [...issues]..sort((a, b) {
      final byBead = a.beadId.compareTo(b.beadId);
      if (byBead != 0) return byBead;
      final bySession = (a.sessionId ?? '').compareTo(b.sessionId ?? '');
      if (bySession != 0) return bySession;
      final byPath = (a.nodePath ?? '').compareTo(b.nodePath ?? '');
      if (byPath != 0) return byPath;
      final byField = a.field.compareTo(b.field);
      if (byField != 0) return byField;
      final byWire = a.wireValue.compareTo(b.wireValue);
      return byWire != 0 ? byWire : a.reason.compareTo(b.reason);
    });

SessionLedgerMetricsProjection projectSessionLedgerMetrics(
  GraphSnapshot snapshot,
) {
  final sessionBeads = <String, Bead>{
    for (final bead in snapshot.beads)
      if (bead.issueType == IssueType.session) bead.id: bead,
  };
  final nodesBySession = <String, List<LedgerNodeMetrics>>{};
  final issues = <MetricsDecodeIssue>[];

  for (final session in sessionBeads.values) {
    for (final entry in _resultRows(session, session.id, null, issues)) {
      (nodesBySession[session.id] ??= []).add(
        _decodeNode(
          bead: session,
          sessionId: session.id,
          nodePath: entry.nodePath,
          fields: entry.fields,
        ),
      );
    }
  }
  for (final step in snapshot.beads.where(
    (bead) => bead.issueType == IssueType.step,
  )) {
    final sessionId = step.metadata[MoleculeStepKeys.session]?.toString();
    final nodePath = step.metadata[MoleculeStepKeys.path]?.toString();
    if (sessionId == null || !sessionBeads.containsKey(sessionId)) {
      issues.add(
        _issue(
          step,
          sessionId,
          nodePath,
          MoleculeStepKeys.session,
          sessionId ?? '',
          'orphan step result',
        ),
      );
      continue;
    }
    if (nodePath == null || nodePath.isEmpty) {
      issues.add(
        _issue(
          step,
          sessionId,
          nodePath,
          MoleculeStepKeys.path,
          nodePath ?? '',
          'missing node path',
        ),
      );
      continue;
    }
    (nodesBySession[sessionId] ??= []).add(
      _decodeNode(
        bead: step,
        sessionId: sessionId,
        nodePath: nodePath,
        fields: _resultFieldsForNode(step, sessionId, nodePath, issues),
      ),
    );
  }

  final sessions = _buildSortedSessions(sessionBeads, nodesBySession);
  final allNodes = sessions.expand((session) => session.nodes).toList();
  final fNodes = allNodes.where((node) => node.grade == LedgerGrade.f).toList();
  final falseFCount = fNodes
      .where(
        (node) => switch (node.transport) {
          ResultTransportFailClosedDefault() => true,
          ResultTransportAbsent() ||
          ResultTransportOperatorRuling() ||
          ResultTransportReported() => false,
        },
      )
      .length;
  final cacheRead = _sumInts(allNodes, (node) => node.cacheReadInputTokens);
  final cacheCreate = _sumInts(
    allNodes,
    (node) => node.cacheCreationInputTokens,
  );
  final uncachedInput = _sumInts(allNodes, (node) => node.tokensIn);
  final cacheDenominator = cacheRead + cacheCreate + uncachedInput;
  final landed = sessions
      .where(
        (session) => session.nodes.any(
          (node) => node.delivery != null && node.delivery!.isNotEmpty,
        ),
      )
      .toList();
  final landedCost = landed
      .expand((session) => session.nodes)
      .fold<double>(0, (sum, node) => sum + (node.costUsd ?? 0));

  return SessionLedgerMetricsProjection(
    sessionsById: {for (final session in sessions) session.sessionId: session},
    sessionsByLane: _sessionsByLane(sessions),
    falseFs: FalseFMetrics(
      total: fNodes.length,
      failClosedDefault: falseFCount,
      realVerdict: fNodes.length - falseFCount,
      rate: fNodes.isEmpty ? null : falseFCount / fNodes.length,
    ),
    cacheHitRatio: cacheDenominator == 0 ? null : cacheRead / cacheDenominator,
    reworkRoundsByWorkBead: _reworkRounds(
      sessions,
      snapshot.beads,
      snapshot.dependencies,
    ),
    costPerLandedDelivery: landed.isEmpty ? null : landedCost / landed.length,
    gradeDistributionByLane: _gradeDistribution(allNodes),
    issues: _sortedIssues([
      ...issues,
      ...sessions.expand((session) => session.issues),
    ]),
  );
}
