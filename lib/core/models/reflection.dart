import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';

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
