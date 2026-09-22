import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_radius.dart';
import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/features/garden/domain/garden_state.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/domain/plant_descriptions.dart';
import 'package:taproot/features/garden/widgets/watering_control.dart';
import 'package:taproot/features/habits/domain/plant_choices.dart';

/// The floating detail card: scene layer 13.
///
/// Shows the selected plant and the two things there are to do with it. Fixed
/// over the soil — it never scrolls with the garden, and garden-design §4.1
/// keeps 90pt of soil above it so it cannot cover a plant's roots.
class PlantDetailCard extends ConsumerWidget {
  const PlantDetailCard({
    required this.plant,
    required this.ticker,
    required this.onWatered,
    this.onUndo,
    this.onReflect,
    super.key,
  });

  final PlantState plant;
  final GardenTicker ticker;
  final VoidCallback onWatered;

  /// Shown while the undo offer lasts. The handoff's disabled "Watered today"
  /// state is deliberately not adopted (garden-design §9): the app records more
  /// than one completion a day and the engine counts them.
  final VoidCallback? onUndo;

  /// Only when there is a watering nobody has asked about yet — see
  /// `canReflectOnProvider`. Otherwise Water takes the full width.
  ///
  /// Deliberately *not* gated on the check-in offer. Those gates —
  /// reflection-logic's "don't ask every time" — exist to stop the app from
  /// bringing things up unprompted, and a user who just watered this plant and
  /// wants to say why is not being interrupted by anyone. Answering removes the
  /// occasion, which is what takes the button away again and what stops the
  /// evening check-in asking about the same watering twice.
  final VoidCallback? onReflect;

  static const String undoLabel = 'Undo';
  static const String reflectLabel = 'Reflect';

  static const String shallowHint =
      'Growing fast on shallow roots — a reflection or two would anchor it.';
  static const String thirstyHint =
      'Looking a little thirsty. Seedlings perk right up.';
  static const String matureHint =
      'Locked in. A missed day won’t shake this one.';

  /// First match wins, per the handoff.
  static String? hintFor(HabitGrowth growth) {
    if (growth.isShallowRooted) return shallowHint;
    final young =
        growth.stage == Stage.sprout || growth.stage == Stage.seedling;
    if (young && growth.vitality < 0.95) return thirstyHint;
    if (growth.stage == Stage.mature) return matureHint;
    return null;
  }

  /// How often the designed cue actually fired, out of the reflections that had
  /// an opinion. Reflections that never answered are not counted as misses.
  static (int hit, int total) cueHits(PlantState plant) {
    var hit = 0;
    var total = 0;
    for (final reflection in plant.inputs.reflections) {
      if (reflection.matchedDesignedCue case final matched?) {
        total++;
        if (matched) hit++;
      }
    }
    return (hit, total);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final growth = plant.growth;
    final species = plantChoiceById(plant.habit.plantType)?.label ?? 'Plant';
    final (hit, total) = cueHits(plant);
    final reflections = growth.roots.weightedReflections.round();
    final hint = hintFor(growth);

    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: GardenColors.monoLabel.withValues(alpha: 0.75),
    );
    final body = TextStyle(
      fontFamily: 'Karla',
      fontSize: 14,
      color: GardenColors.ink.withValues(alpha: 0.80),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: GardenColors.card.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: const Color(0x17FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 50,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        plant.habit.name,
                        style: const TextStyle(
                          fontFamily: 'Newsreader',
                          fontSize: 24,
                          color: GardenColors.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$species · ${stageLabel(growth.stage).toLowerCase()}',
                      style: mono,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Cue worked $hit of $total times', style: body),
                Text(
                  '$reflections reflections · '
                  '${rootDepthLabel(growth.roots.depth)}',
                  style: body,
                ),
                if (hint != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    hint,
                    style: TextStyle(
                      fontFamily: 'Newsreader',
                      fontStyle: FontStyle.italic,
                      fontSize: 15,
                      color: GardenColors.inkHint.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 13,
                      child: WateringControl(
                        ticker: ticker,
                        wateredToday: plant.canUndo,
                        semanticLabel: waterActionLabel(
                          plant.habit.name,
                          again: plant.canUndo,
                        ),
                        onWatered: onWatered,
                      ),
                    ),
                    if (onUndo case final undo?) ...[
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: undo,
                        // Named, because "Undo" on its own is meaningless in a
                        // list of actions a screen reader reads out of context,
                        // and this card has two tap targets side by side.
                        child: Text(
                          undoLabel,
                          semanticsLabel: 'Undo watering ${plant.habit.name}',
                        ),
                      ),
                    ],
                    if (onReflect case final reflect?) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 10,
                        child: OutlinedButton(
                          onPressed: reflect,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            side: const BorderSide(color: Color(0x2EFFFFFF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.medium,
                              ),
                            ),
                          ),
                          child: const Text(reflectLabel),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The advisory root threshold for a stage, from the engine's constants rather
/// than the handoff's numbers. Null where the stage has none.
double? advisoryRootThreshold(Stage stage) =>
    EngineConstants.stageGates[stage]?.rootsThreshold;
