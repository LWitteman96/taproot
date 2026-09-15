import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:taproot/features/notifications/services/preferences_invitation_store.dart';

/// The record of whether the question has been put.
///
/// Small, and load-bearing out of proportion to its size: it is read while the
/// router resolves its gate, and it is the only thing standing between the
/// user and being asked for notification permission on every single launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesInvitationStore store;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = PreferencesInvitationStore();
  });

  test('a phone that has never been asked says so', () async {
    expect(await store.hasBeenOffered(), isFalse);
  });

  test('and remembers once it has been', () async {
    await store.markOffered();

    expect(await store.hasBeenOffered(), isTrue);
  });

  test('marking twice is not a problem', () async {
    await store.markOffered();
    await store.markOffered();

    expect(await store.hasBeenOffered(), isTrue);
  });

  test('a fresh store sees what an earlier one wrote', () async {
    // The record has to outlive the screen that wrote it, or the invitation
    // comes back on the next launch.
    await store.markOffered();

    expect(await PreferencesInvitationStore().hasBeenOffered(), isTrue);
  });

  test('an unreadable record reads as "not yet asked"', () async {
    // Of the two wrong answers this is the survivable one. Asking a second
    // time costs one screen; wrongly reporting "already asked" costs the user
    // every nudge the app exists to send — silently, and for good.
    final broken = PreferencesInvitationStore(
      preferences: _BrokenPreferences(),
    );

    expect(await broken.hasBeenOffered(), isFalse);
  });
}

/// Preferences that cannot be read — a corrupt file, or a platform channel
/// that is not there.
class _BrokenPreferences implements SharedPreferencesAsync {
  @override
  Future<bool?> getBool(String key) async =>
      throw StateError('the preferences file is unreadable');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
