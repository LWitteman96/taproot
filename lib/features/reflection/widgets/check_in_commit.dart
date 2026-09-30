import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/domain/check_in_question.dart';
import 'package:taproot/features/reflection/domain/commit_target.dart';
import 'package:taproot/features/reflection/widgets/check_in_chip.dart';

/// Step 2: commit to tomorrow.
///
/// The look-forward half of reflection-logic §1, and the reason reflection and
/// the next-day nudge are one flow rather than two: you learn what cued you,
/// then you deploy it on tomorrow, and the cue phrase gets rehearsed twice on
/// one screen.
///
/// The answer goes to the **nudge ledger**, not onto the `Reflection`. It is an
/// answer about a future occasion, and the ledger is what the engine reads for
/// autonomy and day-of-week preference.
class CheckInCommit extends ConsumerStatefulWidget {
  const CheckInCommit({
    required this.habit,
    required this.framing,
    required this.target,
    required this.ticker,
    required this.onCommitted,
    super.key,
  });

  final Habit habit;
  final Framing framing;
  final CommitTarget target;
  final GardenTicker ticker;

  /// [declined] is carried through because the done state says something
  /// different about a different day.
  final void Function({required bool declined}) onCommitted;

  static const String yesLabel = 'Yes';
  static const String differentDayLabel = 'Different day';

  @override
  ConsumerState<CheckInCommit> createState() => _CheckInCommitState();
}

class _CheckInCommitState extends ConsumerState<CheckInCommit> {
  String? _held;
  bool _saving = false;

  Future<void> _answer(String label, {required bool declined}) async {
    if (_saving) return;
    setState(() {
      _held = label;
      _saving = true;
    });
    final nudges = ref.read(nudgeServiceProvider);
    final id = widget.target.nudge.id;
    if (declined) {
      await nudges.markDeclined(id);
    } else {
      await nudges.markConfirmed(id);
    }
    if (!mounted) return;
    if (!widget.ticker.isStill) {
      await Future<void>.delayed(CheckInChip.selectionHold);
    }
    if (mounted) widget.onCommitted(declined: declined);
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          commitFact(nextOccasionAt: widget.target.at, now: now),
          style: TextStyle(
            fontFamily: 'Karla',
            fontSize: 15,
            color: GardenColors.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          commitQuestion(habit: widget.habit, framing: widget.framing),
          style: const TextStyle(
            fontFamily: 'Newsreader',
            fontSize: 27,
            height: 1.15,
            letterSpacing: -0.27,
            color: GardenColors.ink,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CheckInChip(
              label: CheckInCommit.yesLabel,
              isPinned: true,
              isSelected: _held == CheckInCommit.yesLabel,
              ticker: widget.ticker,
              onPressed: _saving
                  ? null
                  : () => _answer(CheckInCommit.yesLabel, declined: false),
            ),
            CheckInChip(
              label: CheckInCommit.differentDayLabel,
              isSelected: _held == CheckInCommit.differentDayLabel,
              ticker: widget.ticker,
              // A decline is not a failure, it is data: day-of-week preference
              // falls out of these within a fortnight (growth-engine §8).
              //
              // Later feature: the prototype opens a `Which day?` picker here.
              // v1 records `declined` only — the picker needs a one-off
              // reschedule in the notification planner and a ledger field for
              // the chosen day (check-in-design §4.3).
              onPressed: _saving
                  ? null
                  : () => _answer(
                      CheckInCommit.differentDayLabel,
                      declined: true,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
