/// When the check-in has anything to commit to.
///
/// check-in-design §4.3 skips step 2 in three cases, and they are all the same
/// case: there is no open question about tomorrow. Asking anyway would be the
/// app pretending to listen.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/features/reflection/domain/commit_target.dart';

import '../../../utils/store_fixtures.dart';

void main() {
  final now = DateTime(2026, 3, 12, 20);
  final createdAt = DateTime(2026, 1, 5, 9);

  NudgeRecord nudgeOn(
    DateTime at, {
    bool confirmed = false,
    bool declined = false,
  }) => NudgeRecord(
    id: 'n-${at.day}',
    habitId: 'habit-1',
    expectedOccasionAt: at,
    sent: true,
    confirmed: confirmed,
    declined: declined,
  );

  /// Every expected occasion in the horizon gets a ledger row, including the
  /// ones deliberately not nudged — that is what autonomy is counted over.
  List<NudgeRecord> ledgerFor(List<int> days) => [
    for (final day in days) nudgeOn(DateTime(2026, 3, day, 7)),
  ];

  test('the next occasion is what it asks about', () {
    final target = commitTargetFor(
      habit: testHabit(targetFrequency: 7, createdAt: createdAt),
      nudges: ledgerFor([13, 14, 15]),
      pauses: const [],
      now: now,
    );
    expect(target, isNotNull);
    expect(target!.at.day, 13);
  });

  test('today is never the answer', () {
    // The check-in happens in the evening of a day whose occasion has already
    // been and gone. Committing to it would be committing to the past.
    final target = commitTargetFor(
      habit: testHabit(targetFrequency: 7, createdAt: createdAt),
      nudges: ledgerFor([12, 13]),
      pauses: const [],
      now: now,
    );
    expect(target!.at.day, 13);
  });

  test('an occasion already answered is skipped', () {
    // The notification's own Yes action records `confirmed` without opening
    // anything, and asking again would be the app not listening to itself.
    for (final answered in [
      nudgeOn(DateTime(2026, 3, 13, 7), confirmed: true),
      nudgeOn(DateTime(2026, 3, 13, 7), declined: true),
    ]) {
      expect(
        commitTargetFor(
          habit: testHabit(targetFrequency: 7, createdAt: createdAt),
          nudges: [answered],
          pauses: const [],
          now: now,
        ),
        isNull,
      );
    }
  });

  test('a paused habit is not asked to commit', () {
    expect(
      commitTargetFor(
        habit: testHabit(
          targetFrequency: 7,
          createdAt: createdAt,
          pausedAt: DateTime(2026, 3, 1),
        ),
        nudges: ledgerFor([13]),
        pauses: const [],
        now: now,
      ),
      isNull,
    );
  });

  test('a graduated habit is not asked to commit', () {
    // Knowing when to stop asking is the point of graduation.
    expect(
      commitTargetFor(
        habit: testHabit(
          targetFrequency: 7,
          createdAt: createdAt,
          graduatedAt: DateTime(2026, 3, 1),
        ),
        nudges: ledgerFor([13]),
        pauses: const [],
        now: now,
      ),
      isNull,
    );
  });

  test('a paused day is not an occasion to commit to', () {
    // A pause excludes a day from every window, so an occasion there is an
    // expectation the engine has already agreed not to hold.
    final target = commitTargetFor(
      habit: testHabit(targetFrequency: 7, createdAt: createdAt),
      nudges: ledgerFor([13, 14]),
      pauses: [
        PauseInterval(
          startedAt: DateTime(2026, 3, 13),
          endedAt: DateTime(2026, 3, 13, 23, 59),
        ),
      ],
      now: now,
    );
    expect(target!.at.day, 14);
  });

  test('no ledger row means the planner has not got there yet', () {
    // Recording against a row that does not exist would invent one, and the
    // next planning pass would overwrite it.
    expect(
      commitTargetFor(
        habit: testHabit(targetFrequency: 7, createdAt: createdAt),
        nudges: const [],
        pauses: const [],
        now: now,
      ),
      isNull,
    );
  });
}
