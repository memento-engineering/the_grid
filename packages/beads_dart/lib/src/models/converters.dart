import 'package:json_annotation/json_annotation.dart';

import 'bead_status.dart';
import 'dependency_type.dart';
import 'issue_type.dart';

/// json_serializable bridges for the extension-type wrappers. Each is a
/// zero-cost `String <-> wrapper` mapping; declared `const` so they can be
/// used as field annotations on freezed factories.
class BeadStatusConverter implements JsonConverter<BeadStatus, String> {
  const BeadStatusConverter();
  @override
  BeadStatus fromJson(String json) => BeadStatus(json);
  @override
  String toJson(BeadStatus object) => object.wire;
}

class IssueTypeConverter implements JsonConverter<IssueType, String> {
  const IssueTypeConverter();
  @override
  IssueType fromJson(String json) => IssueType(json);
  @override
  String toJson(IssueType object) => object.wire;
}

class DependencyTypeConverter implements JsonConverter<DependencyType, String> {
  const DependencyTypeConverter();
  @override
  DependencyType fromJson(String json) => DependencyType(json);
  @override
  String toJson(DependencyType object) => object.wire;
}

/// Canonicalizes a bead's labels to sorted order on decode.
///
/// Labels are a **set** upstream (the `labels` table PK is
/// `(issue_id, label)`), so order carries no meaning. Both read paths must
/// agree byte-for-byte for the SQL-vs-CLI equivalence canary (ADR-0001
/// Decision 7) and for `Bead ==` to be reliable, so the CLI decoder sorts here
/// and the SQL `beadFromRow` mapper sorts identically. (ADR-0000 amendment
/// A11.)
class SortedLabelsConverter
    implements JsonConverter<List<String>, List<dynamic>> {
  const SortedLabelsConverter();
  @override
  List<String> fromJson(List<dynamic> json) =>
      <String>[for (final entry in json) entry as String]..sort();
  @override
  List<dynamic> toJson(List<String> object) => object;
}
