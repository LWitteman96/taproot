import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/reflection.dart';

void main() {
  test('round-trips every field', () {
    final original = Reflection(
      id: 'r-1',
      habitId: 'habit-1',
      createdAt: DateTime(2026, 1, 5, 21),
      occasion: Occasion.miss,
      framing: Framing.diagnosis,
      inputMode: InputMode.typed,
      cueReported: 'got home from work',
      cueType: CueType.event,
      matchedDesignedCue: false,
      frictionReported: 'too tired',
      frictionType: FrictionType.energy,
      wasNudged: true,
    );

    final restored = Reflection.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.habitId, original.habitId);
    expect(restored.createdAt.isAtSameMomentAs(original.createdAt), isTrue);
    expect(restored.occasion, Occasion.miss);
    expect(restored.framing, Framing.diagnosis);
    expect(restored.inputMode, InputMode.typed);
    expect(restored.cueReported, 'got home from work');
    expect(restored.cueType, CueType.event);
    expect(restored.matchedDesignedCue, isFalse);
    expect(restored.frictionReported, 'too tired');
    expect(restored.frictionType, FrictionType.energy);
    expect(restored.wasNudged, isTrue);
  });

  test('keeps "not asked" distinct from "answered no"', () {
    // matchedDesignedCue is the cue-reliability numerator; a null that decodes
    // as false would quietly invent a failed validation.
    final notAsked = Reflection(
      id: 'r-2',
      habitId: 'habit-1',
      createdAt: DateTime(2026, 1, 5, 21),
      occasion: Occasion.completion,
      framing: Framing.discovery,
      inputMode: InputMode.cantRemember,
    );

    final restored = Reflection.fromJson(notAsked.toJson());

    expect(restored.matchedDesignedCue, isNull);
    expect(restored.cueReported, isNull);
    expect(restored.cueType, CueType.unknown);
    expect(restored.frictionType, isNull);
  });

  test('carries no derived root credit', () {
    // root_credit and counts_toward_c appear in the schema sketch but are
    // computed in roots.dart. Derived values are computed, never stored.
    final json = Reflection(
      id: 'r-3',
      habitId: 'habit-1',
      createdAt: DateTime(2026, 1, 5, 21),
      occasion: Occasion.completion,
      framing: Framing.discovery,
      inputMode: InputMode.chip,
    ).toJson();

    expect(json.keys, isNot(contains('root_credit')));
    expect(json.keys, isNot(contains('counts_toward_c')));
    expect(
      json.keys,
      containsAll(<String>[
        'id',
        'habit_id',
        'created_at',
        'occasion',
        'framing',
        'input_mode',
        'cue_reported',
        'cue_type',
        'matched_designed_cue',
        'friction_reported',
        'friction_type',
        'was_nudged',
      ]),
    );
  });
}
