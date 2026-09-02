import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/models/nudge.dart';

void main() {
  test('round-trips every field', () {
    final original = NudgeRecord(
      id: 'n-1',
      habitId: 'habit-1',
      expectedOccasionAt: DateTime(2026, 1, 5, 18),
      sent: true,
      scheduledFor: DateTime(2026, 1, 5, 18, 30),
      confirmed: true,
      declined: false,
    );

    final restored = NudgeRecord.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.habitId, original.habitId);
    expect(
      restored.expectedOccasionAt.isAtSameMomentAs(original.expectedOccasionAt),
      isTrue,
    );
    expect(restored.sent, isTrue);
    expect(
      restored.scheduledFor!.isAtSameMomentAs(original.scheduledFor!),
      isTrue,
    );
    expect(restored.confirmed, isTrue);
    expect(restored.declined, isFalse);
  });

  test('a deliberately silent occasion survives the round trip', () {
    // The un-sent rows are autonomy's denominator. If they decoded away, the
    // ratio would silently become "confirmed / sent" instead.
    final silent = NudgeRecord(
      id: 'n-2',
      habitId: 'habit-1',
      expectedOccasionAt: DateTime(2026, 1, 5, 18),
      sent: false,
    );

    final restored = NudgeRecord.fromJson(silent.toJson());

    expect(restored.sent, isFalse);
    expect(restored.scheduledFor, isNull);
    expect(restored.confirmed, isFalse);
    expect(restored.declined, isFalse);
  });

  test('uses the schema column names', () {
    final json = NudgeRecord(
      id: 'n-3',
      habitId: 'habit-1',
      expectedOccasionAt: DateTime(2026, 1, 5, 18),
      sent: false,
    ).toJson();

    expect(
      json.keys,
      containsAll(<String>[
        'id',
        'habit_id',
        'expected_occasion_at',
        'scheduled_for',
        'sent',
        'confirmed',
        'declined',
      ]),
    );
  });
}
