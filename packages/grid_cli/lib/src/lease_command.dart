import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_federation/grid_federation.dart';

/// `grid lease` — run as a LESSEE: lease a compute slot from a peer station and
/// dispatch a command to run THERE, streaming the result back. Proves
/// cross-machine resource leasing (ADR-0011).
///
/// Usage: `grid lease --peer host:port -- <command> [args...]`
class LeaseCommand extends Command<int> {
  /// Wires the lease flags.
  LeaseCommand() {
    argParser
      ..addOption(
        'peer',
        mandatory: true,
        help: 'host:port of the lessor station (e.g. linux-dashboard.local:8080).',
      )
      ..addOption(
        'lessee',
        defaultsTo: Platform.localHostname,
        help: 'This station id (defaults to the hostname).',
      )
      ..addOption('kind', defaultsTo: 'compute', help: 'Resource-asset kind to lease.')
      ..addOption('token', help: 'Shared secret, if the peer requires one.');
  }

  @override
  final String name = 'lease';

  @override
  final String description =
      'Run as a LESSEE: lease a slot from a peer and dispatch a command to run '
      'THERE. Usage: grid lease --peer host:port -- <command> [args...]';

  @override
  Future<int> run() async {
    final a = argResults!;
    final cmdline = a.rest;
    if (cmdline.isEmpty) {
      stderr.writeln(
        'grid lease: provide a command after the options, e.g. '
        '`grid lease --peer host:8080 -- uname -a`',
      );
      return 64;
    }
    final peer = a.option('peer')!;
    final colon = peer.lastIndexOf(':');
    if (colon <= 0 || colon == peer.length - 1) {
      stderr.writeln('grid lease: --peer must be host:port (got "$peer")');
      return 64;
    }
    final host = peer.substring(0, colon);
    final port = int.tryParse(peer.substring(colon + 1));
    if (port == null) {
      stderr.writeln('grid lease: --peer port is not a number (got "$peer")');
      return 64;
    }

    final client = HttpStationClient(host: host, port: port, token: a.option('token'));
    try {
      final p = await client.presence();
      stdout.writeln(
        'peer "${p.station}": ${p.available}/${p.offered} ${p.kinds.join(',')} free',
      );
      final grant = await client.requestLease(
        LeaseRequest(lessee: a.option('lessee')!, kind: a.option('kind')!),
      );
      stdout.writeln('leased ${grant.leaseId} (ttl ${grant.ttlSeconds}s)');

      final cmd = DispatchCommand(
        command: cmdline.first,
        args: cmdline.skip(1).toList(),
      );
      stdout.writeln('dispatching to "${p.station}": ${cmd.command} ${cmd.args.join(' ')}');
      final r = await client.dispatch(grant.leaseId, cmd);
      if (r.stdout.isNotEmpty) stdout.write(r.stdout);
      if (r.stderr.isNotEmpty) stderr.write(r.stderr);
      stdout.writeln(
        '--- exit ${r.exitCode} in ${r.durationMs}ms (ran on "${p.station}") ---',
      );
      await client.release(grant.leaseId);
      stdout.writeln('released ${grant.leaseId}');
      return r.exitCode;
    } on FederationException catch (e) {
      stderr.writeln('grid lease: ${e.message}');
      return 1;
    } finally {
      await client.close();
    }
  }
}
