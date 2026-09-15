import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/supabase/supabase_config.dart';

void main() {
  group('SupabaseConfig', () {
    test('reads the two keys out of an environment', () {
      final config = SupabaseConfig.fromEnvironment(const <String, String>{
        'SUPABASE_URL': 'http://127.0.0.1:54331',
        'SUPABASE_ANON_KEY': 'a-json-web-token',
        'SENTRY_DSN': 'ignored',
      });

      expect(config.url, 'http://127.0.0.1:54331');
      expect(config.publishableKey, 'a-json-web-token');
      expect(config.isConfigured, isTrue);
    });

    test('an empty environment is not configured, and is not an error', () {
      // What every test process has, and what stg and prod have until a remote
      // project is provisioned.
      final config = SupabaseConfig.fromEnvironment(const <String, String>{});

      expect(config.isConfigured, isFalse);
      expect(config.url, isEmpty);
    });

    test('half an environment is not configured either', () {
      // The placeholder shape: a URL filled in ahead of the key, or the other
      // way round. Either one alone would still throw at initialize.
      expect(
        SupabaseConfig.fromEnvironment(const <String, String>{
          'SUPABASE_URL': 'https://example.supabase.co',
        }).isConfigured,
        isFalse,
      );
      expect(
        SupabaseConfig.fromEnvironment(const <String, String>{
          'SUPABASE_ANON_KEY': 'a-json-web-token',
        }).isConfigured,
        isFalse,
      );
    });

    test('a whitespace-only value is not a value', () {
      // `.env` files collect these — a key deleted back to its blank line, or
      // a trailing space after an `=`. Untrimmed, both read as configured and
      // fail at initialize instead of here.
      final config = SupabaseConfig.fromEnvironment(const <String, String>{
        'SUPABASE_URL': '  ',
        'SUPABASE_ANON_KEY': '\t',
      });

      expect(config.isConfigured, isFalse);
    });

    test('trims a value that is otherwise real', () {
      final config = SupabaseConfig.fromEnvironment(const <String, String>{
        'SUPABASE_URL': ' http://127.0.0.1:54331 ',
        'SUPABASE_ANON_KEY': ' a-json-web-token ',
      });

      expect(config.url, 'http://127.0.0.1:54331');
      expect(config.publishableKey, 'a-json-web-token');
    });

    test('does not print the key', () {
      // Not a secret, but a key in a log line is a key in a bug report.
      final config = SupabaseConfig.fromEnvironment(const <String, String>{
        'SUPABASE_URL': 'http://127.0.0.1:54331',
        'SUPABASE_ANON_KEY': 'a-json-web-token',
      });

      expect(config.toString(), isNot(contains('a-json-web-token')));
      expect(
        SupabaseConfig.fromEnvironment(const <String, String>{}).toString(),
        contains('not configured'),
      );
    });
  });
}
