import 'package:meta/meta.dart';

/// One plant a habit can grow as.
///
/// Named [PlantChoice] rather than `PlantType` because `Habit.plantType` is a
/// free-form string id: the plant set is still with the external illustrator,
/// and closing the type would mean inventing a list the design spec does not
/// have. This is the *offer* the creation flow makes, not the domain of the
/// field — a habit restored from a row naming a plant that is no longer offered
/// still reads back fine.
@immutable
class PlantChoice {
  const PlantChoice({
    required this.id,
    required this.label,
    required this.character,
  });

  /// What gets stored on the habit.
  final String id;

  final String label;

  /// The half-sentence that makes choosing one an identity moment rather than
  /// picking an icon — "I'm growing an oak" carries more than "habit #3"
  /// (design-spec §4).
  final String character;
}

/// The placeholder catalogue.
///
/// **Placeholder, deliberately.** design-spec §4 sends the per-habit plant art
/// to a paid external designer and says to treat plant visuals as a slot until
/// it arrives, so this is six plausible ids and the words around them — enough
/// for the identity moment to land, small enough to throw away. The three the
/// spec itself names (lotus, oak, fern) are kept.
const List<PlantChoice> plantChoices = <PlantChoice>[
  PlantChoice(
    id: 'oak',
    label: 'Oak',
    character: 'slow, stubborn, and impossible to knock over later',
  ),
  PlantChoice(
    id: 'fern',
    label: 'Fern',
    character: 'quiet and patient, happiest out of the spotlight',
  ),
  PlantChoice(
    id: 'lotus',
    label: 'Lotus',
    character: 'still on the surface, all the work underneath',
  ),
  PlantChoice(
    id: 'sunflower',
    label: 'Sunflower',
    character: 'quick, bright, and oriented at something',
  ),
  PlantChoice(
    id: 'lavender',
    label: 'Lavender',
    character: 'unfussy, and better for being cut back now and then',
  ),
  PlantChoice(
    id: 'pine',
    label: 'Pine',
    character: 'evergreen — the one that holds through a bad season',
  ),
];

/// The catalogue entry for [id], or null if nothing offers it any more.
PlantChoice? plantChoiceById(String? id) {
  if (id == null) return null;
  for (final choice in plantChoices) {
    if (choice.id == id) return choice;
  }
  return null;
}
