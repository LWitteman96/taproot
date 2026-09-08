import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/utils/json_codec.dart';

/// One evening check-in answer (reflection spec §5).
///
/// `root_credit` and `counts_toward_c` appear as columns in the schema sketch
/// but are *derived* here — see `rootCreditFor` and `countsTowardConvergence`
/// in `lib/core/engine/roots.dart`. Derived values are computed, never stored.
@immutable
class Reflection {
  const Reflection({
    required this.id,
    required this.habitId,
    required this.createdAt,
    required this.occasion,
    required this.framing,
    required this.inputMode,
    this.cueReported,
    this.cueType = CueType.unknown,
    this.matchedDesignedCue,
    this.frictionReported,
    this.frictionType,
    this.wasNudged = false,
  });

  final String id;
  final String habitId;
  final DateTime createdAt;
  final Occasion occasion;
  final Framing framing;
  final InputMode inputMode;

  /// The cue the user named. Null for `cantRemember` and `skipped`.
  final String? cueReported;
  final CueType cueType;

  /// Whether the reported cue was the designed one. Null when not applicable.
  /// The share of true across validations is the cue-reliability number.
  final bool? matchedDesignedCue;

  final String? frictionReported;
  final FrictionType? frictionType;

  final bool wasNudged;

  factory Reflection.fromJson(Map<String, Object?> json) => Reflection(
    id: requireString(json, 'id'),
    habitId: requireString(json, 'habit_id'),
    createdAt: requireDateTime(json, 'created_at'),
    occasion: requireEnum(json, 'occasion', Occasion.values),
    framing: requireEnum(json, 'framing', Framing.values),
    inputMode: requireEnum(json, 'input_mode', InputMode.values),
    cueReported: readString(json, 'cue_reported'),
    cueType: readEnum(json, 'cue_type', CueType.values) ?? CueType.unknown,
    matchedDesignedCue: readNullableBool(json, 'matched_designed_cue'),
    frictionReported: readString(json, 'friction_reported'),
    frictionType: readEnum(json, 'friction_type', FrictionType.values),
    wasNudged: readBool(json, 'was_nudged'),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'habit_id': habitId,
    'created_at': encodeDateTime(createdAt),
    'occasion': encodeEnum(occasion),
    'framing': encodeEnum(framing),
    'input_mode': encodeEnum(inputMode),
    'cue_reported': cueReported,
    'cue_type': encodeEnum(cueType),
    'matched_designed_cue': matchedDesignedCue,
    'friction_reported': frictionReported,
    'friction_type': encodeEnum(frictionType),
    'was_nudged': wasNudged,
  };

  Reflection copyWith({
    String? id,
    String? habitId,
    DateTime? createdAt,
    Occasion? occasion,
    Framing? framing,
    InputMode? inputMode,
    String? Function()? cueReported,
    CueType? cueType,
    bool? Function()? matchedDesignedCue,
    String? Function()? frictionReported,
    FrictionType? Function()? frictionType,
    bool? wasNudged,
  }) => Reflection(
    id: id ?? this.id,
    habitId: habitId ?? this.habitId,
    createdAt: createdAt ?? this.createdAt,
    occasion: occasion ?? this.occasion,
    framing: framing ?? this.framing,
    inputMode: inputMode ?? this.inputMode,
    cueReported: cueReported != null ? cueReported() : this.cueReported,
    cueType: cueType ?? this.cueType,
    matchedDesignedCue: matchedDesignedCue != null
        ? matchedDesignedCue()
        : this.matchedDesignedCue,
    frictionReported: frictionReported != null
        ? frictionReported()
        : this.frictionReported,
    frictionType: frictionType != null ? frictionType() : this.frictionType,
    wasNudged: wasNudged ?? this.wasNudged,
  );

  @override
  String toString() =>
      'Reflection($id, $createdAt, $framing, $inputMode, cue: $cueReported)';
}
