import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/core/utils/flavor.dart';
import 'package:taproot/main.dart';

import 'utils/store_fixtures.dart';

void main() {
  testWidgets('app renders and reports the active flavor', (tester) async {
    // The app now waits on the database before it shows anything, so the test
    // hands it an in-memory one rather than the on-device file.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseOpenerProvider.overrideWithValue(
            openTestDatabaseInWidgetTest,
          ),
        ],
        child: const TaprootApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Taproot'), findsOneWidget);
    expect(find.textContaining('flavor:'), findsOneWidget);
  });

  test('getFlavor defaults to dev when no flavor is set', () {
    // Tests run without --flavor, so appFlavor is null.
    expect(getFlavor(), Flavor.dev);
  });
}
