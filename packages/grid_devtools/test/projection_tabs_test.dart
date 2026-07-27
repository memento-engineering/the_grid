import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_devtools/grid_devtools.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

import 'fake_grid_exploration_client.dart';

const _info = DiagnosticsLevel.info;

TreeSnapshot _snapshot({
  String rootId = 'root',
  String stationId = 'station',
  String stationName = 'alpha',
  String workId = 'work',
  String beadId = 'bead-1',
}) => TreeSnapshot(
  contractVersion: 1,
  projectedAt: DateTime.utc(2026, 7, 25),
  root: TreeNode(
    seedType: 'Grid',
    id: rootId,
    properties: const [],
    children: [
      TreeNode(
        seedType: 'Substation',
        id: stationId,
        properties: [
          DiagnosticsProperty.string(
            name: 'substationId',
            level: _info,
            value: stationName,
          ),
        ],
        children: [
          TreeNode(
            seedType: 'WorkBead',
            id: workId,
            properties: [
              DiagnosticsProperty.string(
                name: 'beadId',
                level: _info,
                value: beadId,
              ),
              const DiagnosticsProperty.string(
                name: 'sessionId',
                level: _info,
                value: 'session-1',
              ),
              const DiagnosticsProperty.string(
                name: 'stepState',
                level: _info,
                value: 'running',
              ),
            ],
            children: const [
              TreeNode(
                seedType: 'CircuitStep',
                id: 'build',
                properties: [
                  DiagnosticsProperty.string(
                    name: 'nodePath',
                    level: _info,
                    value: 'build',
                  ),
                  DiagnosticsProperty.string(
                    name: 'stepState',
                    level: _info,
                    value: 'running',
                  ),
                  DiagnosticsProperty.int(
                    name: 'inputTokens',
                    level: _info,
                    value: 10,
                  ),
                  DiagnosticsProperty.double(
                    name: 'costUsd',
                    level: _info,
                    value: 0.25,
                  ),
                  DiagnosticsProperty.string(
                    name: 'grade',
                    level: _info,
                    value: 'A',
                  ),
                ],
                children: [],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
);

Widget _host({
  required ReplayTreeSource source,
  required FakeGridExplorationClient client,
  SnapshotJsonPicker? picker,
  bool ambientStartAlignment = false,
}) {
  final child = Scaffold(
    body: ProjectionTabs(
      source: source,
      client: client,
      snapshotJsonPicker: picker ?? () async => null,
    ),
  );
  return MaterialApp(
    home: ambientStartAlignment
        ? Theme(
            data: ThemeData(
              tabBarTheme: const TabBarThemeData(
                tabAlignment: TabAlignment.start,
              ),
            ),
            child: child,
          )
        : child,
  );
}

void main() {
  late ReplayTreeSource source;
  late FakeGridExplorationClient client;

  setUp(() {
    source = ReplayTreeSource([_snapshot()]);
    client = FakeGridExplorationClient(
      seedEvents: const [GridEventRecord(type: 'beadCreated', id: 'grid-1')],
    );
  });

  tearDown(() async {
    await source.dispose();
    await client.dispose();
  });

  testWidgets('builds with ambient start tab alignment', (tester) async {
    await tester.pumpWidget(
      _host(
        source: source,
        client: client,
        ambientStartAlignment: true,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
  });

  testWidgets('renders Station Inspector and Events with independent events', (
    tester,
  ) async {
    await tester.pumpWidget(_host(source: source, client: client));
    await tester.pumpAndSettle();
    expect(find.text('Station'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    expect(find.text('beadCreated'), findsOneWidget);
    expect(find.text('grid-1'), findsOneWidget);
  });

  testWidgets('navigates the Station operator flow in both directions', (
    tester,
  ) async {
    await tester.pumpWidget(_host(source: source, client: client));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('station')));
    await tester.pump();
    expect(find.text('bead-1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('work')));
    await tester.pump();
    expect(find.text('build'), findsOneWidget);
    expect(find.text('Input tokens: 10'), findsOneWidget);
    expect(find.text('USD: 0.2500'), findsOneWidget);
    expect(find.text('Grade A'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.text('bead-1'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.text('alpha'), findsOneWidget);
  });

  testWidgets('selects projected tree nodes into inspector detail', (
    tester,
  ) async {
    await source.dispose();
    source = ReplayTreeSource([
      _snapshot(),
      _snapshot(
        rootId: 'next-root',
        stationId: 'next-station',
        workId: 'next-work',
      ),
    ]);
    await tester.pumpWidget(_host(source: source, client: client));
    await tester.tap(find.text('Inspector'));
    await tester.pumpAndSettle();
    expect(find.text('Grid'), findsWidgets);

    await tester.tap(find.byKey(const Key('inspector.node.station')));
    await tester.pump();
    expect(find.text('Substation'), findsWidgets);
    expect(find.text('substationId'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);

    source.advance();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('inspector.node.next-root')), findsOneWidget);
  });

  testWidgets('loads valid snapshot JSON into both projection tabs', (
    tester,
  ) async {
    final replacement = _snapshot(
      rootId: 'replacement-root',
      stationId: 'replacement-station',
      stationName: 'beta',
      workId: 'replacement-work',
      beadId: 'bead-2',
    );
    await tester.pumpWidget(
      _host(
        source: source,
        client: client,
        picker: () async => jsonEncode(replacement),
      ),
    );
    await tester.tap(find.byKey(const Key('projection.loadSnapshot')));
    await tester.pumpAndSettle();
    expect(find.text('beta'), findsOneWidget);

    await tester.tap(find.text('Inspector'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('inspector.node.replacement-root')),
      findsOneWidget,
    );

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    expect(find.text('beadCreated'), findsOneWidget);
    expect(find.text('grid-1'), findsOneWidget);
  });

  testWidgets('cancels or rejects loading without losing replay state', (
    tester,
  ) async {
    var contents = '{';
    await tester.pumpWidget(
      _host(
        source: source,
        client: client,
        picker: () async => contents.isEmpty ? null : contents,
      ),
    );
    await tester.tap(find.byKey(const Key('projection.loadSnapshot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projection.loadError')), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);

    contents = '{"contractVersion":1}';
    await tester.tap(find.byKey(const Key('projection.loadSnapshot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projection.loadError')), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);

    contents = '';
    await tester.tap(find.byKey(const Key('projection.loadSnapshot')));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
  });

  testWidgets('unmounts safely while file selection is pending', (
    tester,
  ) async {
    final picker = Completer<String?>();
    await tester.pumpWidget(
      _host(source: source, client: client, picker: () => picker.future),
    );
    await tester.tap(find.byKey(const Key('projection.loadSnapshot')));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    picker.complete(jsonEncode(_snapshot(rootId: 'late')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
