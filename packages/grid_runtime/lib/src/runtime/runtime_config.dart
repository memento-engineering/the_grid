import 'package:freezed_annotation/freezed_annotation.dart';

part 'runtime_config.freezed.dart';

/// The expected lifetime of a runtime command — gc's `runtime.Lifecycle`
/// (`gascity/internal/runtime/runtime.go:451-457`), trimmed to the two M3
/// cases.
enum Lifecycle {
  /// The default: a long-lived session that stays up across turns until it is
  /// explicitly stopped (gc's empty-string default lifecycle,
  /// `runtime.go:469-470`).
  longLived,

  /// A bounded one-turn command expected to do its work and exit (gc's
  /// `LifecycleOneShot`, `runtime.go:455-456`). The `claude -p` non-interactive
  /// print-mode dogfood invocation is one-shot.
  oneTurn,
}

/// Parameters for starting one agent session — the Dart port of gc's
/// `runtime.Config` (`runtime.go:459-578`), **trimmed to M3** (M3-BUILD-ORDER
/// Track 2): the overlay/pack/MCP/T3/fingerprint/dialog machinery is CUT
/// (reference only). What survives is exactly what [SubprocessProvider] needs to
/// spawn a `claude` per ready bead in its worktree.
///
/// A value type (plain `Config`, no IO, freezed for equality + `copyWith`).
@freezed
abstract class RuntimeConfig with _$RuntimeConfig {
  const RuntimeConfig._();

  const factory RuntimeConfig({
    /// The working directory for the session process — **the per-bead git
    /// worktree** (Track 3 allocates it; gc's `Config.WorkDir`,
    /// `runtime.go:461-462`). Required: an agent never launches into an
    /// unprepared cwd.
    required String workDir,

    /// The executable to run (`claude` for the dogfood). gc splits command +
    /// args; the_grid carries the executable here and the args in [args] so the
    /// no-shell `Process.start(executable, args)` contract holds (no shell word-
    /// splitting; gc's `condition.go:319` exit-code contract).
    required String command,

    /// The argv passed to [command] — permission flag, optional
    /// `--model`/`--effort`, `-p` for non-interactive print mode, the prompt
    /// positional/`--prompt`. NEVER carries a secret (the OAuth token rides
    /// [env]/the allowlist, never argv).
    @Default(<String>[]) List<String> args,

    /// Long-lived vs one-turn (gc's `Config.Lifecycle`, `runtime.go:468-470`).
    @Default(Lifecycle.longLived) Lifecycle lifecycle,

    /// Additional environment variables set in the session, layered OVER the
    /// allowlist and the per-incarnation `GRID_*` env (gc's `Config.Env`,
    /// `runtime.go:472-473`). This is where the **inherited agent token** is
    /// threaded when a caller wants to pass it explicitly rather than inherit it
    /// from the parent allowlist; either way it lands as an env var, never argv.
    @Default(<String, String>{}) Map<String, String> env,

    /// Optional human-readable startup hint surfaced in logs/events — gc's
    /// startup-reliability hints (`runtime.go:483-577`) collapsed to a single
    /// opaque note for M3 (the prompt-prefix / ready-delay / dialog machinery is
    /// CUT). Null when unset.
    String? startupHint,
  }) = _RuntimeConfig;
}

/// What a [RuntimeProvider] can reliably detect, so callers degrade explicitly
/// instead of assuming — gc's `ProviderCapabilities` (`runtime.go:197-199`
/// `Capabilities()`), as a record-style freezed value.
///
/// [SubprocessProvider] reports the honest minimum: it owns the Process handle
/// so it can detect liveness and exit and stream output, but it has no terminal,
/// so attach/activity-from-a-pane are unsupported (a `TmuxProvider` would set
/// those true).
@freezed
abstract class RuntimeCapabilities with _$RuntimeCapabilities {
  const RuntimeCapabilities._();

  const factory RuntimeCapabilities({
    /// Whether the provider can observe agent-process liveness/exit
    /// (`isRunning`/`processAlive`/`RuntimeEvent.exited`).
    @Default(false) bool detectsLiveness,

    /// Whether the provider streams a live transcript (`output(name)`).
    @Default(false) bool streamsOutput,

    /// Whether the provider can attach a user terminal (tmux only; the
    /// subprocess provider cannot).
    @Default(false) bool supportsAttach,

    /// Whether the provider reports last-activity time from terminal I/O
    /// (tmux only).
    @Default(false) bool detectsActivity,
  }) = _RuntimeCapabilities;

  /// The honest capability set for a subprocess provider: liveness + output,
  /// no attach, no terminal-activity.
  static const RuntimeCapabilities subprocess = RuntimeCapabilities(
    detectsLiveness: true,
    streamsOutput: true,
  );
}
