import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/features/notifications/domain/occasion_collapse.dart';

NudgeRecord nudge({
  required String id,
  String habitId = 'habit-1',
  required DateTime expectedOccasionAt,
  bool sent = false,
  bool confirmed = false,
  bool declined = false,
  DateTime? scheduledFor,
}) => NudgeRecord(
  id: id,
  habitId: habitId,
  expectedOccasionAt: expectedOccasionAt,
  sent: sent,
  confirmed: confirmed,
  declined: declined,
  scheduledFor: scheduledFor,
);

void main() {
  group('collapseDuplicateOccasions', () {
    test('leaves a ledger with no duplicates alone', () {
      final rows = <NudgeRecord>[
        nudge(id: 'a', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
        nudge(id: 'b', expectedOccasionAt: DateTime(2026, 3, 5, 19)),
      ];

      final collapsed = collapseDuplicateOccasions(rows);

      expect(collapsed.map((row) => row.id), <String>['a', 'b']);
    });

    test('two devices planning one evening count as one occasion', () {
      // The whole point. These rows are autonomy's denominator, so two of them
      // for one occasion means an occasion that happened once is counted
      // twice — a habit that stood on its own once looks like once out of two.
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'from-phone', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
        nudge(id: 'from-tablet', expectedOccasionAt: DateTime(2026, 3, 4, 20)),
      ]);

      expect(collapsed, hasLength(1));
    });

    test('keyed by local date, not by the instant', () {
      // The ledger's rule is one row per habit per local *date*, which is what
      // `saveNudge` enforces and what a completion is matched against. Two
      // devices planning the same evening will not agree on the minute.
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'a', expectedOccasionAt: DateTime(2026, 3, 4, 8)),
        nudge(id: 'b', expectedOccasionAt: DateTime(2026, 3, 4, 22, 30)),
      ]);

      expect(collapsed, hasLength(1));
    });

    test('different days stay different occasions', () {
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'a', expectedOccasionAt: DateTime(2026, 3, 4, 23, 59)),
        nudge(id: 'b', expectedOccasionAt: DateTime(2026, 3, 5, 0, 1)),
      ]);

      expect(collapsed, hasLength(2));
    });

    test('a habit is never collapsed into another habit', () {
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'a', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
        nudge(
          id: 'b',
          habitId: 'habit-2',
          expectedOccasionAt: DateTime(2026, 3, 4, 19),
        ),
      ]);

      expect(collapsed, hasLength(2));
    });

    test('identity goes to the lowest id, whatever order they arrive in', () {
      // Arbitrary but stable: both devices reach the same answer without
      // talking to each other, and keep reaching it after a re-pull — which
      // "first one written" would not, since rows can arrive either way round.
      final forwards = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'aaa', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
        nudge(id: 'zzz', expectedOccasionAt: DateTime(2026, 3, 4, 20)),
      ]);
      final backwards = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'zzz', expectedOccasionAt: DateTime(2026, 3, 4, 20)),
        nudge(id: 'aaa', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
      ]);

      expect(forwards.single.id, 'aaa');
      expect(backwards.single.id, 'aaa');
    });

    test('sent is OR-ed: if either device queued one, one was queued', () {
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'aaa', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
        nudge(
          id: 'zzz',
          expectedOccasionAt: DateTime(2026, 3, 4, 20),
          sent: true,
        ),
      ]);

      expect(
        collapsed.single.id,
        'aaa',
        reason: 'identity is still the lowest',
      );
      expect(
        collapsed.single.sent,
        isTrue,
        reason: 'and the outcome comes from whichever row has it',
      );
    });

    test('an answer given on either device is still an answer', () {
      // confirmed and declined can be written by a background isolate from the
      // notification shade, which is the normal path — and that isolate is on
      // whichever device the user picked up.
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(
          id: 'aaa',
          expectedOccasionAt: DateTime(2026, 3, 4, 19),
          confirmed: true,
        ),
        nudge(
          id: 'zzz',
          expectedOccasionAt: DateTime(2026, 3, 4, 20),
          declined: true,
        ),
      ]);

      expect(collapsed.single.confirmed, isTrue);
      expect(collapsed.single.declined, isTrue);
    });

    test('scheduledFor is the earliest, being the one that would fire', () {
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(
          id: 'aaa',
          expectedOccasionAt: DateTime(2026, 3, 4, 19),
          scheduledFor: DateTime(2026, 3, 4, 20),
        ),
        nudge(
          id: 'zzz',
          expectedOccasionAt: DateTime(2026, 3, 4, 20),
          scheduledFor: DateTime(2026, 3, 4, 18),
        ),
      ]);

      expect(collapsed.single.scheduledFor, DateTime(2026, 3, 4, 18));
    });

    test('a null scheduledFor does not beat a real one', () {
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'aaa', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
        nudge(
          id: 'zzz',
          expectedOccasionAt: DateTime(2026, 3, 4, 20),
          scheduledFor: DateTime(2026, 3, 4, 18),
        ),
      ]);

      expect(collapsed.single.scheduledFor, DateTime(2026, 3, 4, 18));
    });

    test('is idempotent, which is what lets a re-pull be free', () {
      final once = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'aaa', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
        nudge(
          id: 'zzz',
          expectedOccasionAt: DateTime(2026, 3, 4, 20),
          sent: true,
        ),
      ]);
      final twice = collapseDuplicateOccasions(once);

      expect(twice, hasLength(1));
      expect(twice.single.id, once.single.id);
      expect(twice.single.sent, once.single.sent);
    });

    test('comes back oldest first', () {
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'later', expectedOccasionAt: DateTime(2026, 3, 6, 19)),
        nudge(id: 'earlier', expectedOccasionAt: DateTime(2026, 3, 4, 19)),
        nudge(id: 'middle', expectedOccasionAt: DateTime(2026, 3, 5, 19)),
      ]);

      expect(collapsed.map((row) => row.id), <String>[
        'earlier',
        'middle',
        'later',
      ]);
    });

    test('three devices collapse as readily as two', () {
      final collapsed = collapseDuplicateOccasions(<NudgeRecord>[
        nudge(id: 'aaa', expectedOccasionAt: DateTime(2026, 3, 4, 7)),
        nudge(
          id: 'mmm',
          expectedOccasionAt: DateTime(2026, 3, 4, 13),
          confirmed: true,
        ),
        nudge(
          id: 'zzz',
          expectedOccasionAt: DateTime(2026, 3, 4, 21),
          sent: true,
        ),
      ]);

      expect(collapsed, hasLength(1));
      expect(collapsed.single.id, 'aaa');
      expect(collapsed.single.sent, isTrue);
      expect(collapsed.single.confirmed, isTrue);
    });
  });
}
