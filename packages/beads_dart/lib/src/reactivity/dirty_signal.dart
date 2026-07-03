import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'snapshot_reader.dart';

/// Where a dirty signal came from. Signals only need to be *sufficient* — the
/// structural diff is the authority (ADR-0001 Decision 5) — so origins exist
/// for observability/stats, not correctness.
enum DirtyOrigin { workspaceWatch, workingSetProbe, pollTicker, manual }

/// A "something may have changed, re-query" nudge.
class DirtySignal {
  const DirtySignal(this.origin, {this.detail = ''});
  final DirtyOrigin origin;
  final String detail;

  @override
  String toString() =>
      'DirtySignal(${origin.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// A funnel of dirty signals. Implementations push onto [signals]; the
/// [GraphSyncInteractor] coalesces them.
abstract interface class DirtySignalSource {
  Stream<DirtySignal> get signals;
  Future<void> dispose();
}

/// Watches `.beads/` for the local mutation breadcrumbs bd writes
/// (`last-touched`, `hooks.log`, `interactions.jsonl`) — sub-second push for
/// in-workspace mutations.
///
/// Critically, the re-query path must never call `bd show` (it also writes
/// `last-touched`), or this source would feed its own tail. The watcher is
/// filtered to the breadcrumb files only; arbitrary `.beads/` churn (e.g. the
/// Dolt data dir) is ignored.
class WorkspaceBeadsWatcher implements DirtySignalSource {
  WorkspaceBeadsWatcher(
    this.beadsDir, {
    Stream<WatchEvent> Function(String path)? watcherFactory,
  }) : _watcherFactory =
           watcherFactory ?? ((path) => DirectoryWatcher(path).events);

  static const _breadcrumbs = {
    'last-touched',
    'hooks.log',
    'interactions.jsonl',
  };

  final String beadsDir;
  final Stream<WatchEvent> Function(String path) _watcherFactory;
  final _controller = StreamController<DirtySignal>.broadcast();
  StreamSubscription<WatchEvent>? _sub;

  @override
  Stream<DirtySignal> get signals {
    _sub ??= _watcherFactory(beadsDir).listen(_onEvent, onError: (_) {});
    return _controller.stream;
  }

  void _onEvent(WatchEvent event) {
    if (_breadcrumbs.contains(p.basename(event.path))) {
      _controller.add(
        DirtySignal(DirtyOrigin.workspaceWatch, detail: p.basename(event.path)),
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}

/// Polls a [ChangeProbe] (`SELECT @@<db>_working`) on a fixed cadence and emits
/// only when the working-set hash changes. Catches cross-workspace writes that
/// a file watch alone misses, at ~1ms per probe. Reconnect/error recovery is
/// the probe's concern; transient probe errors are swallowed (the next tick
/// retries), and the probe doubles as connection keepalive.
class WorkingSetProbeSource implements DirtySignalSource {
  WorkingSetProbeSource(
    this.probe, {
    this.interval = const Duration(seconds: 1),
  });

  final ChangeProbe probe;
  final Duration interval;
  final _controller = StreamController<DirtySignal>.broadcast();
  Timer? _timer;
  String? _lastHash;
  bool _inFlight = false;

  @override
  Stream<DirtySignal> get signals {
    _timer ??= Timer.periodic(interval, (_) => _tick());
    return _controller.stream;
  }

  Future<void> _tick() async {
    if (_inFlight) return; // never overlap probes
    _inFlight = true;
    try {
      final hash = await probe.probe();
      if (_lastHash != null && hash != _lastHash) {
        _controller.add(DirtySignal(DirtyOrigin.workingSetProbe, detail: hash));
      }
      _lastHash = hash;
    } on Object {
      // Swallow: reconnect is the probe's job; next tick retries.
    } finally {
      _inFlight = false;
    }
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}

/// A coarse backstop that emits unconditionally on a slow cadence. Active only
/// when the SQL probe is unavailable (embedded mode / server down), so the
/// controller still converges via periodic bd-CLI re-query.
class PollingTickerSource implements DirtySignalSource {
  PollingTickerSource({this.interval = const Duration(seconds: 5)});

  final Duration interval;
  final _controller = StreamController<DirtySignal>.broadcast();
  Timer? _timer;

  @override
  Stream<DirtySignal> get signals {
    _timer ??= Timer.periodic(
      interval,
      (_) => _controller.add(const DirtySignal(DirtyOrigin.pollTicker)),
    );
    return _controller.stream;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}

/// A programmatic trigger — e.g. the exploration `requery` tool or a CLI
/// command forcing an immediate re-query.
class ManualDirtySource implements DirtySignalSource {
  final _controller = StreamController<DirtySignal>.broadcast();

  @override
  Stream<DirtySignal> get signals => _controller.stream;

  void trigger({String detail = ''}) =>
      _controller.add(DirtySignal(DirtyOrigin.manual, detail: detail));

  @override
  Future<void> dispose() async => _controller.close();
}

/// True for the breadcrumb filenames the workspace watcher reacts to — exposed
/// for tests and documentation.
bool isBeadsBreadcrumb(String path) =>
    WorkspaceBeadsWatcher._breadcrumbs.contains(p.basename(path));
