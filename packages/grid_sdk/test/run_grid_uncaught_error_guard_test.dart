import 'dart:async';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

Future<void> pump([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const <Seed>[]);
}

final class _DetachedFailure {
  _DetachedFailure(this.label, {this.nodePath, this.stepId});

  final String label;
  final String? nodePath;
  final String? stepId;
  final gate = Completer<void>();
  late final StateError error = StateError(label);

  Future<void> start() async {
    await gate.future;
    if (nodePath == null && stepId == null) {
      unawaited(_throwDetached());
      return;
    }
    runWithGridErrorAttribution(
      nodePath: nodePath,
      stepId: stepId,
      body: () => unawaited(_throwDetached()),
    );
  }

  Future<void> _throwDetached() async {
    await Future<void>.delayed(Duration.zero);
    throw error;
  }
}

final class _MountedProbe extends StatefulSeed {
  const _MountedProbe({required this.failures, required this.onState});

  final List<_DetachedFailure> failures;
  final void Function(_MountedProbeState state) onState;

  @override
  State<_MountedProbe> createState() => _MountedProbeState();
}

final class _MountedProbeState extends State<_MountedProbe> {
  var builds = 0;
  var disposed = false;

  @override
  void initState() {
    super.initState();
    for (final failure in seed.failures) {
      unawaited(failure.start());
    }
  }

  @override
  void didChangeDependencies() => seed.onState(this);

  @override
  Seed build(TreeContext context) {
    builds++;
    return const _Leaf();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

final class _GuardDelegate extends GridDelegate {
  _GuardDelegate({required this.failures, required this.onState});

  final List<_DetachedFailure> failures;
  final void Function(_MountedProbeState state) onState;
  var buildCount = 0;

  void emit(int value) =>
      state = GridConfiguration(settings: <String, Object?>{'value': value});

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    buildCount++;
    return _MountedProbe(failures: failures, onState: onState);
  }
}

final class _FatalRailDelegate extends GridDelegate {
  _FatalRailDelegate({this.didLaunchError, this.bootError});

  final Object? didLaunchError;
  final Object? bootError;
  var buildCount = 0;

  @override
  void didLaunch() {
    if (didLaunchError case final error?) throw error;
  }

  @override
  Future<void> boot(GridConfiguration configuration) async {
    if (bootError case final error?) throw error;
  }

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    buildCount++;
    return const _Leaf();
  }
}

void main() {
  test(
    'an attributed detached error is station.uncaughtError and the live grid '
    'flushes again',
    () async {
      final failure = _DetachedFailure(
        'detached boom',
        nodePath: 'tg-a/review',
        stepId: 'grade',
      );
      final errors = <GridHookError>[];
      final flushes = <String>[];
      late _MountedProbeState mounted;
      final delegate = _GuardDelegate(
        failures: <_DetachedFailure>[failure],
        onState: (state) => mounted = state,
      );
      final handle = await runGrid(
        delegate,
        onError: errors.add,
        onFlushed: () => flushes.add('flush'),
      );
      addTearDown(handle.teardown);

      failure.gate.complete();
      await pump();

      expect(errors, hasLength(1));
      final error = errors.single;
      expect(error.hook, 'uncaughtError');
      expect(error.name, 'station.uncaughtError');
      expect(error.cause, same(failure.error));
      expect(error.causeStackTrace.toString(), isNotEmpty);
      expect(error.nodePath, 'tg-a/review');
      expect(error.stepId, 'grade');
      expect(error.data, containsPair('attribution', 'nodePath+stepId'));
      expect(error.data, containsPair('error', '${failure.error}'));
      expect(error.data['stackTrace'], isNotEmpty);
      expect(handle.isTornDown, isFalse);
      expect(mounted.disposed, isFalse);

      final beforeFlushes = flushes.length;
      final beforeBuilds = delegate.buildCount;
      delegate.emit(1);
      await pump();

      expect(flushes.length, greaterThan(beforeFlushes));
      expect(delegate.buildCount, greaterThan(beforeBuilds));
      expect(mounted.disposed, isFalse);
      expect(handle.isTornDown, isFalse);
    },
  );

  test('didLaunch and boot remain fatal before mount', () async {
    final didLaunch = _FatalRailDelegate(
      didLaunchError: StateError('launch failed'),
    );
    await expectLater(
      runGrid(didLaunch),
      throwsA(
        isA<GridHookError>()
            .having((error) => error.hook, 'hook', 'didLaunch')
            .having((error) => error.cause, 'cause', isA<StateError>()),
      ),
    );
    expect(didLaunch.buildCount, 0);

    final boot = _FatalRailDelegate(bootError: StateError('boot failed'));
    await expectLater(
      runGrid(boot),
      throwsA(
        isA<GridHookError>()
            .having((error) => error.hook, 'hook', 'boot')
            .having((error) => error.cause, 'cause', isA<StateError>()),
      ),
    );
    expect(boot.buildCount, 0);
  });

  test(
    'uncaught records distinguish attributed and unavailable context',
    () async {
      final failures = <_DetachedFailure>[
        _DetachedFailure('both', nodePath: 'tg-a/build', stepId: 'compile'),
        _DetachedFailure('node', nodePath: 'tg-b/review'),
        _DetachedFailure('step', stepId: 'verify'),
        _DetachedFailure('neither'),
      ];
      final errors = <GridHookError>[];
      final handle = await runGrid(
        _GuardDelegate(failures: failures, onState: (_) {}),
        onError: errors.add,
      );
      addTearDown(handle.teardown);

      for (final failure in failures) {
        failure.gate.complete();
      }
      await pump();

      expect(errors, hasLength(4));
      final byCause = <String, GridHookError>{
        for (final error in errors) '${error.cause}': error,
      };
      expect(byCause['Bad state: both']!.data, <String, String>{
        'hook': 'uncaughtError',
        'delegateType': '_GuardDelegate',
        'error': 'Bad state: both',
        'stackTrace': byCause['Bad state: both']!.data['stackTrace']!,
        'attribution': 'nodePath+stepId',
        'nodePath': 'tg-a/build',
        'stepId': 'compile',
      });
      expect(
        byCause['Bad state: node']!.data,
        allOf(
          containsPair('attribution', 'nodePath'),
          containsPair('nodePath', 'tg-b/review'),
        ),
      );
      expect(byCause['Bad state: node']!.data, isNot(contains('stepId')));
      expect(
        byCause['Bad state: step']!.data,
        allOf(
          containsPair('attribution', 'stepId'),
          containsPair('stepId', 'verify'),
        ),
      );
      expect(byCause['Bad state: step']!.data, isNot(contains('nodePath')));
      expect(
        byCause['Bad state: neither']!.data,
        containsPair('attribution', 'unavailable'),
      );
      expect(
        byCause['Bad state: neither']!.data,
        isNot(anyOf(contains('nodePath'), contains('stepId'))),
      );
      expect(handle.isTornDown, isFalse);
    },
  );

  test('the default sink is loud and non-fatal', () async {
    final failure = _DetachedFailure('default sink boom');
    final lines = <String>[];
    final outerErrors = <Object>[];
    final flushes = <String>[];
    late GridHandle handle;
    late _GuardDelegate delegate;

    await runZonedGuarded(
      () async {
        delegate = _GuardDelegate(
          failures: <_DetachedFailure>[failure],
          onState: (_) {},
        );
        handle = await runGrid(delegate, onFlushed: () => flushes.add('flush'));
        failure.gate.complete();
        await pump();
      },
      (error, stackTrace) => outerErrors.add(error),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );
    addTearDown(handle.teardown);

    expect(outerErrors, isEmpty);
    expect(lines, hasLength(1));
    expect(lines.single, contains('station.uncaughtError'));
    expect(lines.single, contains('default sink boom'));
    expect(lines.single, contains('stackTrace:'));
    expect(handle.isTornDown, isFalse);

    final before = flushes.length;
    delegate.emit(1);
    await pump();
    expect(flushes.length, greaterThan(before));
  });

  test('error attribution requires a non-empty identity', () {
    expect(
      () => runWithGridErrorAttribution<void>(body: () {}),
      throwsArgumentError,
    );
    expect(
      () => runWithGridErrorAttribution<void>(nodePath: '', body: () {}),
      throwsArgumentError,
    );
  });

  test('awaited public failures cross the guarded zone boundary', () async {
    final handle = await runGrid(
      _GuardDelegate(failures: const <_DetachedFailure>[], onState: (_) {}),
      onError: (_) {},
    );

    final reload = handle.hotReload();
    final refusal = expectLater(
      reload,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('tore down before the flush landed'),
        ),
      ),
    );
    await handle.teardown();

    await refusal;
  });
}
