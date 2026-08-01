import 'package:genesis_foundation/genesis_foundation.dart';

TreeSnapshot snapshot({
  required int version,
  List<TreeNode> children = const [],
  List<DiagnosticsProperty> properties = const [],
}) => TreeSnapshot(
  contractVersion: 1,
  projectedAt: DateTime.utc(2026, 1, version),
  root: TreeNode(
    seedType: 'Grid',
    id: 'root',
    properties: properties,
    children: children,
  ),
);

TreeNode node({
  required String id,
  required String seedType,
  String? key,
  List<DiagnosticsProperty> properties = const [],
  List<TreeNode> children = const [],
}) => TreeNode(
  seedType: seedType,
  id: id,
  key: key,
  properties: properties,
  children: children,
);

DiagnosticsProperty stringProperty(
  String name,
  String value, {
  DiagnosticsLevel level = DiagnosticsLevel.info,
}) => DiagnosticsProperty.string(name: name, level: level, value: value);

DiagnosticsProperty intProperty(
  String name,
  int value, {
  DiagnosticsLevel level = DiagnosticsLevel.info,
}) => DiagnosticsProperty.int(name: name, level: level, value: value);
