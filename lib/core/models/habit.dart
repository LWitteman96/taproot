import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
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
    required this.createdAt,
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

  final String? designedCue;

  /// Null until the user designs a cue. Only externally schedulable types are
  /// admissible here (growth spec §1).
  final CueType? designedCueType;

  final String? routine;
  final String? reward;

  final DateTime createdAt;

  /// Set while a pause is running. The pause *intervals* live in their own
  /// table — this is the current-state stamp the UI reads.
  final DateTime? pausedAt;

  final DateTime? graduatedAt;

  bool get isPaused => pausedAt != null;

  bool get hasGraduated => graduatedAt != null;

  factory Habit.fromJson(Map<String, Object?> json) => Habit(
    id: requireString(json, 'id'),
    name: requireString(json, 'name'),
    identityStatement: readString(json, 'identity_statement'),
    plantType: requireString(json, 'plant_type'),
    targetFrequency: requireInt(json, 'target_frequency'),
    designedCue: readString(json, 'designed_cue'),
    designedCueType: readEnum(json, 'designed_cue_type', CueType.values),
    routine: readString(json, 'routine'),
    reward: readString(json, 'reward'),
    createdAt: requireDateTime(json, 'created_at'),
    pausedAt: readDateTime(json, 'paused_at'),
    graduatedAt: readDateTime(json, 'graduated_at'),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'identity_statement': identityStatement,
    'plant_type': plantType,
    'target_frequency': targetFrequency,
    'designed_cue': designedCue,
    'designed_cue_type': encodeEnum(designedCueType),
    'routine': routine,
    'reward': reward,
    'created_at': encodeDateTime(createdAt),
    'paused_at': encodeDateTime(pausedAt),
    'graduated_at': encodeDateTime(graduatedAt),
  };

  Habit copyWith({
    String? id,
    String? name,
    String? Function()? identityStatement,
    String? plantType,
    int? targetFrequency,
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
