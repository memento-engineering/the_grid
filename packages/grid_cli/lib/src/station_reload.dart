/// The `reload` client: hot-reload (or hot-restart) a RESIDENT JIT station over
/// its VM service. The dev-mode sibling of RS-5a's [StationAttach] (lock →
/// classify → sealed result), and of the `up`/`down`/`status` verb family
/// RS-5b shipped.
///
/// The ORDER is the safety property: swap the sources FIRST (`reloadSources`),
/// and only re-compose the tree once the VM ACCEPTED them. A rejected swap (a
/// compile error in the landed code) REFUSES — the reload tool is never invoked,
/// so a broken tree is never composed and the running agents keep running.
///
/// Before that ordered mutation, the client reads isolate metadata and refuses
/// launch shapes that have no incremental compiler. It never touches the
/// read-only [StationControl] HTTP surface (which stays GET-only) and never
/// signals the process (`up`/`down` remain the signal lifecycle). It is
/// DEV-MODE only: an AOT station has no VM service and is classified
/// [ReloadNotDevMode].
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLockRecord;
import 'package:grid_exploration/grid_exploration.dart'
    show ReassembleTool, gridExtension;
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'station_lock.dart';

/// The outcome of a source swap — sealed, consumed exhaustively.
sealed class SourceReload {
  const SourceReload();
}

/// The VM accepted the changed sources.
class SourcesSwapped extends SourceReload {
  /// Const-constructible — carries no data.
  const SourcesSwapped();
}

/// The VM REFUSED the sources (a compile error). [details] is the VM's own
/// report, surfaced verbatim — the operator must see WHY.
class SourcesRejected extends SourceReload {
  /// Creates the rejection carrying the VM's [details].
  const SourcesRejected(this.details);

  /// The VM's rejection report.
  final String details;
}

/// The read-only VM-service verdict on whether source reload is safe.
sealed class ReloadCapability {
  const ReloadCapability();
}

/// The bound isolate has a source root and can receive `reloadSources`.
class ReloadSupported extends ReloadCapability {
  /// Const-constructible — carries no data.
  const ReloadSupported();
}

/// The bound isolate cannot safely receive `reloadSources`.
class ReloadUnsupported extends ReloadCapability {
  /// Creates an unsupported verdict carrying the observed VM metadata.
  const ReloadUnsupported(this.reason);

  /// The read-only probe result shown to the operator.
  final String reason;
}

/// One connected VM-service session against the running station — the seam the
/// offline suite fakes (Fakes, not mocks).
abstract interface class StationVmSession {
  /// Reads VM/isolate metadata without sending a reload or load request.
  Future<ReloadCapability> probeReloadCapability();

  /// Swaps changed sources into the running isolate.
  Future<SourceReload> reloadSources();

  /// Invokes `ext.leonard.grid.reload` with [mode]; returns its JSON body.
  Future<Map<String, Object?>> invokeReload(String mode);

  /// Closes the connection.
  Future<void> close();
}

/// The injected connect seam; the real impl is [VmServiceSession.connect].
typedef VmSessionConnector =
    Future<StationVmSession> Function(Uri vmServiceUri);

/// Opens a VM-service connection for [VmServiceSession.connect].
typedef VmServiceConnector = Future<VmService> Function(String uri);

/// The REAL session over `package:vm_service`.
class VmServiceSession implements StationVmSession {
  VmServiceSession._(this._service, this._isolateId);

  /// Connects to [vmServiceUri] (the http:// URI the station advertised) and
  /// binds the station's main isolate.
  static Future<StationVmSession> connect(
    Uri vmServiceUri, {
    VmServiceConnector connectService = vmServiceConnectUri,
  }) async {
    final ws = convertToWebSocketUrl(serviceProtocolUrl: vmServiceUri);
    final service = await connectService(ws.toString());
    final vm = await service.getVM();
    final isolates = (vm.isolates ?? const <IsolateRef>[]).where(
      (isolate) => isolate.isSystemIsolate != true && isolate.id != null,
    );
    if (isolates.isEmpty) {
      await service.dispose();
      throw StateError(
        'the VM service at $vmServiceUri reports no user isolate',
      );
    }
    return VmServiceSession._(service, isolates.first.id!);
  }

  final VmService _service;
  final String _isolateId;

  @override
  Future<ReloadCapability> probeReloadCapability() async {
    final isolate = await _service.getIsolate(_isolateId);
    final rootUri = isolate.rootLib?.uri;
    if (rootUri == null || rootUri.isEmpty) {
      return ReloadUnsupported(
        'isolate ${isolate.name ?? _isolateId} reports no root-library URI; '
        'reload capability cannot be established',
      );
    }
    final root = Uri.tryParse(rootUri);
    if (root?.path.endsWith('.snapshot') ?? rootUri.endsWith('.snapshot')) {
      return ReloadUnsupported(
        'isolate ${isolate.name ?? _isolateId} root library is $rootUri; '
        'a pub App-JIT snapshot has no incremental compiler',
      );
    }
    return const ReloadSupported();
  }

  @override
  Future<SourceReload> reloadSources() async {
    try {
      final report = await _service.reloadSources(_isolateId);
      if (report.success ?? false) return const SourcesSwapped();
      return SourcesRejected(
        jsonEncode(report.json ?? const <String, Object?>{}),
      );
    } on RPCError catch (error) {
      return SourcesRejected('$error');
    }
  }

  @override
  Future<Map<String, Object?>> invokeReload(String mode) async {
    final response = await _service.callServiceExtension(
      gridExtension(ReassembleTool.toolName),
      isolateId: _isolateId,
      args: <String, String>{'mode': mode},
    );
    return response.json ?? const <String, Object?>{};
  }

  @override
  Future<void> close() => _service.dispose();
}

/// The outcome of [StationReload.reload] — sealed so the command's dispatch is
/// exhaustive (the [AttachResult] precedent).
sealed class ReloadResult {
  const ReloadResult();
}

/// The station re-composed. Live sessions were ADOPTED, never killed.
class Reloaded extends ReloadResult {
  /// Creates the success carrying the station's own report.
  const Reloaded({
    required this.mode,
    required this.generation,
    required this.rebuiltBranches,
  });

  /// `reload` or `restart`, as the station reported it.
  final String mode;

  /// The re-composition counter the station is now at.
  final int generation;

  /// How many branches the station's flush rebuilt.
  final int rebuiltBranches;
}

/// No live station to reload (no lock, an unreadable lock, or a dead pid).
class ReloadStationDown extends ReloadResult {
  /// Const-constructible — carries no data.
  const ReloadStationDown();
}

/// The station is LIVE but advertises no VM service — it is not running in dev
/// mode (an AOT binary, or a JIT one started without `--enable-vm-service`). A
/// distinct variant BY CONSTRUCTION: it must never be swallowed into
/// [ReloadStationDown], because the operator's fix is different.
class ReloadNotDevMode extends ReloadResult {
  /// Creates the refusal naming the live [pid].
  const ReloadNotDevMode(this.pid);

  /// The live station's pid.
  final int pid;
}

/// The live station uses a launch shape that cannot safely hot-reload.
class ReloadUnsupportedLaunchShape extends ReloadResult {
  /// Creates the refusal carrying the read-only probe [reason].
  const ReloadUnsupportedLaunchShape(this.reason);

  /// The VM/isolate metadata that made reload unsafe.
  final String reason;
}

/// The reload was REFUSED — the VM rejected the sources (a compile error), the
/// tool is absent (a station that composed no [ReassembleTool]), or the
/// station's re-composition itself threw. LOUD: [reason] is surfaced verbatim.
class ReloadRefused extends ReloadResult {
  /// Creates the refusal carrying its [reason].
  const ReloadRefused(this.reason);

  /// Why the reload was refused.
  final String reason;
}

/// The reload client (Services: stateless I/O; the reference type carries the
/// classifier). Every seam is injected: [connect] defaults to the real
/// [VmServiceSession.connect] and [isPidAlive] to RS-2's real [defaultPidProbe].
class StationReload {
  /// Creates the client; every seam defaults to its real implementation.
  StationReload({VmSessionConnector? connect, PidProbe? isPidAlive})
    : _connect = connect ?? VmServiceSession.connect,
      _isPidAlive = isPidAlive ?? defaultPidProbe;

  final VmSessionConnector _connect;
  final PidProbe _isPidAlive;

  /// Reloads the station whose lock lives under `<[gridHome]>/.grid/`: swap
  /// sources → re-compose. [restart] re-runs the station's delegate factory
  /// (hot RESTART) instead of its master build (hot RELOAD). [vmServiceUri]
  /// overrides the lock's advertisement (an operator pasting the URI the VM
  /// printed at boot).
  Future<ReloadResult> reload({
    required String gridHome,
    bool restart = false,
    Uri? vmServiceUri,
  }) async {
    final record = await _readLock(gridHome);
    if (record == null || !_isPidAlive(record.pid)) {
      return const ReloadStationDown();
    }
    final advertised = record.vmServiceUri;
    final target =
        vmServiceUri ?? (advertised == null ? null : Uri.parse(advertised));
    if (target == null) return ReloadNotDevMode(record.pid);

    final session = await _connect(target);
    try {
      // 1. Prove that a source swap is safe without sending one.
      final capability = await session.probeReloadCapability();
      switch (capability) {
        case ReloadUnsupported(:final reason):
          return ReloadUnsupportedLaunchShape(reason);
        case ReloadSupported():
          break;
      }
      // 2. The sources FIRST. A rejected swap never reaches the tree.
      final swap = await session.reloadSources();
      switch (swap) {
        case SourcesRejected(:final details):
          return ReloadRefused(details);
        case SourcesSwapped():
          break;
      }
      // 3. Then the re-composition, inside the station.
      final mode = restart ? ReassembleTool.modes[1] : ReassembleTool.modes[0];
      final body = await session.invokeReload(mode);
      if (body['ok'] != true) {
        return ReloadRefused('${body['error'] ?? body}');
      }
      final value = body['value'] as Map<String, Object?>? ?? const {};
      return Reloaded(
        mode: value['mode'] as String? ?? mode,
        generation: value['generation'] as int? ?? -1,
        rebuiltBranches: value['rebuiltBranches'] as int? ?? -1,
      );
    } on Object catch (error) {
      // A missing tool / a throwing re-composition arrives as an RPCError:
      // REFUSED, loudly, with the VM's message.
      return ReloadRefused('$error');
    } finally {
      await session.close();
    }
  }

  /// Reads the lock at [gridHome], or null when there is none or it is
  /// unreadable (a torn write — no live holder can be named).
  Future<StationLockRecord?> _readLock(String gridHome) async {
    final file = File(StationLockService.lockPath(gridHome));
    if (!await file.exists()) return null;
    try {
      return StationLockRecord.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }
}
