import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
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

  setUp(() async {
    habits = FakeHabitService();
    await habits.saveHabit(testHabit());
    invitations = FakeNotificationInvitationStore();
    gateway = FakeNotificationGateway(access: NotificationAccess.denied);
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
        ],
        child: const TaprootApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('offers the real notification, not a description of one', (
    tester,
  ) async {
    // The preview is composed by the same function that composes the
    // notification, so the screen cannot promise something the app does not
    // send. `testHabit` designs "after breakfast".
    await pumpInvitation(tester);

    expect(find.text(NotificationInvitationPage.question), findsOneWidget);
    expect(find.text('Morning run'), findsOneWidget);
    expect(find.textContaining('after breakfast'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Different day'), findsOneWidget);
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
