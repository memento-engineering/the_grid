import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:grid_federation/grid_federation.dart';

/// Builds the ASSET's dispatch [handler] (+ an optional [banner] line + an
/// optional lessor-teardown [onLeaseEnded] hook) from the parsed args — the
/// seam that keeps `serve` GENERIC ("leasing is core"): the core command owns
/// the lessor lifecycle; the asset domain owns the "use" AND the reap of any
/// work it launched under a lease (ADR-0011 D3 + Hazards). The reference app
/// supplies the compute one; the burn's reaps its follower app.
typedef ServeHandlerFactory =
    ({
      DispatchHandler handler,
      String? banner,
      void Function(String leaseId)? onLeaseEnded,
    })
    Function(
      ArgResults args,
      void Function(String) log,
    );

/// `grid serve` — run as a LESSOR station: offer slots over the federation bus
/// (ADR-0011). A peer leases a slot and dispatches a use to run HERE. GENERIC:
/// the dispatched "use" is the asset domain's, injected via [handlerFor] +
/// [configureFlags] (the runner assembles e.g. the compute bounded-use).
class ServeCommand extends Command<int> {
  /// Wires the generic serve flags, then the asset's [configureFlags]; the
  /// offered [defaultKind] and the dispatch [handlerFor] are the asset's.
  ServeCommand({
    required String defaultKind,
    required void Function(ArgParser) configureFlags,
    required this.handlerFor,
  }) {
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
        defaultsTo: defaultKind,
        help: 'The resource-asset kind offered.',
      )
      ..addOption('slots', defaultsTo: '1', help: 'How many slots to offer.')
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
    configureFlags(argParser);
  }

  /// The asset's dispatch-handler factory (the compute bounded-use in the
  /// reference app).
  final ServeHandlerFactory handlerFor;

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
    final asset = handlerFor(a, (m) => stdout.writeln('  $m'));
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
      handler: asset.handler,
      // The asset's lessor teardown (lease release/reap → reap launched work).
      onLeaseEnded: asset.onLeaseEnded,
      onLog: (m) => stdout.writeln('  $m'),
    );
    stdout
      ..writeln('grid serve — LESSOR station "$station"')
      ..writeln(
        'listening on ${a.option('host')}:${server.port}  ·  offering '
        '${a.option('slots')} ${a.option('kind')} slot(s)'
        '${token != null ? '  ·  token REQUIRED' : ''}',
      );
    if (asset.banner != null) stdout.writeln(asset.banner);
    stdout.writeln('Ctrl-C to stop.');

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
