// The resident's unwind closes every store connection the live delegate
// opened, state store first, before the lock release. An established
// `bd db-proxy-child` socket with a pending read keeps the isolate alive, so a
// resident that skips this step never exits after `down`.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show GridIssueTypes, PrimaryCheckoutFreshness, PrimaryCheckoutState;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/recording_stdout.dart';

/// A fake store connection: records both the attempt and the completion, and
/// can refuse ([refuses]) or hang forever ([hangs]) the way a half-open proxy
/// socket does.
final class _Store implements StoreConnection {
  _Store(this.name, this.events, {this.refuses = false, this.hangs = false});

  @override
  final String name;
  final List<String> events;
  final bool refuses;
  final bool hangs;

  @override
  Future<void> close() async {
    events.add('store.close:$name');
    if (refuses) throw StateError('close refused: $name');
    if (hangs) await Completer<void>().future;
    events.add('store.closed:$name');
  }
}

/// Vends [stores] and trips when its handles are read after dispose — the
/// shell must capture them while the delegate is still live.
final class _Delegate extends GridDelegate {
  _Delegate(this.events, this.stores);

  final List<String> events;
  final List<StoreConnection> stores;
  var _disposed = false;

  @override
  List<StoreConnection> get openStores {
    if (_disposed) {
      throw StateError('openStores read on a disposed delegate');
    }
    return stores;
  }

  @override
  void dispose() {
    _disposed = true;
    events.add('delegate.dispose');
    super.dispose();
  }
}

final class _Lock implements LockResource {
  _Lock(this.events);

  final List<String> events;

  @override
  String get path => '/fake/station.lock';

  @override
  Future<void> updateControl({
    required String controlUrl,
    required String token,
  }) async {}

  @override
  Future<void> updateVmService(String vmServiceUri) async {}

  @override
  Future<void> release() async => events.add('lock.release');
}

final class _Grid implements GridResource {
  _Grid(this.events, this.delegate, {required this.orphanSweep});

  final List<String> events;
  final GridDelegate delegate;
  final Future<void> Function() orphanSweep;

  @override
  Future<ReassembleReport> hotReload() => throw UnimplementedError();

  @override
  Future<ReassembleReport> hotRestart() => throw UnimplementedError();

  @override
  Future<void> teardown() async {
    events.add('grid.teardown');
    await orphanSweep();
    delegate.dispose();
  }
}

final class _Control implements ControlResource {
  _Control(this.events);

  final List<String> events;

  @override
  String get url => 'http://127.0.0.1:9999';

  @override
  Future<void> dispose() async => events.add('control.dispose');
}

typedef _Outcome = ({int? code, List<String> events, String out, String err});

Future<_Outcome> _runUp(
  List<StoreConnection> Function(List<String> events) storesFor,
) async {
  final temp = Directory.systemTemp.createTempSync('unwind-stores-');
  addTearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });
  final home = p.join(temp.path, 'home');
  final workRoot = p.join(temp.path, 'work');
  seedStore(p.join(home, '.grid'));
  seedStore(workRoot);

  final events = <String>[];
  final stores = storesFor(events);
  final outConsumer = ByteConsumer();
  final errConsumer = ByteConsumer();
  final outSink = RecordingStdout(outConsumer);
  final errSink = RecordingStdout(errConsumer);

  final command = UpCommand(
    stationName: 'lunar',
    delegateFactory: ({required config}) => _Delegate(events, stores),
    codedRoster: ({required gridHome}) => [
      SubstationWorkSpec(name: 'earth', root: workRoot, prefix: 'earth'),
    ],
    harnessAllowList: const {'safe'},
    validateHarness: (_) => null,
    acquireLock:
        ({required stateWorkspaceDir, required pid, required now}) async =>
            _Lock(events),
    runMountedGrid:
        (
          delegate, {
          required onFlushed,
          required orphanSweep,
          required onDelegateSwapped,
          required treeProjector,
          delegateFactory,
        }) async {
          await delegate.boot(const GridConfiguration());
          return _Grid(events, delegate, orphanSweep: orphanSweep);
        },
    startControl:
        ({
          required port,
          required token,
          required view,
          required commandHandler,
          required treeProjector,
        }) async => _Control(events),
    armDevelopmentMode:
        ({
          required vmServiceUri,
          required hotReload,
          required hotRestart,
          required latest,
          required readPath,
        }) async => null,
    readVmServiceUri: () async => null,
    inspectPrimaryCheckout: (substation) async =>
        const PrimaryCheckoutFreshness(state: PrimaryCheckoutState.fresh),
    maintainStateStore: ({required gridHome}) async {},
    readStateStoreTypes: ({required gridHome}) async => <String, dynamic>{
      'custom_types': [
        for (final type in GridIssueTypes.customTypes) type.wire,
      ],
    },
    waitForShutdown: () async {},
  );
  final runner = CommandRunner<int>('lunar', 'test')..addCommand(command);
  final code = await IOOverrides.runZoned(
    () => runner.run(['up', '--grid-home', home]),
    stdout: () => outSink,
    stderr: () => errSink,
  );
  await outSink.flush();
  await errSink.flush();
  return (
    code: code,
    events: events,
    out: outConsumer.text,
    err: errConsumer.text,
  );
}

void main() {
  test('every store closes — state first — before the lock releases', () async {
    final outcome = await _runUp(
      (events) => [_Store('state', events), _Store('earth', events)],
    );

    expect(outcome.code, 0);
    expect(
      outcome.events,
      containsAllInOrder([
        'grid.teardown',
        'delegate.dispose',
        'store.close:state',
        'store.closed:state',
        'store.close:earth',
        'store.closed:earth',
        'lock.release',
      ]),
    );
    expect(outcome.events.last, 'lock.release');
    expect(outcome.out, contains('store connections closed: 2/2'));
  });

  test(
    'a refusing and a hanging close strand neither the rest nor the lock',
    () async {
      final outcome = await _runUp(
        (events) => [
          _Store('state', events, refuses: true),
          _Store('slow', events, hangs: true),
          _Store('earth', events),
        ],
      );

      expect(outcome.code, 0);
      expect(outcome.events, isNot(contains('store.closed:state')));
      expect(outcome.events, isNot(contains('store.closed:slow')));
      expect(outcome.events, contains('store.closed:earth'));
      expect(outcome.events.last, 'lock.release');
      expect(outcome.err, contains('unwind step "store close (state)" failed'));
      expect(outcome.err, contains('unwind step "store close (slow)" failed'));
      expect(outcome.out, contains('store connections closed: 1/3'));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a station vending no stores prints no store line', () async {
    final outcome = await _runUp((_) => const <StoreConnection>[]);

    expect(outcome.code, 0);
    expect(outcome.out, isNot(contains('store connections closed')));
    expect(outcome.events.last, 'lock.release');
  });
}
