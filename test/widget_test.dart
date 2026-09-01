import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/utils/flavor.dart';
import 'package:taproot/main.dart';

void main() {
  testWidgets('app renders and reports the active flavor', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TaprootApp()));

    expect(find.text('Taproot'), findsOneWidget);
    expect(find.textContaining('flavor:'), findsOneWidget);
  });

  test('getFlavor defaults to dev when no flavor is set', () {
    // Tests run without --flavor, so appFlavor is null.
    expect(getFlavor(), Flavor.dev);
  });
}
