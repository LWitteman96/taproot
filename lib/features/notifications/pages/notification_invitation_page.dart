import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_radius.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';
import 'package:taproot/features/notifications/providers/notification_onboarding_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';

/// Where the invitation has got to.
enum _InvitationStage {
  /// The offer is on screen, unanswered.
  offered,

  /// The system dialog is up, or the answer is being recorded.
  asking,

  /// Asked, and the answer was no. Not an error state — a designed one.
  withoutNotifications,
}

/// Asks, once, whether the app may send the evening check-in.
///
/// **The beat is deliberate: straight after the first habit is planted.** The
/// user has just finished writing a cue, and the thing being asked for is
/// permission to rehearse that exact cue back to them tomorrow evening. Asked
/// on first launch instead, it is a system dialog about an app you have not
/// used yet, and the only honest answer is no.
///
/// The voice follows design-spec §6: an invitation, never an interrogation.
/// The screen shows the real notification rather than describing one — the
/// preview is composed by the same function that composes the notification
/// itself, so it cannot promise something different from what arrives — and
/// declining is a plain, equal choice with no consequence attached to it.
class NotificationInvitationPage extends ConsumerStatefulWidget {
  const NotificationInvitationPage({super.key});

  static const String question = 'Want a nudge the evening before?';
  static const String note =
      'One message in the evening: how today went, and the cue for tomorrow. '
      'Nothing else, and never more than one a day.';
  static const String acceptLabel = 'Yes, remind me';
  static const String declineLabel = 'Not now';
  static const String continueLabel = 'To the garden';

  /// What is said when the answer — theirs or the system's — is no.
  ///
  /// Denial is an app mode, not an error (guide §2). No warning colour, no
  /// retry, no route back into system settings: the app says what still works,
  /// and gets out of the way.
  static const String withoutNotificationsHeadline = 'No notifications, then';
  static const String withoutNotificationsNote =
      'Your garden still grows, and we still notice what you do. If you change '
      'your mind, Taproot is in your phone settings.';

  @override
  ConsumerState<NotificationInvitationPage> createState() =>
      _NotificationInvitationPageState();
}

class _NotificationInvitationPageState
    extends ConsumerState<NotificationInvitationPage> {
  _InvitationStage _stage = _InvitationStage.offered;

  /// The question is only ever put once, so it is recorded as asked whichever
  /// way it is answered — and *before* the platform dialog resolves, so that
  /// dismissing the system prompt without answering does not bring the screen
  /// back on the next launch.
  Future<void> _accept() async {
    // Taken before the first await: reaching for the context again on the far
    // side of one is the lint's whole point, and here it would be reaching for
    // it across a system dialog the user may sit on for a while.
    final container = ProviderScope.containerOf(context, listen: false);

    setState(() => _stage = _InvitationStage.asking);
    await ref.read(notificationInvitationStoreProvider).markOffered();

    final access = await requestNotificationAccess(container);
    if (!mounted) return;

    if (access.canPost) {
      _leave();
      return;
    }
    setState(() => _stage = _InvitationStage.withoutNotifications);
  }

  Future<void> _decline() async {
    setState(() => _stage = _InvitationStage.asking);
    await ref.read(notificationInvitationStoreProvider).markOffered();
    if (!mounted) return;
    setState(() => _stage = _InvitationStage.withoutNotifications);
  }

  /// Hands the user back to the router.
  ///
  /// The gate is invalidated rather than navigated past: it is the thing that
  /// sent the user here, and it has just been answered on information that is
  /// now out of date. Popping without that would bounce them straight back.
  void _leave() {
    ref.invalidate(appGateProvider);
    context.go(AppRoutes.garden);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final habit = ref.watch(newestHabitProvider).value;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDimensions.maximumContentWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
                vertical: AppSpacing.pageVertical,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: _stage == _InvitationStage.withoutNotifications
                    ? _closing(theme)
                    : _offer(theme, habit),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _offer(ThemeData theme, Habit? habit) => <Widget>[
    Text(
      NotificationInvitationPage.question,
      style: theme.textTheme.headlineSmall,
      semanticsLabel: NotificationInvitationPage.question,
    ),
    const SizedBox(height: AppSpacing.small),
    Text(
      NotificationInvitationPage.note,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: AppSpacing.large),
    if (habit != null) _NotificationPreview(habit: habit),
    const SizedBox(height: AppSpacing.large),
    FilledButton(
      onPressed: _stage == _InvitationStage.asking ? null : _accept,
      child: const Text(NotificationInvitationPage.acceptLabel),
    ),
    const SizedBox(height: AppSpacing.small),
    // A plain button, the same size and the same distance away as the other
    // one. A decline styled as the quiet option is still an interrogation.
    TextButton(
      onPressed: _stage == _InvitationStage.asking ? null : _decline,
      child: const Text(NotificationInvitationPage.declineLabel),
    ),
  ];

  List<Widget> _closing(ThemeData theme) => <Widget>[
    Text(
      NotificationInvitationPage.withoutNotificationsHeadline,
      style: theme.textTheme.headlineSmall,
      semanticsLabel: NotificationInvitationPage.withoutNotificationsHeadline,
    ),
    const SizedBox(height: AppSpacing.small),
    Text(
      NotificationInvitationPage.withoutNotificationsNote,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: AppSpacing.large),
    FilledButton(
      onPressed: _leave,
      child: const Text(NotificationInvitationPage.continueLabel),
    ),
  ];
}

/// The actual notification, shown as it will arrive.
///
/// Composed by `composeEveningCheckIn` — the same function the scheduler uses —
/// rather than written out here, so the screen cannot drift into promising
/// something the app does not send.
class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkIn = composeEveningCheckIn(
      habit: habit,
      occasion: ExpectedOccasion(
        index: 0,
        date: LocalDate.from(DateTime.now()).addDays(1),
      ),
    );

    return Semantics(
      label: 'Example notification. ${checkIn.title}. ${checkIn.body}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.medium),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              checkIn.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.extraSmall),
            Text(checkIn.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.medium),
            Row(
              children: [
                Text(
                  checkIn.confirmLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.large),
                Text(
                  checkIn.declineLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
