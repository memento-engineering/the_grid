import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('AgentEnvAllowlist (pure, over a fake parent env)', () {
    const allowlist = AgentEnvAllowlist();

    test('forwards the OAuth token and the fixed allowlist entries', () {
      final parent = <String, String>{
        'CLAUDE_CODE_OAUTH_TOKEN': 'fake-oauth-abc123',
        'HOME': '/Users/tgdog',
        'USER': 'tgdog',
        'LOGNAME': 'tgdog',
        'PATH': '/usr/bin:/bin',
        'CLAUDE_CONFIG_DIR': '/Users/tgdog/.claude',
      };

      final child = allowlist.build(parent);

      expect(child['CLAUDE_CODE_OAUTH_TOKEN'], 'fake-oauth-abc123');
      expect(child['HOME'], '/Users/tgdog');
      expect(child['USER'], 'tgdog');
      expect(child['LOGNAME'], 'tgdog');
      expect(child['PATH'], '/usr/bin:/bin');
      expect(child['CLAUDE_CONFIG_DIR'], '/Users/tgdog/.claude');
    });

    test('FILTERS OUT GC_DOLT_PASSWORD and other host secrets', () {
      final parent = <String, String>{
        'CLAUDE_CODE_OAUTH_TOKEN': 'fake-oauth',
        'GC_DOLT_PASSWORD': 'super-secret-dolt-pw',
        'GC_DOLT_USER': 'gc',
        'GT_ROOT': '/workspace/gascity-root',
        'SOME_OTHER_SECRET': 'nope',
      };

      final child = allowlist.build(parent);

      expect(child.containsKey('GC_DOLT_PASSWORD'), isFalse);
      expect(child.containsKey('GC_DOLT_USER'), isFalse);
      expect(child.containsKey('GT_ROOT'), isFalse);
      expect(child.containsKey('SOME_OTHER_SECRET'), isFalse);
      // The token still made it through.
      expect(child['CLAUDE_CODE_OAUTH_TOKEN'], 'fake-oauth');
    });

    test(
      'forwards provider-credential prefixes (ANTHROPIC_) and exact AWS keys',
      () {
        final parent = <String, String>{
          'ANTHROPIC_API_KEY': 'sk-ant-xxx',
          'OPENAI_API_KEY': 'sk-oai-yyy',
          'AWS_ACCESS_KEY_ID': 'AKIA',
          'AWS_SECRET_ACCESS_KEY': 'secret',
          'RANDOM_PREFIX_KEY': 'leak-me-not',
        };

        final child = allowlist.build(parent);

        expect(child['ANTHROPIC_API_KEY'], 'sk-ant-xxx');
        expect(child['OPENAI_API_KEY'], 'sk-oai-yyy');
        expect(child['AWS_ACCESS_KEY_ID'], 'AKIA');
        expect(child['AWS_SECRET_ACCESS_KEY'], 'secret');
        expect(child.containsKey('RANDOM_PREFIX_KEY'), isFalse);
      },
    );

    test('drops empty-valued allowlisted vars (the gc `if v != ""` guard)', () {
      final parent = <String, String>{
        'HOME': '',
        'CLAUDE_CODE_OAUTH_TOKEN': 'present',
      };

      final child = allowlist.build(parent);

      expect(child.containsKey('HOME'), isFalse);
      expect(child['CLAUDE_CODE_OAUTH_TOKEN'], 'present');
    });

    test(
      'forwards the local swift-infer provider vars and the e2e device id',
      () {
        final parent = <String, String>{
          'PATH': '/usr/bin:/bin',
          'SWIFT_INFER_ENDPOINT': 'http://127.0.0.1:8080',
          'SWIFT_INFER_AGENT_TOKEN': 'fake-agent-token',
          'SWIFT_INFER_MODEL': 'qwen3.6-35b-a3b',
          'LEONARD_E2E_DEVICE': '00008110-0000000000000000',
          // Same host, NOT on the list: a device id under a different name and
          // an unrelated LEONARD_ var stay behind the boundary.
          'LEONARD_E2E_RUN_DIR': '/tmp/run',
          'GC_DOLT_PASSWORD': 'super-secret-dolt-pw',
        };

        final child = allowlist.build(parent);

        expect(child['SWIFT_INFER_ENDPOINT'], 'http://127.0.0.1:8080');
        expect(child['SWIFT_INFER_AGENT_TOKEN'], 'fake-agent-token');
        expect(child['SWIFT_INFER_MODEL'], 'qwen3.6-35b-a3b');
        expect(child['LEONARD_E2E_DEVICE'], '00008110-0000000000000000');
        expect(child.containsKey('LEONARD_E2E_RUN_DIR'), isFalse);
        expect(child.containsKey('GC_DOLT_PASSWORD'), isFalse);
      },
    );

    test('isProviderCredentialEnv recognises prefix and exact keys', () {
      expect(allowlist.isProviderCredentialEnv('ANTHROPIC_BASE_URL'), isTrue);
      expect(allowlist.isProviderCredentialEnv('AWS_REGION'), isTrue);
      expect(
        allowlist.isProviderCredentialEnv('SWIFT_INFER_AGENT_TOKEN'),
        isTrue,
      );
      expect(allowlist.isProviderCredentialEnv('LEONARD_E2E_DEVICE'), isFalse);
      expect(allowlist.isProviderCredentialEnv('GC_DOLT_PASSWORD'), isFalse);
      expect(allowlist.isProviderCredentialEnv('HOME'), isFalse);
    });
  });
}
