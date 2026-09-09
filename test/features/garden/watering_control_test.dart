import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/app/theme/themedata.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/widgets/watering_control.dart';

Widget harness({
  required VoidCallback onWatered,
  GardenTicker ticker = GardenTicker.still,
  bool accessibleNavigation = false,
  bool wateredToday = false,
}) => MediaQuery(
  data: MediaQueryData(accessibleNavigation: accessibleNavigation),
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: WateringControl(
          semanticLabel: 'Water Morning walk',
          onWatered: onWatered,
          ticker: ticker,
          wateredToday: wateredToday,
        ),
      ),
    ),
  ),
);

void main() {
  group('WateringControl', () {
    testWidgets('a tap does not water', (tester) async {
      // The reason the gesture is a hold at all: the garden is a screen people
      // open to look at, and a tap target on it gets hit by accident.
      var waterings = 0;
      await tester.pumpWidget(harness(onWatered: () => waterings++));

      await tester.tap(find.byType(WateringControl));
      await tester.pumpAndSettle();

      expect(waterings, 0);
    });

    testWidgets('a hold released early does not water', (tester) async {
      var waterings = 0;
      await tester.pumpWidget(harness(onWatered: () => waterings++));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WateringControl)),
      );
      await tester.pump(AppMotion.waterHoldDuration ~/ 2);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(waterings, 0);
    });

    testWidgets('a full hold waters, once', (tester) async {
      var waterings = 0;
      await tester.pumpWidget(harness(onWatered: () => waterings++));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WateringControl)),
      );
      await tester.pump(AppMotion.waterHoldDuration);
      expect(waterings, 1);

      // Keeping the finger down does not water again.
      await tester.pump(AppMotion.waterHoldDuration * 3);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(waterings, 1);
    });

    testWidgets('scrolling past a plant with a finger down does not water', (
      tester,
    ) async {
      // A slow scroll rests a finger on a plant for longer than the hold. The
      // recognizer is in the arena precisely so the scrollable takes the
      // pointer and the hold is cancelled.
      var waterings = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 300),
                WateringControl(
                  semanticLabel: 'Morning walk',
                  onWatered: () => waterings++,
                  ticker: GardenTicker.still,
                ),
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WateringControl)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(AppMotion.waterHoldDuration * 2);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(waterings, 0);
    });

    testWidgets('the hold is not shortened when motion is turned off', (
      tester,
    ) async {
      // AppMotion.waterHoldDuration is the accident guard, not decoration, so
      // GardenTicker must not be able to scale it.
      var waterings = 0;
      await tester.pumpWidget(
        harness(onWatered: () => waterings++, ticker: GardenTicker.still),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WateringControl)),
      );
      await tester.pump(
        AppMotion.waterHoldDuration - const Duration(milliseconds: 50),
      );
      expect(waterings, 0);

      await tester.pump(const Duration(milliseconds: 50));
      expect(waterings, 1);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('with motion off the label carries the feedback instead', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(onWatered: () {}, ticker: GardenTicker.still),
      );

      expect(find.text(WateringControl.holdLabel), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WateringControl)),
      );
      await tester.pump(AppMotion.waterHoldDuration ~/ 2);

      expect(find.text(WateringControl.holdingLabel), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('assistive navigation gets a button, not an instruction to '
        'hold', (tester) async {
      var waterings = 0;
      await tester.pumpWidget(
        harness(onWatered: () => waterings++, accessibleNavigation: true),
      );

      expect(find.text(WateringControl.accessibleLabel), findsOneWidget);
      expect(find.text(WateringControl.holdLabel), findsNothing);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(waterings, 1);
    });

    testWidgets('the semantics action waters without holding anything', (
      tester,
    ) async {
      var waterings = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(onWatered: () => waterings++));

      // An action, not a description — the plant's state is announced by the
      // card that holds it, and repeating it here made a screen reader read
      // the whole thing twice.
      final node = tester.getSemantics(find.byType(WateringControl));
      expect(node.label, 'Water Morning walk');

      tester.semantics.tap(find.semantics.byLabel(node.label));
      await tester.pumpAndSettle();

      expect(waterings, 1);
      handle.dispose();
    });

    testWidgets('a plant watered today invites another watering', (
      tester,
    ) async {
      // Watering twice in a day is allowed; the engine counts both.
      await tester.pumpWidget(harness(onWatered: () {}, wateredToday: true));

      expect(find.text(WateringControl.holdAgainLabel), findsOneWidget);
    });
  });
}
