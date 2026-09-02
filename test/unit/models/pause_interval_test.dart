import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/models/pause_interval.dart';

void main() {
  test('round-trips a closed interval', () {
    final original = PauseInterval(
      startedAt: DateTime(2026, 2, 1, 8),
      endedAt: DateTime(2026, 2, 8, 8),
    );

    final restored = PauseInterval.fromJson(original.toJson());

    expect(restored.startedAt.isAtSameMomentAs(original.startedAt), isTrue);
    expect(restored.endedAt!.isAtSameMomentAs(original.endedAt!), isTrue);
    expect(restored.isOpen, isFalse);
  });

  test('round-trips an open interval', () {
    final restored = PauseInterval.fromJson(
      PauseInterval(startedAt: DateTime(2026, 2, 1, 8)).toJson(),
    );

    expect(restored.endedAt, isNull);
    expect(restored.isOpen, isTrue);
  });

  test('uses the schema column names, without the row identity', () {
    // id and habit_id belong to the habit_pauses row, not to the interval the
    // engine reasons about.
    final json = PauseInterval(startedAt: DateTime(2026, 2, 1, 8)).toJson();

    expect(json.keys, containsAll(<String>['started_at', 'ended_at']));
    expect(json.keys, isNot(anyOf(contains('id'), contains('habit_id'))));
  });
}
