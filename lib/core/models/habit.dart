import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/core/utils/json_codec.dart';

/// One habit — one plant.
///
/// The cue → routine → reward triple is a first-class object the user designs,
/// not an app default, so all three are stored fields rather than inferred.
/// What is *not* here is anything the engine derives: stage, vitality, roots
/// and autonomy are computed from completions and reflections at read time,
/// because storing them would make tuning a constant a data migration.
@immutable
class Habit {
  // Not const: the cue-type assert calls a getter, which a const constructor
  // cannot evaluate. Enforcing the invariant is worth more than constness on a
  // model that is only ever built from user input or a database row.
  Habit({
    required this.id,
    required this.name,
    required this.plantType,
    required this.targetFrequency,
    required this.journey,
    required this.createdAt,
    this.category,
    this.identityStatement,
    this.designedCue,
    this.designedCueType,
    this.routine,
    this.reward,
    this.pausedAt,
    this.graduatedAt,
  }) : assert(
         designedCueType == null || designedCueType.isSchedulable,
         'A designed cue must be externally schedulable — the engine cannot '
         'schedule, nudge or fairly measure a habit hung on a mood. Internal '
         'cues are still valid as cues *discovered* through reflection.',
       ),
       assert(
         journey != HabitJourney.design || designedCue != null,
         'A designed habit carries the cue it was designed around. The reverse '
         'does not hold: a tracked habit that discovers a reliable cue through '
         'reflection may have one locked in later, and stays Journey A. The '
         'cue *type* is required by the creation flow rather than here, '
         'because a persisted cue whose type was never recorded is a row this '
         'model still has to be able to read.',
       ),
       assert(
         targetFrequency >= EngineConstants.minimumTargetFrequency &&
             targetFrequency <= EngineConstants.maximumTargetFrequency,
         'targetFrequency is a weekly count in 1..7',
       );

  final String id;
  final String name;

  /// "I am someone who runs." The identity the habit is evidence for.
  final String? identityStatement;

  /// Which plant this habit grows. Chosen at creation as a quiet identity
  /// moment.
  ///
  /// Left as a free identifier rather than an enum: the plant set is still with
  /// the external illustrator, and closing the type now would be inventing a
  /// list the design spec does not have.
  final String plantType;

  /// f — the user-declared weekly target. The engine's anchor.
  final int targetFrequency;

  /// Which route this habit took into the garden — designed, or tracked
  /// (design-spec §2). Recorded rather than inferred; see [HabitJourney].
  final HabitJourney journey;

  /// What kind of habit this is, for seeding the first reflection's chips
  /// (starter-chip-library.md §0). Null is a supported answer — see
  /// [HabitCategory].
  final HabitCategory? category;

  final String? designedCue;

  /// Null until the user designs a cue. Only externally schedulable types are
  /// admissible here (growth spec §1).
  final CueType? designedCueType;

  final String? routine;
  final String? reward;

  final DateTime createdAt;

  /// Set while a pause is running — the start of the open pause interval.
  ///
  /// **Derived, not stored.** The pause ledger is the only place this fact
  /// lives; the repository fills this in on read and never writes it back.
  /// That is why [toJson] omits `paused_at` while [fromJson] accepts it: the
  /// map a repository builds carries the derived value, and a map this model
  /// produces must not be able to contradict the ledger.
  final DateTime? pausedAt;

  final DateTime? graduatedAt;

  bool get isPaused => pausedAt != null;

  bool get hasGraduated => graduatedAt != null;

  /// Whether the loop this habit was designed around is on record.
  bool get hasDesignedLoop => designedCue != null && designedCueType != null;

  factory Habit.fromJson(Map<String, Object?> json) {
    final designedCue = readString(json, 'designed_cue');

    return Habit(
      id: requireString(json, 'id'),
      name: requireString(json, 'name'),
      identityStatement: readString(json, 'identity_statement'),
      plantType: requireString(json, 'plant_type'),
      targetFrequency: requireInt(json, 'target_frequency'),
      // Not `requireEnum`: rows written before schema version 2 have no
      // journey, and the one defensible reading of such a row is the inference
      // the column exists to replace — a cue present at creation means the loop
      // was designed. The upgrade step backfills exactly this, so in practice
      // the fallback only fires for a row that skipped the migration.
      journey:
          readEnum(json, 'journey', HabitJourney.values) ??
          (designedCue != null ? HabitJourney.design : HabitJourney.track),
      category: readEnum(json, 'category', HabitCategory.values),
      designedCue: designedCue,
      designedCueType: readEnum(json, 'designed_cue_type', CueType.values),
      routine: readString(json, 'routine'),
      reward: readString(json, 'reward'),
      createdAt: requireDateTime(json, 'created_at'),
      pausedAt: readDateTime(json, 'paused_at'),
      graduatedAt: readDateTime(json, 'graduated_at'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'identity_statement': identityStatement,
    'plant_type': plantType,
    'target_frequency': targetFrequency,
    'journey': encodeEnum(journey),
    'category': encodeEnum(category),
    'designed_cue': designedCue,
    'designed_cue_type': encodeEnum(designedCueType),
    'routine': routine,
    'reward': reward,
    'created_at': encodeDateTime(createdAt),
    // No 'paused_at': see the field doc — it is derived from the pause ledger.
    'graduated_at': encodeDateTime(graduatedAt),
  };

  Habit copyWith({
    String? id,
    String? name,
    String? Function()? identityStatement,
    String? plantType,
    int? targetFrequency,
    HabitJourney? journey,
    HabitCategory? Function()? category,
    String? Function()? designedCue,
    CueType? Function()? designedCueType,
    String? Function()? routine,
    String? Function()? reward,
    DateTime? createdAt,
    DateTime? Function()? pausedAt,
    DateTime? Function()? graduatedAt,
  }) => Habit(
    id: id ?? this.id,
    name: name ?? this.name,
    identityStatement: identityStatement != null
        ? identityStatement()
        : this.identityStatement,
    plantType: plantType ?? this.plantType,
    targetFrequency: targetFrequency ?? this.targetFrequency,
    journey: journey ?? this.journey,
    category: category != null ? category() : this.category,
    designedCue: designedCue != null ? designedCue() : this.designedCue,
    designedCueType: designedCueType != null
        ? designedCueType()
        : this.designedCueType,
    routine: routine != null ? routine() : this.routine,
    reward: reward != null ? reward() : this.reward,
    createdAt: createdAt ?? this.createdAt,
    pausedAt: pausedAt != null ? pausedAt() : this.pausedAt,
    graduatedAt: graduatedAt != null ? graduatedAt() : this.graduatedAt,
  );

  @override
  String toString() => 'Habit($id, $name, f: $targetFrequency, $plantType)';
}
