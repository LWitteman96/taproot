/// Whether the app has already had the notification conversation.
///
/// **Why the app keeps its own record rather than asking the platform.**
/// Android cannot tell "never asked" from "asked and refused" after the fact —
/// `areNotificationsEnabled()` returns false for both — and iOS only
/// distinguishes them until the first prompt. So the one thing the OS cannot
/// answer is the only thing the invitation needs to know: have we already put
/// this question to this person.
///
/// That question is asked **once**. A user who said no is not asked again on
/// the next launch, or the one after; they are not asked again at all. The
/// engine measures autonomy by withholding nudges, so an app that nags for
/// permission to nudge is arguing with its own thesis — and the denied state is
/// a designed mode the rest of the app already handles, not a problem to be
/// resolved (guide §2). Turning notifications on later is a settings trip the
/// user makes when they want to, and the app notices on resume.
///
/// What it deliberately does *not* record is the **answer**. That lives with
/// the platform, which is the only place that stays true when someone changes
/// their mind in system settings; a second copy here would go stale the first
/// time they did.
///
/// **"It must not sync" is enforced in two places, not asserted here.** The
/// storage choice keeps the record out of Taproot's own sync; what it does not
/// escape is platform backup, which carries it to a new phone while the
/// permission it implies stays behind. Both halves of that are handled
/// elsewhere, and both are needed because each platform only admits one:
///
/// - **Android** excludes the store from Auto Backup and device-to-device
///   transfer (`android/app/src/main/res/xml/`), because
///   `areNotificationsEnabled()` cannot tell "never asked" from "refused" and
///   so nothing downstream could detect a restore.
/// - **iOS** cannot exclude `NSUserDefaults` from iCloud or encrypted local
///   backups at all, so the record does travel — and is caught on arrival by
///   `resolveAppGate`, using the one thing iOS *can* report that Android
///   cannot: `NotificationMode.undecided`, meaning this install has never
///   prompted.
abstract class NotificationInvitationStore {
  /// Whether the invitation has been offered before.
  ///
  /// False on any failure to read. Asking a second time is a small
  /// annoyance; never asking — which is what a failed read that reported
  /// "already asked" would cause — silently costs the user every nudge the app
  /// was built to send.
  Future<bool> hasBeenOffered();

  /// Records that the question has now been put.
  ///
  /// Called for *both* answers, and before the platform dialog resolves, so a
  /// user who dismisses the system prompt without answering is not asked again
  /// on the next launch.
  Future<void> markOffered();
}
