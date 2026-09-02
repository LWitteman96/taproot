import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/models/completion.dart';

void main() {
  test('round-trips through json', () {
    final original = Completion(
      id: 'c-1',
      habitId: 'habit-1',
      completedAt: DateTime(2026, 1, 5, 9, 30),
      wasNudged: true,
      source: CompletionSource.nudgeConfirmation,
    );

    final restored = Completion.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.habitId, original.habitId);
    expect(restored.completedAt.isAtSameMomentAs(original.completedAt), isTrue);
    expect(restored.wasNudged, isTrue);
    expect(restored.source, CompletionSource.nudgeConfirmation);
  });

  test('uses the schema column names', () {
    final json = Completion(
      id: 'c-1',
      habitId: 'habit-1',
      completedAt: DateTime(2026, 1, 5, 9, 30),
    ).toJson();

    expect(
      json.keys,
      containsAll(<String>[
        'id',
        'habit_id',
        'completed_at',
        'was_nudged',
        'source',
      ]),
    );
  });

  test('defaults are an un-nudged tap', () {
    final restored = Completion.fromJson(<String, Object?>{
      'id': 'c-1',
      'habit_id': 'habit-1',
      'completed_at': DateTime.utc(2026, 1, 5, 9).toIso8601String(),
    });

    expect(restored.wasNudged, isFalse);
    expect(restored.source, CompletionSource.tap);
  });

  test('reads the booleans SQLite gives back as integers', () {
    final restored = Completion.fromJson(<String, Object?>{
      'id': 'c-1',
      'habit_id': 'habit-1',
      'completed_at': DateTime.utc(2026, 1, 5, 9).toIso8601String(),
      'was_nudged': 1,
      'source': 'backfill',
    });

    expect(restored.wasNudged, isTrue);
    expect(restored.source, CompletionSource.backfill);
  });
}
