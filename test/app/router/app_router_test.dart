import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/pages/habit_creation_page.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/pages/notification_invitation_page.dart';
import 'package:taproot/features/notifications/providers/notification_onboarding_providers.dart';
import 'package:taproot/main.dart';

import '../../utils/fake_repositories.dart';

import '../../utils/store_fixtures.dart';

Widget appWith({
  Future<AppGate> Function()? gateResolver,
  HabitRepository? habits,
  // Defaults to *already offered*, so that every test about some other part of
  // the router is not also a test about the notification invitation. The two
  // tests that are about it say so.
  bool notificationsOffered = true,
}) => ProviderScope(
  overrides: [
    databaseOpenerProvider.overrideWithValue(openTestDatabaseInWidgetTest),
    if (habits != null) habitServiceProvider.overrideWithValue(habits),
    notificationInvitationStoreProvider.overrideWithValue(
      FakeNotificationInvitationStore(offered: notificationsOffered),
    ),
    if (gateResolver != null)
      appGateResolverProvider.overrideWithValue(gateResolver),
  ],
  child: const TaprootApp(),
);

/// A store with one habit already in it.
Future<FakeHabitService> plantedStore() async {
  final habits = FakeHabitService();
  await habits.saveHabit(testHabit());
  return habits;
}

void main() {
  group('the router', () {
    testWidgets('lands on the garden once something is planted', (
      tester,
    ) async {
      await tester.pumpWidget(appWith(habits: await plantedStore()));
      await tester.pumpAndSettle();

      expect(find.byType(GardenPage), findsOneWidget);
    });

    testWidgets('offers the notification invitation after the first habit', (
      tester,
    ) async {
      await tester.pumpWidget(
        appWith(habits: await plantedStore(), notificationsOffered: false),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotificationInvitationPage), findsOneWidget);
      expect(find.byType(GardenPage), findsNothing);
    });

    testWidgets('and never offers it before there is a habit', (tester) async {
      // A permission request about nothing is an interrogation. The user is
      // sent to plant something first.
      await tester.pumpWidget(appWith(notificationsOffered: false));
      await tester.pumpAndSettle();

      expect(find.byType(HabitCreationPage), findsOneWidget);
      expect(find.byType(NotificationInvitationPage), findsNothing);
    });

    testWidgets('sends a user with nothing planted in to plant one', (
      tester,
    ) async {
      // The gate is real now: an empty garden has no accumulated progress to
      // lead with, so the first habit is what the app needs before it has a
      // home screen worth showing.
      await tester.pumpWidget(appWith());
      await tester.pumpAndSettle();

      expect(find.byType(HabitCreationPage), findsOneWidget);
      expect(find.byType(GardenPage), findsNothing);
    });

    testWidgets('a failed gate resolution routes into habit creation', (
      tester,
    ) async {
      await tester.pumpWidget(
        appWith(gateResolver: () => Future<AppGate>.error(StateError('nope'))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HabitCreationPage), findsOneWidget);
      expect(find.byType(GardenPage), findsNothing);
    });

    testWidgets('an unknown path is not a dead end', (tester) async {
      await tester.pumpWidget(appWith(habits: await plantedStore()));
      await tester.pumpAndSettle();

      routerOf(tester).go('/nowhere');
      await tester.pumpAndSettle();

      expect(find.text(AppRouteErrorPage.headline), findsOneWidget);
    });
  });
}

/// The router the running app is actually using.
GoRouter routerOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(TaprootApp)),
).read(goRouterProvider);
