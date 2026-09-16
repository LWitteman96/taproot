/// The drawn plant: when it appears, when it gets out of the way, and what a
/// stage advance does.
///
/// Unlike the rest of the garden tests these load the real Rive file, so they
/// need the native library — `dart run rive_native:setup --platform macos` — and
/// they are the only widget tests that do.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart' as rive;

import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/app/theme/garden_layout.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/domain/plant_art.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/garden/providers/plant_art_providers.dart';
import 'package:taproot/features/garden/widgets/plant_art_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  rive.File? realFile;

  setUpAll(() async {
    if (await rive.RiveNative.init()) {
      realFile = await rive.File.asset(
        fernAssetPath,
        riveFactory: rive.Factory.flutter,
      );
    }
    expect(
      realFile,
      isNotNull,
      reason: 'run `dart run rive_native:setup --platform macos`',
    );
  });

  const habitId = 'habit-1';

  /// The three things the art reads, driven directly.
  ///
  /// Overriding the selectors rather than assembling a whole [PlantState] is
  /// not a shortcut: it is the same surface the widget actually depends on, so
  /// a test cannot pass by accident on a field the widget never reads.
  Widget harness({
    required String plantType,
    required Stage stage,
    double vitality = 1,
    rive.File? file,
    GardenTicker ticker = GardenTicker.still,
  }) => ProviderScope(
    overrides: [
      habitPlantTypeProvider(habitId).overrideWithValue(plantType),
      habitStageProvider(habitId).overrideWithValue(stage),
      habitVitalityProvider(habitId).overrideWithValue(vitality),
      riveFernFileProvider.overrideWith((ref) async => file),
      gardenTickerProvider.overrideWith(() => _FixedTicker(ticker)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: PlantArtView(habitId: habitId)),
    ),
  );

  testWidgets('a fern draws itself, at world scale', (tester) async {
    await tester.pumpWidget(
      harness(plantType: 'fern', stage: Stage.mature, file: realFile),
    );
    await tester.pump();

    expect(find.byType(rive.RiveWidget), findsOneWidget);
    // Square and exactly the artboard's scaled size, so `Fit.contain` maps the
    // 1024 canvas onto it 1:1. Anything else silently rescales the plant and
    // breaks the one-world-one-scale rule.
    expect(
      tester.getSize(find.byType(PlantArtView)),
      const Size(GardenLayout.stageSize, GardenLayout.stageSize),
    );
  });

  testWidgets('a species with no art takes no space at all', (tester) async {
    // Not a spinner and not a gap: five of six species have nothing to draw,
    // and a reserved empty box on every one of them would be worse than the
    // card simply being shorter.
    await tester.pumpWidget(
      harness(plantType: 'oak', stage: Stage.mature, file: realFile),
    );
    await tester.pump();

    expect(find.byType(rive.RiveWidget), findsNothing);
    expect(tester.getSize(find.byType(PlantArtView)).height, 0);
  });

  testWidgets('a device without the native library still gets a garden', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(plantType: 'fern', stage: Stage.mature, file: null),
    );
    await tester.pump();

    expect(find.byType(rive.RiveWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stage advance cross-fades rather than cutting', (
    tester,
  ) async {
    // Motion on, so the switcher actually animates. The ticker's `still`
    // default would collapse the fade to an instant swap, which is the correct
    // reduced-motion behaviour and the wrong thing to assert here.
    await tester.pumpWidget(
      harness(
        plantType: 'fern',
        stage: Stage.young,
        file: realFile,
        ticker: GardenTicker.lively,
      ),
    );
    await tester.pump();
    expect(find.byType(rive.RiveWidget), findsOneWidget);

    await tester.pumpWidget(
      harness(
        plantType: 'fern',
        stage: Stage.mature,
        file: realFile,
        ticker: GardenTicker.lively,
      ),
    );
    await tester.pump();
    // Mid-fade: both stages on screen at once. This is the whole point of the
    // cross-fade — one artboard replacing another in a single frame is the
    // jarring cut it exists to avoid.
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(rive.RiveWidget), findsNWidgets(2));

    // And it resolves rather than leaving the old plant behind.
    //
    // Pumped by a known duration, not `pumpAndSettle`. A lively garden never
    // settles — the sway is an endless loop, which is precisely why
    // [GardenTicker.ambientEnabled] exists and why every other widget test in
    // the garden runs still. `pumpAndSettle` here times out rather than fails,
    // which is a slow and confusing way to learn that.
    await tester.pump(AppMotion.stageAdvanceDuration);
    expect(find.byType(rive.RiveWidget), findsOneWidget);
  });
}

class _FixedTicker extends GardenTickerController {
  _FixedTicker(this.value);

  final GardenTicker value;

  @override
  GardenTicker build() => value;
}
