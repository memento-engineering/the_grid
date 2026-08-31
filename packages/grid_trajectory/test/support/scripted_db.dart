/// A scripted [TrajectoryDb]: records every statement, answers from
/// first-match rules — so every §5 contract branch (0-row CAS, 1213 at
/// COMMIT, both 1105 shapes, the belt) is drivable without a socket.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';

class ExecutedSql {
  ExecutedSql(this.sql, this.params);

  final String sql;
  final Map<String, dynamic>? params;

  @override
  String toString() => '$sql  <-  $params';
}

class _Rule {
  _Rule(this.pattern, this.respond, {this.once = false});

  final Pattern pattern;
  final SqlResult Function(ExecutedSql call) respond;
  final bool once;
  bool spent = false;
}

class ScriptedDb implements TrajectoryDb {
  final List<ExecutedSql> log = [];
  final List<_Rule> _rules = [];
  bool closed = false;

  /// Registers a rule; earlier registrations win, `once` rules retire after
  /// one match (letting a retry see the next rule for the same pattern).
  void on(
    Pattern pattern, {
    SqlResult result = const SqlResult(),
    Object? throwing,
    SqlResult Function(ExecutedSql call)? respond,
    bool once = false,
  }) {
    _rules.add(
      _Rule(
        pattern,
        respond ??
            (throwing != null
                ? (_) =>
                      throw throwing // ignore: only_throw_errors
                : (_) => result),
        once: once,
      ),
    );
  }

  /// A 1105 whose message names [constraint], matching dolt's commit-time
  /// unique-violation surface.
  void onUniqueViolation(
    Pattern pattern,
    String constraint, {
    bool once = false,
  }) => on(
    pattern,
    throwing: MySQLServerException(
      'unique key violation on $constraint: to commit transaction '
      'anyway set @@dolt_force_transaction_commit = 1',
      1105,
    ),
    once: once,
  );

  List<ExecutedSql> matching(Pattern pattern) =>
      log.where((call) => call.sql.contains(pattern)).toList();

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async {
    final call = ExecutedSql(sql, params);
    log.add(call);
    for (final rule in _rules) {
      if (rule.spent || !sql.contains(rule.pattern)) continue;
      if (rule.once) rule.spent = true;
      return rule.respond(call);
    }
    return const SqlResult();
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
