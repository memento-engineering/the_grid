import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart' show isStrictlyUnderDir;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// One asset manifest belonging to a substation.
class HookManifest {
  /// Creates an asset manifest reference.
  const HookManifest({required this.source, required this.path});

  /// The asset that authored this manifest.
  final String source;

  /// The manifest's filesystem path.
  final String path;
}

/// The immutable manifest roster for one authored substation.
class HookSubstation {
  /// Creates a substation manifest roster.
  const HookSubstation({
    required this.substation,
    required this.root,
    this.manifests = const <HookManifest>[],
  });

  /// The authored substation id.
  final String substation;

  /// The root whose strict descendants this substation owns.
  final String root;

  /// The asset manifests authored into this substation.
  final List<HookManifest> manifests;
}

/// A hook execution mode declared by an extension manifest.
enum HookMode {
  /// The hook may repair selected files.
  fix,

  /// The hook gates the triggering operation.
  gate,

  /// The hook reports without fixing or gating.
  notify;

  /// Parses a manifest mode value.
  static HookMode parse(String value) => switch (value) {
    'fix' => HookMode.fix,
    'gate' => HookMode.gate,
    'notify' => HookMode.notify,
    _ => throw FormatException('unknown hook mode: $value'),
  };

  /// The mode's serialized manifest name.
  String get wireName => switch (this) {
    HookMode.fix => 'fix',
    HookMode.gate => 'gate',
    HookMode.notify => 'notify',
  };
}

/// One resolved deterministic hook run specification.
class HookContribution {
  /// Creates a resolved hook contribution.
  const HookContribution({
    required this.id,
    required this.source,
    required this.run,
    required this.select,
    required this.mode,
    required this.timeoutMs,
  });

  /// The contribution id.
  final String id;

  /// The asset that declared the contribution.
  final String source;

  /// The command to run.
  final String run;

  /// The file-selection expression.
  final String select;

  /// The declared execution mode.
  final HookMode mode;

  /// The maximum execution time in milliseconds.
  final int timeoutMs;

  /// Serializes this contribution to its transport shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source': source,
    'run': run,
    'select': select,
    'mode': mode.wireName,
    'timeout_ms': timeoutMs,
  };
}

/// The complete response for one hook-resolution read.
class HooksResponse {
  /// Creates a hook-resolution response.
  const HooksResponse({
    required this.event,
    required this.worktree,
    required this.substation,
    required this.contributions,
  });

  /// The requested hook event.
  final String event;

  /// The requested worktree path.
  final String worktree;

  /// The owning substation id.
  final String substation;

  /// The matching contributions in declaration order.
  final List<HookContribution> contributions;

  /// Serializes this response to its transport shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'event': event,
    'worktree': worktree,
    'substation': substation,
    'contributions': <Map<String, Object?>>[
      for (final contribution in contributions) contribution.toJson(),
    ],
  };
}

/// A deterministic HTTP-facing refusal from hook resolution.
class HooksResolutionException implements Exception {
  /// Creates a refusal with an HTTP [statusCode] and safe [message].
  const HooksResolutionException(this.statusCode, this.message);

  /// The HTTP status code to return.
  final int statusCode;

  /// The transport-safe error message.
  final String message;
}

/// Resolves hook declarations for an event/worktree without executing them.
class HooksResolver {
  /// Creates a resolver over an immutable authored substation roster.
  const HooksResolver({this.substations = const <HookSubstation>[]});

  /// The configured substation manifest rosters.
  final List<HookSubstation> substations;

  /// Resolves contributions for [event] and [worktree].
  Future<HooksResponse> resolve({
    required String event,
    required String worktree,
  }) async {
    if (event.trim().isEmpty) {
      throw const HooksResolutionException(400, 'event must be non-empty');
    }
    if (worktree.trim().isEmpty || !p.isAbsolute(worktree)) {
      throw const HooksResolutionException(
        400,
        'worktree must be a non-empty absolute path',
      );
    }
    final matches = <HookSubstation>[
      for (final candidate in substations)
        if (isStrictlyUnderDir(candidate.root, worktree)) candidate,
    ];
    if (matches.isEmpty) {
      throw const HooksResolutionException(
        404,
        'worktree is outside every configured substation',
      );
    }
    if (matches.length != 1) {
      throw const HooksResolutionException(
        500,
        'worktree matches more than one configured substation',
      );
    }
    final owner = matches.single;
    final contributions = <HookContribution>[];
    for (final manifest in owner.manifests) {
      contributions.addAll(await _readManifest(manifest, event));
    }
    return HooksResponse(
      event: event,
      worktree: worktree,
      substation: owner.substation,
      contributions: List<HookContribution>.unmodifiable(contributions),
    );
  }

  Future<List<HookContribution>> _readManifest(
    HookManifest manifest,
    String event,
  ) async {
    try {
      final document = loadYaml(await File(manifest.path).readAsString());
      if (document is! Map<Object?, Object?>) {
        throw const FormatException('manifest root must be a map');
      }
      final hooks = document['hooks'];
      if (hooks == null) return const <HookContribution>[];
      if (hooks is! List<Object?>) {
        throw const FormatException('hooks must be a list');
      }
      return <HookContribution>[
        for (final raw in hooks)
          if (_requiredString(_entry(raw), 'event') == event)
            HookContribution(
              id: _requiredString(_entry(raw), 'id'),
              source: manifest.source,
              run: _requiredString(_entry(raw), 'run'),
              select: _requiredString(_entry(raw), 'select'),
              mode: HookMode.parse(_requiredString(_entry(raw), 'mode')),
              timeoutMs: _positiveInt(_entry(raw), 'timeout_ms'),
            ),
      ];
    } on HooksResolutionException {
      rethrow;
    } on Object catch (error) {
      throw HooksResolutionException(
        500,
        'invalid hooks manifest ${manifest.path}: $error',
      );
    }
  }

  Map<Object?, Object?> _entry(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const FormatException('hook entry must be a map');
    }
    return raw;
  }

  String _requiredString(Map<Object?, Object?> entry, String key) {
    final value = entry[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  int _positiveInt(Map<Object?, Object?> entry, String key) {
    final value = entry[key];
    if (value is! int || value <= 0) {
      throw FormatException('$key must be a positive integer');
    }
    return value;
  }
}
