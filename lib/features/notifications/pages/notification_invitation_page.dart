import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_radius.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
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

  /// What the notification actually is, in the app's own words.
  ///
  /// **The cue for tomorrow is every evening; the look back is not.** The
  /// reflection question is scored per occasion against a budget and a cooldown
  /// (reflection spec §2), and most evenings nothing clears the threshold — so
  /// "how today went" as a flat promise was the one line on this screen that
  /// over-promised, on the screen whose whole point is that it cannot. The
  /// preview below is composed rather than written, which is what keeps the
  /// rest of it honest; this sentence has to be kept honest by hand.
  static const String note =
      'One message in the evening: the cue for tomorrow, and now and then a '
      'question about how the day went. Nothing else, and never more than one '
      'a day.';
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
  static final Logger _log = Logger('NotificationInvitationPage');

  _InvitationStage _stage = _InvitationStage.offered;

  /// The question is only ever put once, so it is recorded as asked whichever
  /// way it is answered — and *before* the platform dialog resolves, so that
  /// dismissing the system prompt without answering does not bring the screen
  /// back on the next launch.
  ///
  /// **Neither await may escape.** `asking` disables both buttons, and this
  /// page is a redirect destination: no `AppBar`, nothing pushed underneath to
  /// pop back to. An exception thrown after the stage flips leaves two greyed
  /// buttons and killing the app as the only way out. So both failures end
  /// somewhere the user can leave from, and they end in *different* places,
  /// because they are not the same failure.
  Future<void> _accept() async {
    // Taken before the first await: reaching for the context again on the far
    // side of one is the lint's whole point, and here it would be reaching for
    // it across a system dialog the user may sit on for a while.
    final container = ProviderScope.containerOf(context, listen: false);

    setState(() => _stage = _InvitationStage.asking);
    await _markOffered();

    // A platform that cannot be asked is a platform that cannot post, so this
    // failure lands on the designed screen for "no notifications" — the same
    // place a refusal lands, and true for the same reason.
    final NotificationAccess access;
    try {
      access = await requestNotificationAccess(container);
    } catch (error, stackTrace) {
      _log.warning(
        'the platform could not be asked for notification access',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() => _stage = _InvitationStage.withoutNotifications);
      return;
    }
    if (!mounted) return;

    if (access.canPost) {
      _leave();
      return;
    }
    setState(() => _stage = _InvitationStage.withoutNotifications);
  }

  Future<void> _decline() async {
    setState(() => _stage = _InvitationStage.asking);
    await _markOffered();
    if (!mounted) return;
    setState(() => _stage = _InvitationStage.withoutNotifications);
  }

  /// Records the question as put, and never throws.
  ///
  /// Deliberately *not* folded into the accept path's catch. A record that
  /// failed to write is a bookkeeping loss — the user is asked once more on
  /// the next launch, which [NotificationInvitationStore] already argues is
  /// the cheaper of the two wrong answers. Treating it as "no notifications,
  /// then" would be the screen contradicting the platform: it would say the
  /// app will not nudge while the OS has just granted permission for exactly
  /// that. So this failure is logged and the answer the user actually gave is
  /// carried through.
  Future<void> _markOffered() async {
    try {
      await ref.read(notificationInvitationStoreProvider).markOffered();
    } catch (error, stackTrace) {
      _log.warning(
        'the invitation record could not be written; the question will be '
        'put again on the next launch',
        error,
        stackTrace,
      );
    }
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
    final preview = ref.watch(notificationPreviewProvider).value;

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
                    : _offer(theme, preview),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _offer(ThemeData theme, EveningCheckIn? preview) => <Widget>[
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
    if (preview != null) _NotificationPreview(checkIn: preview),
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
/// It is handed a composed [EveningCheckIn] rather than composing one, because
/// composing it needs the reflection composer and the habit's real occasion
/// calendar — both asynchronous, both the scheduler's own inputs. See
/// [notificationPreviewProvider], which is where that happens and where the
/// reasoning lives.
class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.checkIn});

  final EveningCheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
