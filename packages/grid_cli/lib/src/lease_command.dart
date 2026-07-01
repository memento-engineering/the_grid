import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_federation/grid_federation.dart';

/// Builds the ASSET's dispatch payload from the rest args — the seam that keeps
/// `lease` GENERIC ("leasing is core"; the payload shape is the asset domain's,
/// ADR-0011 D3 — the reference app supplies the compute one).
typedef LeasePayloadBuilder = Map<String, dynamic> Function(List<String> rest);

/// Renders the ASSET's opaque dispatch result, returning the exit code (the
/// compute renderer prints stdout/stderr + the exit line).
typedef LeaseResultRenderer =
    int Function(
      Map<String, dynamic> result,
      void Function(String) out,
      void Function(String) err,
    );

/// `grid lease` — run as a LESSEE: lease a slot from a peer station and
/// dispatch a use to run THERE, rendering the result. GENERIC: the payload +
/// result shapes are the asset domain's, injected via [payloadFor]/[render].
///
/// Usage: `grid lease --peer host:port -- <command> [args...]`
class LeaseCommand extends Command<int> {
  /// Wires the lease flags; the payload/result codecs + [defaultKind] are the
  /// asset's.
  LeaseCommand({
    required String defaultKind,
    required this.payloadFor,
    required this.render,
  }) {
    argParser
      ..addOption(
        'peer',
        mandatory: true,
        help:
            'host:port of the lessor station (e.g. linux-dashboard.local:8080).',
      )
      ..addOption(
        'lessee',
        defaultsTo: Platform.localHostname,
        help: 'This station id (defaults to the hostname).',
      )
      ..addOption(
        'kind',
        defaultsTo: defaultKind,
        help: 'Resource-asset kind to lease.',
      )
      ..addOption('token', help: 'Shared secret, if the peer requires one.');
  }

  /// The asset's payload builder (compute: `DispatchCommand.toJson`).
  final LeasePayloadBuilder payloadFor;

  /// The asset's result renderer (compute: `CommandResult` → stdout/stderr).
  final LeaseResultRenderer render;

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

    final client = HttpStationClient(
      host: host,
      port: port,
      token: a.option('token'),
    );
    // A per-invocation idempotency key so a retried lease/dispatch dedups at the
    // owner (never a second grant or a second run).
    final lessee = a.option('lessee')!;
    final idem = '$lessee-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final p = await client.presence();
      stdout.writeln(
        'peer "${p.station}": ${p.available}/${p.offered} ${p.kinds.join(',')} free',
      );
      final grant = await client.requestLease(
        LeaseRequest(
          lessee: lessee,
          kind: a.option('kind')!,
          idempotencyKey: idem,
        ),
      );
      stdout.writeln(
        'leased ${grant.leaseId} (ttl ${grant.ttlSeconds}s, '
        'fence ${grant.fencingToken})',
      );

      stdout.writeln(
        'dispatching to "${p.station}": ${cmdline.join(' ')}',
      );
      final raw = await client.dispatch(
        grant,
        payloadFor(cmdline),
        idempotencyKey: idem,
      );
      // The asset's renderer interprets the opaque result envelope.
      final code = render(raw, stdout.write, stderr.write);
      stdout.writeln('--- exit $code (ran on "${p.station}") ---');
      await client.release(grant);
      stdout.writeln('released ${grant.leaseId}');
      return code;
    } on FederationException catch (e) {
      stderr.writeln('grid lease: ${e.message}');
      return 1;
    } finally {
      await client.close();
    }
  }
}
