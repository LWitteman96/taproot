import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/habits/pages/habit_creation_page.dart';
import 'package:taproot/main.dart';

import '../../utils/store_fixtures.dart';

Widget appWith({Future<AppGate> Function()? gateResolver}) => ProviderScope(
  overrides: [
    databaseOpenerProvider.overrideWithValue(openTestDatabaseInWidgetTest),
    if (gateResolver != null)
      appGateResolverProvider.overrideWithValue(gateResolver),
  ],
  child: const TaprootApp(),
);

void main() {
  group('the router', () {
    testWidgets('lands on the garden', (tester) async {
      await tester.pumpWidget(appWith());
      await tester.pumpAndSettle();

      expect(find.byType(GardenPage), findsOneWidget);
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
      await tester.pumpWidget(appWith());
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
