import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/features/habits/domain/completion_retraction.dart';

/// The undo window, as a pure predicate.
///
/// Both the store (which enforces it) and the garden UI (which decides whether
/// to offer the affordance) read this, so they can never disagree about whether
/// a tap is still undoable.
void main() {
  Completion completionAt(DateTime at) =>
      Completion(id: 'c-1', habitId: 'habit-1', completedAt: at);

  test('a completion is undoable for the rest of its local day', () {
    final completion = completionAt(DateTime(2026, 3, 12, 9));

    expect(
      isRetractable(completion, at: DateTime(2026, 3, 12, 9, 0, 1)),
      isTrue,
    );
    expect(isRetractable(completion, at: DateTime(2026, 3, 12, 18)), isTrue);
    expect(
      isRetractable(completion, at: DateTime(2026, 3, 12, 23, 59, 59)),
      isTrue,
    );
  });

  test('and not once the local day has turned', () {
    final completion = completionAt(DateTime(2026, 3, 12, 23, 58));

    expect(isRetractable(completion, at: DateTime(2026, 3, 13, 0, 1)), isFalse);
    expect(isRetractable(completion, at: DateTime(2026, 3, 19)), isFalse);
  });

  test('the day is the local calendar day, not a 24-hour window', () {
    // A tap at 23:00 stops being undoable an hour later; one at 00:30 stays
    // undoable for nearly a day. That asymmetry is the point — the boundary
    // users reason about is midnight, not the stopwatch since the tap.
    final lateEvening = completionAt(DateTime(2026, 3, 12, 23));
    final earlyMorning = completionAt(DateTime(2026, 3, 12, 0, 30));

    expect(
      isRetractable(lateEvening, at: DateTime(2026, 3, 13, 0, 1)),
      isFalse,
    );
    expect(
      isRetractable(earlyMorning, at: DateTime(2026, 3, 12, 23, 30)),
      isTrue,
    );
  });

  test('a UTC-stored timestamp is judged on the local clock', () {
    final completion = completionAt(DateTime(2026, 3, 12, 9).toUtc());

    expect(isRetractable(completion, at: DateTime(2026, 3, 12, 21)), isTrue);
    expect(isRetractable(completion, at: DateTime(2026, 3, 13, 9)), isFalse);
  });
}
