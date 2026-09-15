import 'package:meta/meta.dart';

/// Whether the app may post notifications at all.
///
/// **Denial is an app mode, not an error** (guide §2, CLAUDE.md). The engine
/// measures autonomy by *withholding* nudges, which presupposes nudges were
/// granted in the first place; a user who never granted them is not a failed
/// send to retry, he is a user the app has to work differently for. So this is
/// a state the rest of the app reads and renders, never an exception.
enum NotificationMode {
  /// Never asked. The permission prompt is a designed moment in onboarding,
  /// not something to fire on first launch.
  undecided,

  granted,

  /// Asked and refused, or revoked in system settings afterwards. Occasions
  /// are still recorded — the habit still has expected days, and the user
  /// still either does it or does not.
  denied;

  bool get canPost => this == NotificationMode.granted;
}

/// Whether Android will honour an exact alarm (Android 12+ `SCHEDULE_EXACT_ALARM`).
///
/// **The decision the guide (§14) asks to make early: inexact is the
/// fallback, and it is not a degraded mode worth telling the user about.** An
/// evening check-in is a ritual slot, not an alarm; the OS may slide it by
/// minutes to batch wakeups, and 20:07 does the same job as 20:00. Asking a
/// user to grant a permission named "alarms & reminders" to buy seven minutes
/// of precision spends trust the permission prompt in onboarding needs.
enum ExactAlarmCapability {
  /// Not Android, or below 12 — exactness was never gated.
  notApplicable,

  granted,

  /// Denied or never requested. Scheduling silently uses the inexact mode.
  unavailable;

  bool get allowsExact => this != ExactAlarmCapability.unavailable;
}

/// The notification capabilities the app currently has.
@immutable
class NotificationAccess {
  const NotificationAccess({
    required this.mode,
    this.exactAlarms = ExactAlarmCapability.notApplicable,
  });

  static const NotificationAccess denied = NotificationAccess(
    mode: NotificationMode.denied,
  );

  final NotificationMode mode;
  final ExactAlarmCapability exactAlarms;

  bool get canPost => mode.canPost;

  @override
  bool operator ==(Object other) =>
      other is NotificationAccess &&
      other.mode == mode &&
      other.exactAlarms == exactAlarms;

  @override
  int get hashCode => Object.hash(mode, exactAlarms);

  @override
  String toString() => 'NotificationAccess($mode, exact: ${exactAlarms.name})';
}
