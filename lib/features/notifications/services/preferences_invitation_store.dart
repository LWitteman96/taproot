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

  /// Whether the question was put during *this* run of the app.
  ///
  /// Set by [markOffered] whether or not the write lands, because the two are
  /// different facts: the question really was put, and the record of it really
  /// did fail to persist. Without this the router's gate — which reads only
  /// the persisted answer — sends the user straight back to the invitation the
  /// moment they leave it, and keeps doing it, because the screen they just
  /// answered is the one thing the gate still thinks they have not seen.
  ///
  /// It deliberately does not outlive the process. What survives a relaunch is
  /// the file, and if the file never got written then asking once more on the
  /// next launch is the cheaper of the two wrong answers — the same trade
  /// [hasBeenOffered] makes on a failed read.
  bool _offeredThisRun = false;

  @override
  Future<bool> hasBeenOffered() async {
    if (_offeredThisRun) return true;
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

  /// Records that the question has been put, and **rethrows** if the write
  /// fails.
  ///
  /// The in-memory half above is taken first, so a caller that catches this —
  /// the invitation screen does — leaves behind a store that answers honestly
  /// for the rest of the run. The throw still escapes, because a silent
  /// swallow here is how "asked once" quietly becomes "asked every launch"
  /// with nothing in the logs.
  @override
  Future<void> markOffered() async {
    _offeredThisRun = true;
    await _preferences.setBool(key, true);
  }
}
