import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taproot/features/notifications/domain/notification_invitation.dart';

/// The invitation record, in `SharedPreferences`.
///
/// Not SQLite, and not for want of a database: this is one device-local
/// boolean about a conversation the app had with the person holding *this*
/// phone. It must not sync. Permission is granted per install — a new phone
/// has never been asked, whatever the old one recorded — so a row that rode
/// along with the habits would arrive on device two claiming a question had
/// been answered there when it had not, and that user would never be offered
/// notifications at all.
class PreferencesInvitationStore implements NotificationInvitationStore {
  PreferencesInvitationStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static final Logger _log = Logger('PreferencesInvitationStore');

  /// Namespaced, because this file is shared with every other preference the
  /// app will ever keep.
  static const String key = 'notifications.invitationOffered';

  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> hasBeenOffered() async {
    try {
      return await _preferences.getBool(key) ?? false;
    } catch (error, stackTrace) {
      // Deliberately answered rather than rethrown, and answered *false*. This
      // is read while resolving the router's gate, so throwing would take a
      // launch down over a preference; and of the two wrong answers, asking a
      // second time costs one screen, while wrongly reporting "already asked"
      // costs the user every nudge the app exists to send.
      _log.warning(
        'the invitation record could not be read',
        error,
        stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> markOffered() => _preferences.setBool(key, true);
}
