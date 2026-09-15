import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';

void main() {
  group('GardenTicker', () {
    test('lively runs everything at nominal speed', () {
      expect(GardenTicker.lively.ambientEnabled, isTrue);
      expect(GardenTicker.lively.isStill, isFalse);
      expect(
        GardenTicker.lively.durationFor(AppMotion.stateChangeDuration),
        AppMotion.stateChangeDuration,
      );
    });

    test('still resolves transient motion instantly', () {
      expect(GardenTicker.still.isStill, isTrue);
      expect(
        GardenTicker.still.durationFor(AppMotion.stateChangeDuration),
        Duration.zero,
      );
    });

    test('calm stops the endless loops without freezing caused motion', () {
      // The battery shape: the garden stops idling, but a watering still pours.
      expect(GardenTicker.calm.ambientEnabled, isFalse);
      expect(GardenTicker.calm.isStill, isFalse);
      expect(
        GardenTicker.calm.durationFor(AppMotion.stateChangeDuration),
        AppMotion.stateChangeDuration,
      );
    });

    test('a scale stretches transient durations', () {
      const half = GardenTicker(ambientEnabled: true, motionScale: 0.5);
      expect(
        half.durationFor(const Duration(milliseconds: 400)),
        const Duration(milliseconds: 200),
      );
    });

    test('equality is by value, so a rebuild does not restart animations', () {
      expect(
        const GardenTicker(ambientEnabled: true, motionScale: 1),
        GardenTicker.lively,
      );
    });
  });
}
