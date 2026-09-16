import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/pages/notification_invitation_page.dart';
import 'package:taproot/features/notifications/providers/notification_onboarding_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/main.dart';

import '../../utils/fake_notification_gateway.dart';
import '../../utils/fake_repositories.dart';
import '../../utils/store_fixtures.dart';

/// The one moment the app asks for notification permission.
///
/// Two rules are load-bearing and both are asserted rather than described: the
/// question is put **once**, whatever the answer, and a refusal is a designed
/// mode rather than an error — no warning, no retry, and the app carries on.
void main() {
  late FakeHabitService habits;
  late FakeNotificationInvitationStore invitations;
  late FakeNotificationGateway gateway;
  late ReflectionPromptComposer composer;

  setUp(() async {
    habits = FakeHabitService();
    await habits.saveHabit(testHabit());
    invitations = FakeNotificationInvitationStore();
    gateway = FakeNotificationGateway(access: NotificationAccess.denied);
    composer = const NoReflectionPrompt();
  });

  Future<void> pumpInvitation(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseOpenerProvider.overrideWithValue(
            openTestDatabaseInWidgetTest,
          ),
          habitServiceProvider.overrideWithValue(habits),
          nudgeServiceProvider.overrideWithValue(
            FakeNudgeService(habits: habits),
          ),
          notificationGatewayProvider.overrideWithValue(gateway),
          notificationInvitationStoreProvider.overrideWithValue(invitations),
          reflectionPromptComposerProvider.overrideWithValue(composer),
        ],
        child: const TaprootApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The notification the *scheduler* would compose for this habit, built from
  /// the running app's own providers.
  ///
  /// The point of going through the container rather than rebuilding the
  /// arguments here is that a second hand-assembled copy is a second thing to
  /// keep in step — which is the defect this whole group is about.
  Future<EveningCheckIn> composedFor(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TaprootApp)),
    );
    final composed = await container.read(notificationPreviewProvider.future);
    return composed!;
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('the preview is the notification, not a description of one', () {
    testWidgets('it is what composeEveningCheckIn returns', (tester) async {
      // Asserted against the composer's own output rather than against copied
      // literals. Literals duplicate the copy instead of binding to it: they
      // keep passing when the composer's wording changes, and — the failure
      // that actually happened — when the preview and the scheduler stop
      // calling it the same way.
      await pumpInvitation(tester);

      final expected = await composedFor(tester);

      expect(find.text(expected.title), findsOneWidget);
      expect(find.text(expected.body), findsOneWidget);
      expect(find.text(expected.confirmLabel), findsOneWidget);
      expect(find.text(expected.declineLabel), findsOneWidget);
    });

    testWidgets('a reflection question shows up in it when one is composed', (
      tester,
    ) async {
      // **The seam, driven with a non-default value.** While the stand-in
      // composer is installed the prompt is always null, and null is
      // indistinguishable from an omitted argument at every observation point
      // — so every assertion built on the default passes whether or not the
      // preview passes `reflectionPrompt` at all. Overriding the provider is
      // what gives the assertion power, and it is the state #11 puts the app
      // in.
      composer = const _AlwaysAsks('How did today go?');
      await pumpInvitation(tester);

      expect(
        find.textContaining('How did today go?'),
        findsOneWidget,
        reason: 'the preview dropped the reflection prompt the scheduler sends',
      );
      expect(find.text((await composedFor(tester)).body), findsOneWidget);
    });

    testWidgets('it uses the habit\'s real next occasion', (tester) async {
      // Not `ExpectedOccasion(index: 0, …)`. `composeEveningCheckIn` ignores
      // the index today, which is exactly why a fabricated one survives —
      // until something reads it. The composer is handed the occasion and the
      // delivery instant, so both have to be the real ones.
      final recorder = _RecordsWhatItWasAsked();
      composer = recorder;
      await pumpInvitation(tester);

      final expected = nextNudgeableOccasion(
        habit: (await habits.allHabits()).last,
        now: DateTime.now(),
      );
      expect(recorder.occasion, expected);
      expect(recorder.deliverAt, nudgeDeliveryTime(expected!));
    });

    testWidgets('the copy does not promise the question every evening', (
      tester,
    ) async {
      // The one line on this screen that is written rather than composed, and
      // so the one that can over-promise. The reflection question is scored
      // per occasion against a budget and a cooldown; most evenings nothing
      // clears it.
      await pumpInvitation(tester);

      expect(find.textContaining('now and then'), findsOneWidget);
      expect(find.text(NotificationInvitationPage.note), findsOneWidget);
      expect(
        NotificationInvitationPage.note,
        isNot(contains('One message in the evening: how today went')),
      );
    });
  });

  testWidgets('accepting asks the platform and lands in the garden', (
    tester,
  ) async {
    gateway.grant(const NotificationAccess(mode: NotificationMode.granted));
    await pumpInvitation(tester);

    await tap(tester, NotificationInvitationPage.acceptLabel);

    expect(invitations.offered, isTrue);
    expect(find.byType(GardenPage), findsOneWidget);
  });

  testWidgets('declining is a plain choice, not a dead end', (tester) async {
    await pumpInvitation(tester);

    await tap(tester, NotificationInvitationPage.declineLabel);

    expect(
      find.text(NotificationInvitationPage.withoutNotificationsHeadline),
      findsOneWidget,
    );

    await tap(tester, NotificationInvitationPage.continueLabel);
    expect(find.byType(GardenPage), findsOneWidget);
  });

  testWidgets('a refusal from the platform is a mode, not an error', (
    tester,
  ) async {
    // The user said yes and the system said no. Denial is an app mode
    // (guide §2), so what follows says what still works — no warning colour,
    // no retry, no trip to system settings.
    await pumpInvitation(tester);

    await tap(tester, NotificationInvitationPage.acceptLabel);

    expect(
      find.text(NotificationInvitationPage.withoutNotificationsHeadline),
      findsOneWidget,
    );
    expect(find.textContaining('still grows'), findsOneWidget);
    expect(find.textContaining('went wrong'), findsNothing);
    expect(find.byIcon(Icons.error), findsNothing);
    expect(find.byIcon(Icons.warning), findsNothing);
  });

  group('a failure on the way out is not a dead end', () {
    // Both awaits in `_accept` can throw, and `asking` has already disabled
    // both buttons by the time either can. The page is a redirect destination
    // — no AppBar, nothing underneath to pop to — so an escaping exception
    // leaves killing the app as the only way off the screen.

    testWidgets(
      'a platform that cannot be asked lands on the designed screen',
      (tester) async {
        gateway.grant(const NotificationAccess(mode: NotificationMode.granted));
        gateway.failRequestAccess = true;
        await pumpInvitation(tester);

        await tap(tester, NotificationInvitationPage.acceptLabel);

        expect(
          find.text(NotificationInvitationPage.withoutNotificationsHeadline),
          findsOneWidget,
          reason: 'the request threw and the screen never left `asking`',
        );

        // And it is a screen you can leave from, which is the whole finding.
        await tap(tester, NotificationInvitationPage.continueLabel);
        expect(find.byType(GardenPage), findsOneWidget);
      },
    );

    testWidgets('a record that will not write still asks the platform', (
      tester,
    ) async {
      // `markOffered` is a bare `setBool`. Its failure is a bookkeeping loss —
      // the question gets put once more on the next launch — and deliberately
      // not the same failure as the platform refusing: saying "no
      // notifications, then" here would contradict the permission the OS just
      // granted.
      gateway.grant(const NotificationAccess(mode: NotificationMode.granted));
      invitations.failMarkOffered = true;
      await pumpInvitation(tester);

      await tap(tester, NotificationInvitationPage.acceptLabel);

      expect(find.byType(GardenPage), findsOneWidget);
    });

    testWidgets('a record that will not write leaves declining answerable', (
      tester,
    ) async {
      invitations.failMarkOffered = true;
      await pumpInvitation(tester);

      await tap(tester, NotificationInvitationPage.declineLabel);

      expect(
        find.text(NotificationInvitationPage.withoutNotificationsHeadline),
        findsOneWidget,
      );
      await tap(tester, NotificationInvitationPage.continueLabel);
      expect(find.byType(GardenPage), findsOneWidget);
    });

    testWidgets('both failing at once still ends somewhere with a way out', (
      tester,
    ) async {
      invitations.failMarkOffered = true;
      gateway.failRequestAccess = true;
      await pumpInvitation(tester);

      await tap(tester, NotificationInvitationPage.acceptLabel);

      expect(
        find.text(NotificationInvitationPage.withoutNotificationsHeadline),
        findsOneWidget,
      );
      expect(find.textContaining('went wrong'), findsNothing);
      expect(find.byIcon(Icons.error), findsNothing);
    });
  });

  group('the question is put once', () {
    testWidgets('accepting records it', (tester) async {
      gateway.grant(const NotificationAccess(mode: NotificationMode.granted));
      await pumpInvitation(tester);

      await tap(tester, NotificationInvitationPage.acceptLabel);

      expect(invitations.markCalls, 1);
    });

    testWidgets('declining records it too', (tester) async {
      await pumpInvitation(tester);

      await tap(tester, NotificationInvitationPage.declineLabel);

      expect(invitations.markCalls, 1);
    });

    testWidgets('and a refusal by the system still counts as asked', (
      tester,
    ) async {
      // Recorded *before* the platform dialog resolves, so dismissing the
      // system prompt without answering does not bring the screen back on the
      // next launch.
      await pumpInvitation(tester);

      await tap(tester, NotificationInvitationPage.acceptLabel);

      expect(invitations.offered, isTrue);
    });

    testWidgets('so the next launch goes straight to the garden', (
      tester,
    ) async {
      await pumpInvitation(tester);
      await tap(tester, NotificationInvitationPage.declineLabel);
      await tap(tester, NotificationInvitationPage.continueLabel);

      // A fresh app over the same store: the record outlives the screen.
      await pumpInvitation(tester);

      expect(find.byType(GardenPage), findsOneWidget);
      expect(find.byType(NotificationInvitationPage), findsNothing);
    });
  });

  testWidgets('a habit with no designed cue still gets an offer', (
    tester,
  ) async {
    // A tracked habit (Journey A) has no cue to rehearse, and the screen must
    // not invent one — it makes the offer in the habit's own terms instead.
    habits = FakeHabitService();
    await habits.saveHabit(
      testHabit(journey: HabitJourney.track, designedCue: null),
    );

    await pumpInvitation(tester);

    expect(find.text(NotificationInvitationPage.question), findsOneWidget);
    expect(find.textContaining('Morning run'), findsWidgets);
  });
}

/// A composer that always has something to ask — the state #11 puts the app in.
class _AlwaysAsks implements ReflectionPromptComposer {
  const _AlwaysAsks(this.question);

  final String question;

  @override
  Future<String?> promptFor({
    required Habit habit,
    required ExpectedOccasion occasion,
    required DateTime deliverAt,
  }) async => question;
}

/// Records what the preview handed the composer.
class _RecordsWhatItWasAsked implements ReflectionPromptComposer {
  ExpectedOccasion? occasion;
  DateTime? deliverAt;

  @override
  Future<String?> promptFor({
    required Habit habit,
    required ExpectedOccasion occasion,
    required DateTime deliverAt,
  }) async {
    this.occasion = occasion;
    this.deliverAt = deliverAt;
    return null;
  }
}
