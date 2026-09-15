import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// The Supabase client, behind a provider whose only job is to be overridable.
///
/// Three lines on purpose (infrastructure guide §6). `Supabase.instance` is a
/// singleton initialised in `runMainApp`, and a test that wants a different
/// client — `mock_supabase_http_client`, or a real one pointed at a local
/// stack — overrides this rather than reaching for the singleton.
///
/// Reading it before `Supabase.initialize` has run throws, which is correct and
/// deliberate: on a flavor with no credentials nothing should be reaching for a
/// client at all. `SupabaseConfig.isConfigured` is the question to ask first,
/// and `SyncService` asks it before it ever gets here.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
