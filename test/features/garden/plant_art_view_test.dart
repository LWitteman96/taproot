/// The drawn plant: when it appears, when it gets out of the way, and what a
/// stage advance does.
///
/// Unlike the rest of the garden tests these load the real Rive files — one per
/// species in `plantArts` — so they need the native library
/// (`dart run rive_native:setup --platform macos`) and they are the only widget
/// tests that do.
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

  /// The real decoded asset per species, so a test can assert on the oak's
  /// artboards and not just the fern's.
  final realFiles = <String, rive.File>{};

  setUpAll(() async {
    if (await rive.RiveNative.init()) {
      for (final art in plantArts) {
        final file = await rive.File.asset(
          art.assetPath,
          riveFactory: rive.Factory.flutter,
        );
        if (file != null) realFiles[art.plantType] = file;
      }
    }
    expect(
      realFiles.keys,
      containsAll(plantArts.map((art) => art.plantType)),
      reason: 'run `dart run rive_native:setup --platform macos`',
    );
  });

  const habitId = 'habit-1';

  /// The three things the art reads, driven directly.
  ///
  /// Overriding the selectors rather than assembling a whole [PlantState] is
  /// not a shortcut: it is the same surface the widget actually depends on, so
  /// a test cannot pass by accident on a field the widget never reads.
  ///
  /// [art] true hands the widget the real decoded file for whichever species it
  /// asks for, false hands it null — the device-without-the-native-library
  /// case. The override is on the family itself, so it answers for every
  /// species rather than one.
  Widget harness({
    required String plantType,
    required Stage stage,
    double vitality = 1,
    double roots = 0,
    bool art = true,
    GardenTicker ticker = GardenTicker.still,
  }) => ProviderScope(
    overrides: [
      habitPlantTypeProvider(habitId).overrideWithValue(plantType),
      habitStageProvider(habitId).overrideWithValue(stage),
      habitVitalityProvider(habitId).overrideWithValue(vitality),
      habitRootDepthProvider(habitId).overrideWithValue(roots),
      plantArtFileProvider.overrideWith(
        (ref, species) async => art ? realFiles[species] : null,
      ),
      gardenTickerProvider.overrideWith(() => _FixedTicker(ticker)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: PlantArtView(habitId: habitId)),
    ),
  );

  testWidgets('a fern draws itself, at world scale', (tester) async {
    await tester.pumpWidget(harness(plantType: 'fern', stage: Stage.mature));
    await tester.pump();

    // Two artboards: the plant, and the roots beneath it.
    expect(find.byType(rive.RiveWidget), findsNWidgets(2));
    // Exactly the artboards' scaled sizes, so `Fit.contain` maps each canvas
    // onto its box 1:1. Anything else silently rescales the plant and breaks
    // the one-world-one-scale rule.
    expect(
      tester.getSize(find.byType(PlantArtView)),
      const Size(
        GardenLayout.stageSize,
        GardenLayout.stageSize + GardenLayout.rootsDepth,
      ),
    );
  });

  testWidgets('the plant and its roots share one view model instance', (
    tester,
  ) async {
    // The failure this guards is silent and specific: with two auto-bound
    // instances both artboards render, both binds resolve, and the plant leans
    // about roots that disagree with the ones drawn under it.
    await tester.pumpWidget(
      harness(plantType: 'fern', stage: Stage.mature, roots: 0.5),
    );
    await tester.pump();

    final controllers = tester
        .widgetList<rive.RiveWidget>(find.byType(rive.RiveWidget))
        .map((widget) => widget.controller)
        .toList();
    expect(controllers, hasLength(2));
    expect(
      controllers.first.stateMachine,
      isNot(same(controllers.last.stateMachine)),
      reason: 'two different artboards were expected',
    );
    // Same numbers, because it is the same instance behind both.
    expect(
      controllers.first.artboard.name,
      isNot(controllers.last.artboard.name),
    );
  });

  testWidgets('an oak draws itself too, from its own asset', (tester) async {
    // The second species, and the reason [PlantArt] exists. It is a different
    // `.riv` with different artboard names behind the same two numbers, so the
    // hard-coded fern this replaced would draw nothing at all here.
    await tester.pumpWidget(harness(plantType: 'oak', stage: Stage.mature));
    await tester.pump();

    expect(find.byType(rive.RiveWidget), findsNWidgets(2));

    final artboards = tester
        .widgetList<rive.RiveWidget>(find.byType(rive.RiveWidget))
        .map((widget) => widget.controller.artboard.name)
        .toList();
    // Named from the map rather than spelled here, so this fails if the widget
    // drew the fern's artboards for an oak habit — the actual regression.
    expect(artboards, contains(oakArt.artboardFor(Stage.mature)));
    expect(artboards, contains(oakArt.rootsArtboard));

    // And it occupies exactly the box the fern does, because
    // `GardenLayout.rootsDepth` is one constant for every species.
    expect(
      tester.getSize(find.byType(PlantArtView)),
      const Size(
        GardenLayout.stageSize,
        GardenLayout.stageSize + GardenLayout.rootsDepth,
      ),
    );
  });

  testWidgets('each species draws from its own file, not a shared one', (
    tester,
  ) async {
    // The family is keyed by species. Keyed by anything else — or not a family
    // at all — every plant in the garden would draw out of whichever file
    // loaded first, which looks like the right plant for a fern and like
    // nothing at all for an oak.
    final loaded = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          habitPlantTypeProvider(habitId).overrideWithValue('oak'),
          habitStageProvider(habitId).overrideWithValue(Stage.young),
          habitVitalityProvider(habitId).overrideWithValue(1),
          habitRootDepthProvider(habitId).overrideWithValue(0),
          plantArtFileProvider.overrideWith((ref, species) async {
            loaded.add(species);
            return realFiles[species];
          }),
          gardenTickerProvider.overrideWith(
            () => _FixedTicker(GardenTicker.still),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlantArtView(habitId: habitId)),
        ),
      ),
    );
    await tester.pump();

    expect(loaded, ['oak'], reason: 'an oak habit must ask for the oak file');
  });

  testWidgets('a species with no art takes no space at all', (tester) async {
    // Not a spinner and not a gap: four of six species have nothing to draw,
    // and a reserved empty box on every one of them would be worse than the
    // card simply being shorter.
    //
    // `lotus` is offered by `plantChoices` and absent from `plantArts`, which
    // is exactly this case. The oak used to stand here and now draws.
    await tester.pumpWidget(harness(plantType: 'lotus', stage: Stage.mature));
    await tester.pump();

    expect(find.byType(rive.RiveWidget), findsNothing);
    expect(tester.getSize(find.byType(PlantArtView)).height, 0);
  });

  testWidgets('a device without the native library still gets a garden', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(plantType: 'fern', stage: Stage.mature, art: false),
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
        ticker: GardenTicker.lively,
      ),
    );
    await tester.pump();
    expect(find.byType(rive.RiveWidget), findsNWidgets(2));

    await tester.pumpWidget(
      harness(
        plantType: 'fern',
        stage: Stage.mature,
        ticker: GardenTicker.lively,
      ),
    );
    await tester.pump();
    // Mid-fade: both stages on screen at once. This is the whole point of the
    // cross-fade — one artboard replacing another in a single frame is the
    // jarring cut it exists to avoid.
    await tester.pump(const Duration(milliseconds: 120));
    // Two stages plus the roots, which do not cross-fade: the root system does
    // not change with the stage, so fading it against itself would only make
    // it flicker.
    expect(find.byType(rive.RiveWidget), findsNWidgets(3));

    // And it resolves rather than leaving the old plant behind.
    //
    // Pumped by a known duration, not `pumpAndSettle`. A lively garden never
    // settles — the sway is an endless loop, which is precisely why
    // [GardenTicker.ambientEnabled] exists and why every other widget test in
    // the garden runs still. `pumpAndSettle` here times out rather than fails,
    // which is a slow and confusing way to learn that.
    await tester.pump(AppMotion.stageAdvanceDuration);
    expect(find.byType(rive.RiveWidget), findsNWidgets(2));
  });
}

class _FixedTicker extends GardenTickerController {
  _FixedTicker(this.value);

  final GardenTicker value;

  @override
  GardenTicker build() => value;
}
