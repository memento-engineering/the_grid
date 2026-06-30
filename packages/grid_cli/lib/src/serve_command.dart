import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_federation/grid_federation.dart';

/// `grid serve` — run as a LESSOR station: offer compute slots over the
/// federation bus (ADR-0011). A peer leases a slot and dispatches a generic
/// command to run HERE. No inference required — this station just executes the
/// dispatched process, BOUNDED by the compute domain's allow-list (ADR-0011 D3:
/// the asset domain — not the kind-agnostic core — owns the "use").
class ServeCommand extends Command<int> {
  /// Wires the serve flags.
  ServeCommand() {
    argParser
      ..addOption(
        'station',
        defaultsTo: Platform.localHostname,
        help: 'This station id (defaults to the hostname).',
      )
      ..addOption('host', defaultsTo: '0.0.0.0', help: 'Bind address.')
      ..addOption('port', defaultsTo: '8080', help: 'Bind port.')
      ..addOption(
        'kind',
        defaultsTo: kComputeKind,
        help: 'The resource-asset kind offered.',
      )
      ..addOption('slots', defaultsTo: '1', help: 'How many slots to offer.')
      ..addMultiOption(
        'allow',
        defaultsTo: const [
          'dart',
          'echo',
          'flutter',
          'git',
          'hostname',
          'melos',
          'uname',
        ],
        help:
            'The executables the lessor will run (the bounded-use allow-list). A '
            'dispatched command not on this list is REFUSED (no shell-as-a-'
            'service; ADR-0011 RCE-bounds).',
      )
      ..addOption(
        'exec-timeout',
        defaultsTo: '300',
        help: 'Per-command timeout in seconds (the bounded-use upper bound).',
      )
      ..addOption(
        'token',
        help:
            'Optional shared secret; when set, peers must send it as '
            'X-Grid-Token (LAN trust, this pass).',
      )
      ..addOption(
        'ttl',
        defaultsTo: '300',
        help: 'Lease TTL in seconds (reaped if idle this long).',
      )
      ..addOption(
        'max-lifetime',
        defaultsTo: '3600',
        help:
            'Max lease lifetime in seconds (caps total TTL renewal — the '
            'starvation bound; a held lease is reaped past this regardless of '
            'activity).',
      )
      ..addOption(
        'lease-wait',
        defaultsTo: '0',
        help:
            'Seconds a full-capacity request waits in the FIFO queue before '
            'it is denied (0 = deny immediately).',
      )
      ..addOption(
        'max-queue',
        defaultsTo: '64',
        help: 'Max requests that may wait in the FIFO queue.',
      );
  }

  @override
  final String name = 'serve';

  @override
  final String description =
      'Run as a LESSOR station: offer compute slots over the federation bus; a '
      'peer leases a slot and dispatches a command to run here.';

  @override
  Future<int> run() async {
    final a = argResults!;
    final station = a.option('station')!;
    final token = a.option('token');
    final bounds = ComputeBounds(
      allowedCommands: a.multiOption('allow').toSet(),
      timeout: Duration(seconds: int.parse(a.option('exec-timeout')!)),
    );
    final server = await StationServer.start(
      station: station,
      host: a.option('host')!,
      port: int.parse(a.option('port')!),
      kind: a.option('kind')!,
      offered: int.parse(a.option('slots')!),
      token: token,
      ttl: Duration(seconds: int.parse(a.option('ttl')!)),
      maxLifetime: Duration(seconds: int.parse(a.option('max-lifetime')!)),
      leaseWait: Duration(seconds: int.parse(a.option('lease-wait')!)),
      maxQueueDepth: int.parse(a.option('max-queue')!),
      handler: computeDispatchHandler(
        bounds: bounds,
        onLog: (m) => stdout.writeln('  $m'),
      ),
      onLog: (m) => stdout.writeln('  $m'),
    );
    stdout
      ..writeln('grid serve — LESSOR station "$station"')
      ..writeln(
        'listening on ${a.option('host')}:${server.port}  ·  offering '
        '${a.option('slots')} ${a.option('kind')} slot(s)'
        '${token != null ? '  ·  token REQUIRED' : ''}',
      )
      ..writeln(
        'bounded use: allow-list ${(bounds.allowedCommands.toList()..sort())}  ·  '
        'timeout ${bounds.timeout.inSeconds}s',
      )
      ..writeln('Ctrl-C to stop.');

    final done = Completer<void>();
    final sub = ProcessSignal.sigint.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    await sub.cancel();
    await server.close();
    stdout.writeln('stopped.');
    return 0;
  }
}
