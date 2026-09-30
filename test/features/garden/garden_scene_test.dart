/// The scene shell: the world the plants stand in.
///
/// These are about geometry and wording rather than pixels. Where the ground
/// line falls decides every other position on the screen, and the header's copy
/// is fixed by the handoff, so both are worth pinning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/theme/garden_layout.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/domain/time_of_day_mode.dart';
import 'package:taproot/features/garden/widgets/garden_header.dart';
import 'package:taproot/features/garden/widgets/plant_silhouette.dart';

void main() {
  group('GardenLayout', () {
    test(
      'plants sit one pitch apart, starting half a pitch from the inset',
      () {
        expect(GardenLayout.slotCentre(0), 80);
        expect(GardenLayout.slotCentre(1), 208);
        expect(
          GardenLayout.slotCentre(3) - GardenLayout.slotCentre(2),
          GardenLayout.slotPitch,
        );
      },
    );

    test('about three plants fit a 402pt screen, with a fourth peeking in', () {
      // garden-design §4.3 wants the fourth slot just past the edge, so a wide
      // plant there shows that the row scrolls.
      const screen = 402.0;
      expect(GardenLayout.slotCentre(2), lessThan(screen));
      expect(GardenLayout.slotCentre(3), greaterThan(screen));
    });

    test(
      'a stage artboard stands on the ground line, not on its own bottom',
      () {
        // The plant is drawn at canvas y=900 of a 1024 square, so 124 art px of
        // the canvas hang below its feet. Getting this wrong buries the plant or
        // floats it.
        expect(GardenLayout.stageSize, closeTo(153.6, 1e-9));
        expect(GardenLayout.stageGroundOffset, closeTo(18.6, 1e-9));
      },
    );

    test('the ground line is 53% down a tall screen', () {
      const viewport = Size(402, 874);
      expect(
        GardenLayout.groundLine(viewport, cardTop: 700),
        closeTo(874 * 0.53, 1e-9),
      );
    });

    test(
      'a short screen moves the ground line up rather than burying roots',
      () {
        // The clamp exists so the detail card can never cover a plant's roots.
        const viewport = Size(402, 500);
        final ground = GardenLayout.groundLine(viewport, cardTop: 300);
        expect(ground, lessThan(viewport.height * 0.53));
        expect(ground, 300 - GardenLayout.minimumSoilBelowGround);
      },
    );

    test('the art is anchored on its ground line, not its canvas bottom', () {
      // The plant stands on canvas y=900 of a 1024 square. Anchoring on the
      // canvas bottom instead would float every plant 18.6pt above the soil,
      // which reads as a bug rather than as a plant.
      expect(GardenLayout.stageAboveGround, closeTo(135, 1e-9));
      expect(
        GardenLayout.stageAboveGround + GardenLayout.stageGroundOffset,
        closeTo(GardenLayout.stageSize, 1e-9),
      );
    });

    test('a mature fern is about 115pt tall and its roots reach 78pt down', () {
      // garden-design §4.2's own numbers, so a change to worldScale that
      // quietly breaks the design's sense of scale fails here.
      expect(GardenLayout.stageAboveGround, lessThan(140));
      expect(GardenLayout.rootsDepth, closeTo(78, 1e-9));
    });

    test('the scene is wide enough for the plants plus the empty plot', () {
      // Three plants means four slots: the plot always follows the last plant.
      expect(
        GardenLayout.sceneWidth(3),
        greaterThan(GardenLayout.slotCentre(3)),
      );
    });
  });

  group('TimeOfDayMode', () {
    test('the day is cut at 06, 09, 17 and 20', () {
      // The prototype's README omits the 06:00 cut; garden-design §7 takes the
      // boundaries from its code instead, so midnight is night and not dusk.
      expect(TimeOfDayMode.forHour(0), TimeOfDayMode.night);
      expect(TimeOfDayMode.forHour(5), TimeOfDayMode.night);
      expect(TimeOfDayMode.forHour(6), TimeOfDayMode.dawn);
      expect(TimeOfDayMode.forHour(8), TimeOfDayMode.dawn);
      expect(TimeOfDayMode.forHour(9), TimeOfDayMode.day);
      expect(TimeOfDayMode.forHour(16), TimeOfDayMode.day);
      expect(TimeOfDayMode.forHour(17), TimeOfDayMode.dusk);
      expect(TimeOfDayMode.forHour(19), TimeOfDayMode.dusk);
      expect(TimeOfDayMode.forHour(20), TimeOfDayMode.night);
      expect(TimeOfDayMode.forHour(23), TimeOfDayMode.night);
    });

    test('every mode has a greeting and a full sky', () {
      for (final mode in TimeOfDayMode.values) {
        expect(mode.greeting, isNotEmpty);
        expect(mode.sky.length, greaterThanOrEqualTo(3));
        // Stops must run 0 to 1 and ascend, or the gradient throws at paint.
        expect(mode.sky.first.$2, 0);
        expect(mode.sky.last.$2, 1);
      }
    });
  });

  group('GardenHeader', () {
    test('the status line says how the garden is, never what is owed', () {
      // design-spec §6 and garden-design §2: no counts of what is done, no
      // "0 of 3", nothing due. The wording is the handoff's, exactly.
      expect(GardenHeader.thirstyLine(0), GardenHeader.allWatered);
      expect(GardenHeader.thirstyLine(1), 'One plant could use a drink.');
      expect(GardenHeader.thirstyLine(4), 'Four plants could use a drink.');
      // Spelled while the handoff spells them, digits past that rather than
      // inventing words it never wrote.
      expect(GardenHeader.thirstyLine(7), '7 plants could use a drink.');
    });
  });

  group('PlantSilhouette', () {
    test('stage sizes only ever grow', () {
      // Size is the growth story (garden-design §2), so a later stage that drew
      // smaller would say the opposite of what the engine means.
      var previous = 0.0;
      for (final stage in Stage.values) {
        final height = PlantSilhouette.sizeFor(stage).height;
        expect(height, greaterThan(previous), reason: '${stage.name} shrank');
        previous = height;
      }
    });

    testWidgets('a seed carries no caption, because it is smaller than one', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlantSilhouetteLabel(species: 'Oak', stage: Stage.seed),
          ),
        ),
      );
      expect(find.textContaining('Oak'), findsNothing);
    });

    testWidgets('a bigger stage says what it is', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlantSilhouetteLabel(species: 'Oak', stage: Stage.young),
          ),
        ),
      );
      expect(find.textContaining('Oak'), findsOneWidget);
      expect(find.textContaining('young'), findsOneWidget);
    });
  });
}
