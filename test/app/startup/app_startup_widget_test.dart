import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/startup/app_startup_widget.dart';
import 'package:taproot/app/theme/themedata.dart';

import '../../utils/store_fixtures.dart';

/// An opener the test drives by hand, so the loading state can be observed
/// before it resolves.
class ManualOpener {
  final List<Completer<Database>> pending = <Completer<Database>>[];

  Future<Database> call() {
    final completer = Completer<Database>();
    pending.add(completer);
    return completer.future;
  }

  Future<void> succeed() async {
    pending.last.complete(await openTestDatabaseInWidgetTest());
  }

  void fail() =>
      pending.last.completeError(StateError('the database file is unreadable'));
}

Widget harness(ManualOpener opener) => ProviderScope(
  overrides: [databaseOpenerProvider.overrideWithValue(opener.call)],
  child: MaterialApp(
    theme: AppTheme.light,
    home: const AppStartupWidget(child: Text('the garden')),
  ),
);

void main() {
  group('AppStartupWidget', () {
    testWidgets('waits while the database opens', (tester) async {
      final opener = ManualOpener();
      await tester.pumpWidget(harness(opener));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('the garden'), findsNothing);

      await opener.succeed();
      await tester.pumpAndSettle();

      expect(find.text('the garden'), findsOneWidget);
    });

    testWidgets('offers a retry when the open fails', (tester) async {
      final opener = ManualOpener();
      await tester.pumpWidget(harness(opener));

      opener.fail();
      await tester.pumpAndSettle();

      expect(find.text('the garden'), findsNothing);
      expect(find.text(AppStartupErrorScreen.retryLabel), findsOneWidget);
    });

    testWidgets('the retry re-opens the database and lets the app through', (
      tester,
    ) async {
      final opener = ManualOpener();
      await tester.pumpWidget(harness(opener));

      opener.fail();
      await tester.pumpAndSettle();
      expect(opener.pending, hasLength(1));

      await tester.tap(find.text(AppStartupErrorScreen.retryLabel));
      await tester.pump();

      expect(
        opener.pending,
        hasLength(2),
        reason: 'the retry must re-open, not re-read the cached error',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await opener.succeed();
      await tester.pumpAndSettle();

      expect(find.text('the garden'), findsOneWidget);
    });

    testWidgets('a repeated failure is still retryable', (tester) async {
      final opener = ManualOpener();
      await tester.pumpWidget(harness(opener));

      opener.fail();
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStartupErrorScreen.retryLabel));
      await tester.pump();
      opener.fail();
      await tester.pumpAndSettle();

      expect(find.text(AppStartupErrorScreen.retryLabel), findsOneWidget);
    });

    testWidgets(
      'both waiting and failing announce themselves to a screen reader',
      (tester) async {
        final handle = tester.ensureSemantics();
        final opener = ManualOpener();
        await tester.pumpWidget(harness(opener));

        expect(
          find.bySemanticsLabel(AppStartupLoadingScreen.semanticsLabel),
          findsOneWidget,
        );

        opener.fail();
        await tester.pumpAndSettle();

        expect(find.text(AppStartupErrorScreen.headline), findsOneWidget);
        handle.dispose();
      },
    );
  });
}
