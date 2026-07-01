/// The DART domain's exported CLI components — the asset's Command offering
/// beside its domain components (the CLI-SDK model: an asset ships domain code
/// AND reusable Commands; a runner assembles the ones it wants).
///
/// THIN by rule: all logic lives in [DartLinkService] (UI-drivable — a Flutter
/// app executes the same service); these Commands only parse flags and render
/// the sealed [LinkOutcome]. Pub is subordinate to the Dart domain, so `link`
/// is a SUBcommand of [DartCommand] (`grid dart link ...`), not a top-level
/// `pub` anything.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'dart_link_service.dart';
import 'pub_links.dart';

/// `dart` — the DART domain umbrella command (subcommands carry the verbs).
class DartCommand extends Command<int> {
  /// Creates the umbrella with its subcommands.
  DartCommand({DartLinkService service = const DartLinkService()}) {
    addSubcommand(DartLinkCommand(service: service));
  }

  @override
  final String name = 'dart';

  @override
  final String description =
      'The DART domain: typed grid.dart configuration applied to a checkout '
      '(pub dev-time linkage first).';
}

/// `dart link` — apply a work bead's declared pub linkage to a checkout:
/// decode the `grid.dart` envelope and write/remove `pubspec_overrides.yaml`
/// for the context.
class DartLinkCommand extends Command<int> {
  /// Creates the link command over [service] (injectable for tests).
  DartLinkCommand({DartLinkService service = const DartLinkService()})
    : _service = service {
    argParser
      ..addOption(
        'metadata',
        mandatory: true,
        help:
            'Path to a JSON file carrying the work bead\'s metadata map (the '
            'grid.dart envelope rides it). The live provision path reads the '
            'bead directly; this flag is the offline/manual surface.',
      )
      ..addOption(
        'context',
        mandatory: true,
        allowed: ['dev', 'worktree', 'stable'],
        help:
            'The resolution situation: dev (root checkout — paths as '
            'declared), worktree (deep per-bead worktree — paths absolutized '
            'against --dev-root), stable (no overrides; removes a generated '
            'file).',
      )
      ..addOption(
        'dir',
        help:
            'The workspace ROOT to apply into (pub honors '
            'pubspec_overrides.yaml at the workspace root). Defaults to the '
            'current directory.',
      )
      ..addOption(
        'dev-root',
        help:
            'The station dev root relative dev paths absolutize against '
            '(worktree context). Omit when every declared path is absolute.',
      );
  }

  final DartLinkService _service;

  @override
  final String name = 'link';

  @override
  final String description =
      'Apply the grid.dart pub linkage: write/remove pubspec_overrides.yaml '
      'for a context.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final context = PubLinkContext.parse(args.option('context'));
    if (context == null) {
      stderr.writeln('dart link: unknown --context');
      return 64;
    }
    final metadataFile = File(args.option('metadata')!);
    if (!metadataFile.existsSync()) {
      stderr.writeln('dart link: no such metadata file: ${metadataFile.path}');
      return 64;
    }
    final Map<String, dynamic> metadata;
    try {
      metadata = jsonDecode(await metadataFile.readAsString())
          as Map<String, dynamic>;
    } on Object catch (e) {
      stderr.writeln('dart link: metadata is not a JSON object: $e');
      return 64;
    }

    final outcome = await _service.apply(
      metadata: metadata,
      context: context,
      workspaceDir: args.option('dir') ?? Directory.current.path,
      devRoot: args.option('dev-root'),
    );
    switch (outcome) {
      case LinkApplied(:final file, :final packages):
        stdout.writeln('linked ${packages.join(', ')} → $file');
        return 0;
      case LinkCleared(:final removed):
        stdout.writeln(
          removed
              ? 'no links for this context — removed the generated overrides'
              : 'no links for this context — nothing to remove',
        );
        return 0;
      case LinkNoConfig():
        stdout.writeln('no grid.dart config on this bead — nothing to do');
        return 0;
      case LinkRefused(:final reason):
        stderr.writeln('dart link: refused (fail-closed): $reason');
        return 1;
    }
  }
}
