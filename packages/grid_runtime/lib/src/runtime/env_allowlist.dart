import 'dart:io';

/// The **explicit** parent-environment allowlist for a spawned agent child —
/// the Dart port of gc's `processenv.ProviderProcessPassthroughEnv`
/// (`gascity/internal/processenv/provider.go:98-126`).
///
/// **Why an allowlist, not the inherited env.** [SubprocessProvider] keeps
/// `includeParentEnvironment: false` (mirroring [SystemProcessRunner], gc's
/// `condition.go:79-150`), so the child sees ONLY what this builder forwards
/// plus the per-incarnation `GRID_*` injection. The agent's
/// `CLAUDE_CODE_OAUTH_TOKEN` is forwarded *as an inherited env var on this
/// allowlist* — never on argv (the plaintext leak flagged on gc's separate
/// control-dispatcher; CLAUDE.md side-finding). Host secrets that are NOT on
/// the list — `GC_DOLT_PASSWORD`, `GC_DOLT_USER`, and every other ambient
/// var — are **never** leaked into the agent child. This is a security
/// boundary, not a convenience.
///
/// **The list is curated, not auto-discovered** (gc's words): persistent
/// supervisor env has a bounded size, so the only wildcards are the
/// provider-credential **prefixes** ([_providerCredentialPrefixes]) and the
/// exact AWS keys ([_providerCredentialExactKeys]); everything else is an
/// exact name. We keep gc's behaviour with two deliberate trims for M3
/// (ADR-0004 + M3-BUILD-ORDER Track 2 CUT): no OpenTelemetry env map (gc's
/// `telemetry.OTELEnvMap()` — not wired in the_grid) and no locale-defaulting
/// dance beyond forwarding `LANG`/`LC_*` when present.
///
/// Pure over an injected `Map<String,String>` reader so the whole policy is
/// tested offline with a fake environment (Fakes, not mocks) — the real
/// process environment is read only by [systemEnvironment].
class AgentEnvAllowlist {
  const AgentEnvAllowlist();

  /// Exact env-var names always forwarded when present and non-empty. Mirrors
  /// gc's `provider.go:103-121` fixed block (PATH/HOME/USER/LOGNAME, the
  /// `CLAUDE_*` config + the **OAuth token**, and the `XDG_*`/locale context an
  /// agent needs to start reliably).
  static const List<String> exactKeys = <String>[
    'PATH',
    'HOME',
    'USER',
    'LOGNAME',
    'CLAUDE_CONFIG_DIR',
    // The agent credential. Forwarded as an inherited env var, NEVER on argv.
    'CLAUDE_CODE_OAUTH_TOKEN',
    'CLAUDE_CODE_SUBAGENT_MODEL',
    'CLAUDE_CODE_EFFORT_LEVEL',
    'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
    'LANG',
    'LC_ALL',
    'LC_CTYPE',
    'XDG_CONFIG_HOME',
    'XDG_STATE_HOME',
  ];

  /// Provider-credential env-var name **prefixes** — the only wildcards.
  /// Verbatim from gc's `providerCredentialEnvPrefixes`
  /// (`provider.go:39-56`); a var whose name starts with any of these is an
  /// agent-provider credential and is forwarded.
  static const List<String> _providerCredentialPrefixes = <String>[
    'ANTHROPIC_',
    'AZURE_',
    'CEREBRAS_',
    'COHERE_',
    'DEEPSEEK_',
    'FIREWORKS_',
    'GEMINI_',
    'GOOGLE_',
    'GROQ_',
    'MISTRAL_',
    'OLLAMA_',
    'OPENAI_',
    'OPENROUTER_',
    'TOGETHER_',
    'VERTEX_',
    'XAI_',
  ];

  /// Exact provider-credential keys for ecosystems whose namespace is broader
  /// than provider auth (gc uses exact names so unrelated AWS tooling state is
  /// not persisted). Verbatim from gc's `providerCredentialEnvKeys`
  /// (`provider.go:60-82`).
  static const Set<String> _providerCredentialExactKeys = <String>{
    'AWS_ACCESS_KEY_ID',
    'AWS_BEARER_TOKEN_BEDROCK',
    'AWS_CA_BUNDLE',
    'AWS_CONFIG_FILE',
    'AWS_CONTAINER_AUTHORIZATION_TOKEN',
    'AWS_CONTAINER_CREDENTIALS_FULL_URI',
    'AWS_CONTAINER_CREDENTIALS_RELATIVE_URI',
    'AWS_DEFAULT_REGION',
    'AWS_EC2_METADATA_DISABLED',
    'AWS_ENDPOINT_URL',
    'AWS_ENDPOINT_URL_BEDROCK',
    'AWS_PROFILE',
    'AWS_REGION',
    'AWS_ROLE_ARN',
    'AWS_SDK_LOAD_CONFIG',
    'AWS_SECRET_ACCESS_KEY',
    'AWS_SESSION_TOKEN',
    'AWS_SHARED_CREDENTIALS_FILE',
    'AWS_USE_DUALSTACK_ENDPOINT',
    'AWS_USE_FIPS_ENDPOINT',
    'AWS_WEB_IDENTITY_TOKEN_FILE',
  };

  /// Whether [key] belongs to the curated provider-credential allowlist
  /// (exact key OR matching prefix). gc's `IsProviderCredentialEnv`
  /// (`provider.go:86-96`).
  bool isProviderCredentialEnv(String key) {
    if (_providerCredentialExactKeys.contains(key)) return true;
    for (final prefix in _providerCredentialPrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  /// Builds the forwarded subset of [parentEnv]: every [exactKeys] entry that
  /// is present and non-empty, plus every provider-credential var
  /// ([isProviderCredentialEnv]) that is present and non-empty.
  ///
  /// Empty values are dropped (gc's `if v != ""` guards), so an exported-but-
  /// empty `GC_DOLT_PASSWORD` could never sneak through even if it were on the
  /// list — and it is not on the list at all. The result is a fresh map; the
  /// caller layers the per-incarnation `GRID_*` env and any [RuntimeConfig.env]
  /// on top.
  Map<String, String> build(Map<String, String> parentEnv) {
    final out = <String, String>{};
    for (final key in exactKeys) {
      final v = parentEnv[key];
      if (v != null && v.isNotEmpty) out[key] = v;
    }
    parentEnv.forEach((key, value) {
      if (value.isEmpty) return;
      if (isProviderCredentialEnv(key)) out[key] = value;
    });
    return out;
  }

  /// Convenience: [build] over the real process environment. The ONLY place
  /// this class touches `dart:io`; everything else is pure over an injected
  /// map so the allowlist is unit-tested with a fake parent env.
  Map<String, String> fromSystem() => build(systemEnvironment());
}

/// The live process environment as a plain map. Wrapped so callers and tests
/// share one read point (and so a test can prove a real exported
/// `GC_DOLT_PASSWORD` is filtered by running [AgentEnvAllowlist.build] over
/// this map).
Map<String, String> systemEnvironment() =>
    Map<String, String>.from(Platform.environment);
