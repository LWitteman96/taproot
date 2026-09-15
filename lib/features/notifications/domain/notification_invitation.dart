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
