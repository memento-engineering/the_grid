import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_federation/grid_federation.dart';

/// `grid serve` — run as a LESSOR station: offer compute slots over the
/// federation bus (ADR-0011). A peer leases a slot and dispatches a generic
/// command to run HERE. No inference required — this station just executes the
/// dispatched process (the cross-machine MVP).
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
        defaultsTo: 'compute',
        help: 'The resource-asset kind offered.',
      )
      ..addOption('slots', defaultsTo: '1', help: 'How many slots to offer.')
      ..addOption(
        'token',
        help: 'Optional shared secret; when set, peers must send it as '
            'X-Grid-Token (LAN trust, this pass).',
      )
      ..addOption(
        'ttl',
        defaultsTo: '300',
        help: 'Lease TTL in seconds (reaped if idle this long).',
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
    final server = await StationServer.start(
      station: station,
      host: a.option('host')!,
      port: int.parse(a.option('port')!),
      kind: a.option('kind')!,
      offered: int.parse(a.option('slots')!),
      token: token,
      ttl: Duration(seconds: int.parse(a.option('ttl')!)),
      onLog: (m) => stdout.writeln('  $m'),
    );
    stdout
      ..writeln('grid serve — LESSOR station "$station"')
      ..writeln(
        'listening on ${a.option('host')}:${server.port}  ·  offering '
        '${a.option('slots')} ${a.option('kind')} slot(s)'
        '${token != null ? '  ·  token REQUIRED' : ''}',
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
