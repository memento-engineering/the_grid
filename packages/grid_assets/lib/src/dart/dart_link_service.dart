/// The DART-domain linkage SERVICE — the reusable lib layer behind the exported
/// Command (the layering rule: a Command is a thin adapter; a Flutter app must
/// be able to execute this via UI, so the logic lives HERE, never on the
/// Command).
///
/// Stateless I/O (predictable-flutter Services): decode the `grid.dart`
/// envelope off a bead's metadata → derive the `pubspec_overrides.yaml`
/// content for the context (pure, `pubspecOverridesFor`) → write/remove the
/// file at the target workspace root. Pub honors `pubspec_overrides.yaml` at
/// the WORKSPACE ROOT (resolution is workspace-wide), so [workspaceDir] must be
/// the checkout/worktree root, not a member package dir.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_domain.dart';
import 'pub_links.dart';

/// The overrides file name pub honors beside a pubspec.
const String kPubspecOverridesFile = 'pubspec_overrides.yaml';

/// What applying the linkage did — sealed so callers (the Command, a future
/// Flutter UI) render exhaustively.
sealed class LinkOutcome {
  const LinkOutcome();
}

/// Overrides were written for [packages] at [file].
class LinkApplied extends LinkOutcome {
  /// Wraps the written [file] + the overridden [packages].
  const LinkApplied({required this.file, required this.packages});

  /// The written `pubspec_overrides.yaml` path.
  final String file;

  /// The packages the file overrides (sorted).
  final List<String> packages;
}

/// No overrides apply for this context; an existing generated file was
/// [removed] (a stable apply clears a stale dev link — but never a file this
/// domain didn't generate).
class LinkCleared extends LinkOutcome {
  /// Wraps whether a file was actually [removed].
  const LinkCleared({required this.removed});

  /// True when an existing generated overrides file was deleted.
  final bool removed;
}

/// The bead declares no `grid.dart` config — nothing was touched.
class LinkNoConfig extends LinkOutcome {
  /// The no-config outcome.
  const LinkNoConfig();
}

/// The envelope could not be used (incompatible pack version / malformed) —
/// FAIL-CLOSED: nothing was touched.
class LinkRefused extends LinkOutcome {
  /// Wraps the [reason] (diagnostics).
  const LinkRefused(this.reason);

  /// Why the envelope was refused.
  final String reason;
}

/// Applies a work bead's declared pub linkage to a checkout (stateless; safe
/// to construct anywhere — a CLI Command, a Flutter interactor).
class DartLinkService {
  /// Creates the service.
  const DartLinkService();

  /// Decodes the `grid.dart` envelope from [metadata] and applies its pub
  /// linkage for [context] at [workspaceDir] (the workspace ROOT):
  ///
  /// - links with dev paths → writes [kPubspecOverridesFile] (worktree context
  ///   absolutizes relative paths against [devRoot] — fail-closed without one);
  /// - stable / no dev links → removes a previously GENERATED overrides file
  ///   (never one this domain didn't write — a hand-authored file is left
  ///   alone and reported un-removed);
  /// - no `grid.dart` on the bead → touches nothing ([LinkNoConfig]);
  /// - incompatible/malformed envelope → touches nothing ([LinkRefused]).
  Future<LinkOutcome> apply({
    required Map<String, dynamic> metadata,
    required PubLinkContext context,
    required String workspaceDir,
    String? devRoot,
  }) async {
    switch (decodeDartEnvelope(metadata)) {
      case DartEnvelopeAbsent():
        return const LinkNoConfig();
      case DartEnvelopeIncompatible(:final version):
        return LinkRefused(
          'grid.dart envelope written by an incompatible pack '
          '(assets_version $version; this pack reads $kDartAssetsVersion)',
        );
      case DartEnvelopeMalformed(:final reason):
        return LinkRefused('grid.dart envelope malformed: $reason');
      case DartEnvelopeDecoded(:final config):
        final String? content;
        try {
          content = pubspecOverridesFor(
            config.pub,
            context,
            devRoot: devRoot,
          );
        } on StateError catch (e) {
          return LinkRefused(e.message);
        }
        final file = File(p.join(workspaceDir, kPubspecOverridesFile));
        if (content == null) return _clear(file);
        await file.writeAsString(content);
        return LinkApplied(
          file: file.path,
          packages: [
            for (final l in config.pub.links)
              if (l.devPath != null) l.package,
          ]..sort(),
        );
    }
  }

  /// Removes [file] only when THIS domain generated it (the marker comment) —
  /// a hand-authored `pubspec_overrides.yaml` is never deleted, and anything
  /// unreadable (a dir/odd link in the file's place) is left alone rather than
  /// guessed at (fail-closed: when in doubt, don't delete).
  Future<LinkOutcome> _clear(File file) async {
    if (!file.existsSync()) return const LinkCleared(removed: false);
    final String head;
    try {
      head = await file
          .openRead(0, 128)
          .transform(const SystemEncoding().decoder)
          .join();
    } on FileSystemException {
      return const LinkCleared(removed: false);
    }
    if (!head.startsWith('# Generated by the grid.dart domain')) {
      return const LinkCleared(removed: false);
    }
    await file.delete();
    return const LinkCleared(removed: true);
  }
}
