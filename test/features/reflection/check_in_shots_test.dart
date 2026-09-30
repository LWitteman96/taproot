/// Renders each framing's step 1 and a done state to `.tmp/shots/`.
///
/// Not a test of behaviour — an assertion that each framing *renders*, plus a
/// set of images to look at. It exists because the check-in's five framings are
/// chosen by reflection-logic from a habit's history, so reaching them on a
/// device means seeding five different histories; and because this machine's
/// Xcode has no SimulatorKit, so there is no way to tap through to them.
///
/// Run with: flutter test test/features/reflection/check_in_shots_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/reflection/domain/check_in_scheduler.dart';
import 'package:taproot/features/reflection/domain/reflection_priority.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';
import 'package:taproot/features/reflection/widgets/check_in_done.dart';
import 'package:taproot/features/reflection/widgets/check_in_look_back.dart';
import 'package:taproot/features/reflection/widgets/check_in_sheet.dart';

import '../../utils/fake_repositories.dart';
import '../../utils/store_fixtures.dart';

void main() {
  final now = DateTime(2026, 3, 12, 20);
  final directory = Directory('.tmp/shots');

  late FakeHabitService habits;
  late FakeCompletionService completions;
  late FakeReflectionService reflections;
  late FakeNudgeService nudges;

  setUpAll(() async {
    directory.createSync(recursive: true);
    // Without this every glyph renders as a filled box: the test environment
    // ships a placeholder font, and these images exist to be *read*.
    await _loadFont('Newsreader', 'assets/fonts/Newsreader.ttf');
    await _loadFont('Karla', 'assets/fonts/Karla.ttf');
    // Karla stands in for the platform mono here. The letterforms are wrong,
    // but a readable meta row is worth more in a review picture than an
    // accurate row of boxes.
    await _loadFont('monospace', 'assets/fonts/Karla.ttf');
  });

  setUp(() {
    habits = FakeHabitService(clock: () => now);
    completions = FakeCompletionService(habits: habits, clock: () => now);
    reflections = FakeReflectionService(habits: habits, clock: () => now);
    nudges = FakeNudgeService(habits: habits);
  });

  Habit habit({String? cue = 'after breakfast'}) => testHabit(
    name: 'Morning run',
    designedCue: cue,
    designedCueType: cue == null ? null : CueType.event,
    createdAt: DateTime(2026, 1, 5, 9),
  );

  CheckInOffer offer(Framing framing, {String? cue = 'after breakfast'}) =>
      CheckInOffer(
        habit: habit(cue: cue),
        candidate: CheckInCandidate(
          occasion: CheckInOccasion(
            habitId: 'habit-1',
            occasion: framing == Framing.diagnosis
                ? Occasion.miss
                : Occasion.completion,
            at: DateTime(2026, 3, 12, 7, 10),
          ),
          framing: framing,
          priority: 1,
        ),
        // The chip *set* is the surfacing rule's job; these are the
        // starter-chip-library §7.1 example A values, used here only so the
        // pictures show a realistic row.
        cueChips: const [
          StarterChip('after breakfast', CueType.event, 1, 'routine'),
          StarterChip('after coffee', CueType.event, 0.8, 'routine'),
          StarterChip('put my shoes on', CueType.event, 0.7, 'routine'),
          StarterChip('first thing up', CueType.time, 0.6, 'time'),
        ],
        frictionChips: const [
          FrictionChip('just forgot', FrictionType.forgot),
          FrictionChip('ran out of time', FrictionType.time),
          FrictionChip('too tired', FrictionType.energy),
          FrictionChip('something came up', FrictionType.competing),
        ],
        isFirstReflection: false,
      );

  Future<void> shoot(WidgetTester tester, String name, Widget sheet) async {
    tester.view.physicalSize = const Size(1206, 1500);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The look-back reads the check-in controller, which reaches the
          // database. These pictures are about layout and copy, so it gets
          // fakes rather than a store.
          habitServiceProvider.overrideWithValue(habits),
          completionServiceProvider.overrideWithValue(completions),
          reflectionServiceProvider.overrideWithValue(reflections),
          nudgeServiceProvider.overrideWithValue(nudges),
          newIdProvider.overrideWithValue(() => 'reflection-1'),
          clockProvider.overrideWithValue(() => now),
          habitRootDepthProvider('habit-1').overrideWithValue(0.42),
          gardenTickerProvider.overrideWith(_StillTicker.new),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            backgroundColor: GardenColors.bgApp,
            body: RepaintBoundary(
              key: const Key('shot'),
              child: Align(alignment: Alignment.bottomCenter, child: sheet),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        tester.renderObject(find.byKey(const Key('shot')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${directory.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final framing in Framing.values) {
    testWidgets('${framing.name} step 1 renders', (tester) async {
      await shoot(
        tester,
        'checkin-1-${framing.name}',
        CheckInSheet(
          habitName: 'Morning run',
          step: '1 of 2',
          ticker: GardenTicker.still,
          child: CheckInLookBack(
            offer: offer(framing),
            ticker: GardenTicker.still,
            onAnswered: (_) {},
            onSkipped: () {},
          ),
        ),
      );
    });
  }

  testWidgets('the expanded stage renders', (tester) async {
    await shoot(
      tester,
      'checkin-1-validation-expanded',
      _Expanded(offer: offer(Framing.validation)),
    );
  });

  testWidgets('done renders', (tester) async {
    await shoot(
      tester,
      'checkin-done',
      CheckInSheet(
        habitName: 'Morning run',
        step: 'done',
        ticker: GardenTicker.still,
        child: CheckInDone(
          habitId: 'habit-1',
          framing: Framing.discovery,
          inputMode: InputMode.chip,
          ticker: GardenTicker.still,
          commitDay: 'Tomorrow',
          onBack: () {},
        ),
      ),
    );
  });

  testWidgets('done with the autonomy insight renders', (tester) async {
    await shoot(
      tester,
      'checkin-done-autonomy',
      CheckInSheet(
        habitName: 'Morning run',
        step: 'done',
        ticker: GardenTicker.still,
        child: CheckInDone(
          habitId: 'habit-1',
          framing: Framing.autonomy,
          inputMode: InputMode.chip,
          ticker: GardenTicker.still,
          commitDay: 'Tomorrow',
          showAutonomyInsight: true,
          onBack: () {},
        ),
      ),
    );
  });
}

/// Taps the "no" chip so the expansion is what gets rendered.
class _Expanded extends StatefulWidget {
  const _Expanded({required this.offer});

  final CheckInOffer offer;

  @override
  State<_Expanded> createState() => _ExpandedState();
}

class _ExpandedState extends State<_Expanded> {
  @override
  Widget build(BuildContext context) => CheckInSheet(
    habitName: 'Morning run',
    step: '1 of 2',
    ticker: GardenTicker.still,
    child: CheckInLookBack(
      offer: widget.offer,
      ticker: GardenTicker.still,
      onAnswered: (_) {},
      onSkipped: () {},
    ),
  );
}

class _StillTicker extends GardenTickerController {
  @override
  GardenTicker build() => GardenTicker.still;
}

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(
      File(path).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
    );
  await loader.load();
}
