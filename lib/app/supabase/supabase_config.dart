import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// The credentials a flavor was launched with.
///
/// Read from the flavor's `.env` file, which `main_<flavor>.dart` loads before
/// [runMainApp]. Kept as a value object rather than read at the point of use so
/// that "is there a backend at all" is one question asked in one place — see
/// [isConfigured], which is load-bearing rather than defensive.
@immutable
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.publishableKey});

  final String url;

  /// The client-side key. Public by design — it carries no authority beyond
  /// what RLS grants the `anon` role, which on Taproot is nothing at all until
  /// a user signs in.
  ///
  /// Named for `Supabase.initialize`'s current parameter rather than for the
  /// environment variable it is read from. Supabase renamed `anonKey` to
  /// `publishableKey` while it migrates from legacy JWT keys to `sb_publishable_`
  /// ones; the two are the same argument (`effectiveKey = publishableKey ??
  /// anonKey`), so the local stack's JWT is passed here unchanged. The env var
  /// stays `SUPABASE_ANON_KEY` because that is what `.secrets/` and the local
  /// stack both call it — renaming that is the backend's call, not this one's.
  final String publishableKey;

  /// Whether this flavor has a backend to talk to.
  ///
  /// **Not every build does, and that is a designed state rather than an
  /// error.** Only `.env.dev` has real values today; stg and prod are
  /// placeholders until a remote project is provisioned. `Supabase.initialize`
  /// on an empty URL throws at launch, so the choice is between a flavor that
  /// cannot start and one that runs without sync.
  ///
  /// Running without sync is the honest answer, and it costs the user nothing
  /// they can see: SQLite is the *primary* store, not a cache. Every read is
  /// local, every write is local-then-queued, and the queue simply does not
  /// drain. What must not happen is the app pretending to back up work it is
  /// not backing up — which is why this is surfaced as `SyncStatus.unavailable`
  /// rather than a permanently idle sync.
  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Reads the two keys out of an already-loaded environment.
  ///
  /// Takes the map rather than reaching for `dotenv` so it is a pure function a
  /// test can hand any environment to, including a half-filled one.
  factory SupabaseConfig.fromEnvironment(Map<String, String> environment) =>
      SupabaseConfig(
        url: environment['SUPABASE_URL']?.trim() ?? '',
        publishableKey: environment['SUPABASE_ANON_KEY']?.trim() ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is SupabaseConfig &&
      other.url == url &&
      other.publishableKey == publishableKey;

  @override
  int get hashCode => Object.hash(url, publishableKey);

  /// Deliberately does not print the key. It is not a secret, but a key in a
  /// log line is a key in a bug report, and the habit is worth keeping.
  @override
  String toString() =>
      'SupabaseConfig(${isConfigured ? url : 'not configured'})';
}

/// The loaded `.env`, or an empty environment when there is not one.
///
/// A unit test, a widget test, and `flutter test` generally never run a flavor
/// entry point, so `dotenv` is not loaded and reading `dotenv.env` would throw
/// `NotInitializedError`. An empty map is the right answer there rather than a
/// crash: it decodes to "no backend configured", which is exactly what a test
/// process has.
///
/// A function as well as a provider because `runMainApp` needs it before there
/// is a [ProviderScope] to read from, and two spellings of "is dotenv loaded"
/// is how the bootstrap and the app end up disagreeing about it.
Map<String, String> loadedEnvironment() =>
    dotenv.isInitialized ? dotenv.env : const <String, String>{};

final environmentProvider = Provider<Map<String, String>>(
  (ref) => loadedEnvironment(),
);

final supabaseConfigProvider = Provider<SupabaseConfig>(
  (ref) => SupabaseConfig.fromEnvironment(ref.watch(environmentProvider)),
);
