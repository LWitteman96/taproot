import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/reflection/domain/check_in_scheduler.dart';
import 'package:taproot/features/reflection/domain/chip_surfacing.dart';
import 'package:taproot/features/reflection/domain/cue_families.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';
import 'package:taproot/features/reflection/domain/friction_surfacing.dart';
import 'package:taproot/features/reflection/domain/occasion_detection.dart';
import 'package:taproot/features/reflection/domain/remembered_chips.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';

/// A check-in the app is ready to show: what to ask, about what, with what to
/// tap.
@immutable
class CheckInOffer {
  const CheckInOffer({
    required this.habit,
    required this.candidate,
    required this.cueChips,
    required this.frictionChips,
    required this.isFirstReflection,
    this.lastCheckInAnywhere,
  });

  final Habit habit;
  final CheckInCandidate candidate;

  /// The cue chips to offer, pinned cue first where there is one. Empty for a
  /// Diagnosis, which asks about friction instead.
  final List<StarterChip> cueChips;

  final List<FrictionChip> frictionChips;

  /// Whether this is the habit's first *cue-bearing* reflection — the one the
  /// starter library exists for. A `skip` or a `Can't remember` is a row but
  /// not an answer to offer back, so neither ends the first.
  final bool isFirstReflection;

  /// The newest reflection across every habit at the moment this offer was
  /// assembled — the app-wide once-a-day gate's input, carried so that
  /// [CheckInAssembler.reverify] can re-apply the gate without re-reading
  /// every habit.
  final DateTime? lastCheckInAnywhere;

  Framing get framing => candidate.framing;

  Occasion get occasion => candidate.occasion.occasion;

  bool get isDiagnosis => framing == Framing.diagnosis;
}

/// Assembles the evening check-in from the store.
///
/// The decisions all live in `domain/` as pure functions; this is the part that
/// has to talk to four repositories, and it is deliberately the only part that
/// does. It holds **no state between calls**: notification answers are written
/// by a background isolate, so a `confirmed` nudge row can land without the main
/// isolate observing the write, and a remembered ledger would be wrong exactly
/// when it mattered.
class CheckInAssembler {
  const CheckInAssembler({
    required HabitRepository habits,
    required HabitInputsLoader loader,
    required DateTime Function() clock,
  }) : _habits = habits,
       _loader = loader,
       _clock = clock;

  final HabitRepository _habits;
  final HabitInputsLoader _loader;
  final DateTime Function() _clock;

  /// The one check-in to offer now, or null — which is the usual answer.
  Future<CheckInOffer?> nextCheckIn() async {
    final now = _clock();
    final habits = await _habits.allHabits();

    // A paused habit is not asked about. Paused days are excluded from every
    // engine window because they are not misses, and diagnosing someone for a
    // day they told us about would be the app not listening.
    final active = habits.where((habit) => !habit.isPaused).toList();

    // The per-habit loads are independent I/O and are awaited together. Done in
    // sequence this is N round trips before the first score is computed, and it
    // is the latency both the garden invitation and the check-in screen wait
    // on. `loadFor` rather than `load`: the habit row is already in hand, and
    // `load` would re-fetch every one of them by id.
    final loaded = await Future.wait(
      active.map((habit) => _loader.loadFor(habit)),
    );

    final contexts = <HabitCheckInContext>[];
    final byId = <String, (Habit, List<Reflection>)>{};
    DateTime? lastCheckInAnywhere;

    for (final (index, habit) in active.indexed) {
      final inputs = loaded[index];

      final (context, lastPromptedAt) = _contextFor(
        habit: habit,
        inputs: inputs,
        now: now,
      );

      if (lastPromptedAt != null &&
          (lastCheckInAnywhere == null ||
              lastPromptedAt.isAfter(lastCheckInAnywhere))) {
        lastCheckInAnywhere = lastPromptedAt;
      }

      contexts.add(context);
      byId[habit.id] = (habit, inputs.reflections);
    }

    final candidate = selectCheckIn(
      habits: contexts,
      now: now,
      lastCheckInAnywhere: lastCheckInAnywhere,
    );
    if (candidate == null) return null;

    final (habit, reflections) = byId[candidate.habitId]!;
    return _offerFor(
      habit: habit,
      reflections: reflections,
      candidate: candidate,
      lastCheckInAnywhere: lastCheckInAnywhere,
    );
  }

  /// Re-checks an offer the garden already assembled, reading **one** habit.
  ///
  /// The screen cannot simply show what the garden handed it. Notification
  /// answers are written by a background isolate, so a `confirmed` row can land
  /// between the garden rendering the invitation and the user tapping it, and
  /// the question has to be composed against the ledger as it is now. What it
  /// does not need is the whole ranking again: the garden already answered
  /// *which* habit, and re-reading four ledgers per habit and replaying the
  /// growth ladder for all of them to re-elect the same winner is the same
  /// expensive assembly run twice, seconds apart, with the user watching a
  /// spinner for the second one.
  ///
  /// So this re-reads the winner and re-applies every gate to it — the occasion
  /// may have changed, the weekly budget may have moved, the priority may have
  /// dropped below threshold — and returns null if it no longer holds, which
  /// sends the screen to its "nothing to ask" state exactly as a fresh
  /// assembly would.
  ///
  /// The one thing it inherits rather than recomputes is [
  /// CheckInOffer.lastCheckInAnywhere], the app-wide daily gate. Refreshed with
  /// this habit's own newest reflection, it is only stale if *another* habit
  /// was answered in the seconds between the tap and this call — which can only
  /// happen from this screen, for a different habit, in that window.
  Future<CheckInOffer?> reverify(CheckInOffer offer) async {
    final now = _clock();
    final habit = await _habits.habitById(offer.habit.id);
    if (habit == null || habit.isPaused) return null;

    final inputs = await _loader.loadFor(habit);
    final (context, lastPromptedAt) = _contextFor(
      habit: habit,
      inputs: inputs,
      now: now,
    );

    final lastCheckInAnywhere = switch ((
      offer.lastCheckInAnywhere,
      lastPromptedAt,
    )) {
      (null, final latest) => latest,
      (final carried?, null) => carried,
      (final carried?, final latest?) =>
        latest.isAfter(carried) ? latest : carried,
    };

    final candidate = selectCheckIn(
      habits: <HabitCheckInContext>[context],
      now: now,
      lastCheckInAnywhere: lastCheckInAnywhere,
    );
    if (candidate == null) return null;

    return _offerFor(
      habit: habit,
      reflections: inputs.reflections,
      candidate: candidate,
      lastCheckInAnywhere: lastCheckInAnywhere,
    );
  }

  /// The question, the chips, and the habit they are about.
  CheckInOffer _offerFor({
    required Habit habit,
    required List<Reflection> reflections,
    required CheckInCandidate candidate,
    required DateTime? lastCheckInAnywhere,
  }) {
    final first = isFirstReflection(reflections);

    return CheckInOffer(
      habit: habit,
      candidate: candidate,
      isFirstReflection: first,
      lastCheckInAnywhere: lastCheckInAnywhere,
      frictionChips: candidate.framing == Framing.diagnosis
          ? surfaceFrictionChips(habit.category)
          : const <FrictionChip>[],
      cueChips: candidate.framing == Framing.diagnosis
          ? const <StarterChip>[]
          : _cueChipsFor(
              habit: habit,
              reflections: reflections,
              isFirst: first,
              loggedAt: candidate.occasion.at,
            ),
    );
  }

  /// One habit's scoring context, plus the newest reflection it carries.
  ///
  /// The second half of the record is returned rather than recomputed by the
  /// caller: the same fold answers both "when was this habit last asked" and
  /// "when was anything last asked", and reflection history grows without
  /// bound, so walking it twice for one maximum is a cost that scales with how
  /// long the user has been here.
  (HabitCheckInContext, DateTime?) _contextFor({
    required Habit habit,
    required HabitInputs inputs,
    required DateTime now,
  }) {
    final growth = evaluateGrowth(inputs: inputs, at: now);
    final reflections = inputs.reflections;

    DateTime? lastPromptedAt;
    for (final reflection in reflections) {
      if (lastPromptedAt == null ||
          reflection.createdAt.isAfter(lastPromptedAt)) {
        lastPromptedAt = reflection.createdAt;
      }
    }

    return (
      HabitCheckInContext(
        habitId: habit.id,
        stage: growth.stage,
        convergence: growth.roots.convergence,
        reflectionCount: reflections.length,
        promptsThisWeek: promptsInTheLastWeek(
          reflections: reflections,
          at: now,
        ),
        occasion: occasionFor(
          habitId: habit.id,
          completions: inputs.completions,
          // The sanctioned filter, and the one the engine uses. A planning
          // pass records the whole horizon at once, so the raw list holds
          // occasions up to a week out; `occasionFor` guards against them too,
          // but reading the ledger the same way the engine does keeps one
          // definition of "an occasion that has happened".
          nudges: inputs.nudgesUpTo(now),
          reflections: reflections,
          targetFrequency: habit.targetFrequency,
          at: now,
        ),
        lastPromptedAt: lastPromptedAt,
      ),
      lastPromptedAt,
    );
  }

  /// The chips for a cue question.
  ///
  /// The first reflection is the only one with no history to rank, so it is the
  /// only one the starter library answers. Everything after it offers the
  /// user's own past answers back (§4) — which is what makes tapping rather
  /// than typing sustainable.
  ///
  /// **Whichever branch runs, the check-in comes back with something to tap.**
  /// The two branches used to disagree about what a reflection is: "first" was
  /// *no rows at all*, while the remembered pool counts only cue-bearing ones,
  /// so a single `skip` — or a first `Can't remember`, which §4 calls a
  /// first-class answer — put a habit in the returning branch with an empty
  /// pool and no pinned cue, and left it there permanently, since only a typed
  /// answer could ever seed the pool again. [isFirstReflection] now asks the
  /// same question the pool does.
  List<StarterChip> _cueChipsFor({
    required Habit habit,
    required List<Reflection> reflections,
    required bool isFirst,
    required DateTime loggedAt,
  }) {
    final family = familyForCueText(
      habit.designedCue,
      category: habit.category,
    );
    final pinned = pinnedDesignedCue(
      designedCue: habit.designedCue,
      designedCueType: habit.designedCueType,
      family: family ?? 'designed-cue',
    );

    if (!isFirst) {
      final remembered = rememberedCues(reflections: reflections);
      // The pinned cue leads here too, unless the user has already said it
      // back — Validation is one tap (§0) on the tenth check-in as much as on
      // the first, and the designed cue is the answer the question names.
      final saidAlready = remembered
          .map((cue) => cue.label.toLowerCase())
          .toSet();
      return <StarterChip>[
        if (pinned != null && !saidAlready.contains(pinned.label.toLowerCase()))
          pinned,
        for (final cue in remembered)
          StarterChip(cue.label, cue.cueType, 1, cue.label),
      ];
    }

    // The daypart comes from the **completion**, not from now. The evening
    // check-in asking about a 07:00 run has to rank against 07:00, or every
    // morning habit gets evening chips.
    final starters = surfaceStarterChips(
      category: habit.category,
      logged: daypartFor(loggedAt),
      // The journey is the habit's, not the keyword table's. A designed cue
      // the table cannot place still means Journey B; it just means filter
      // §5.2.2 has nothing to match on.
      hasDesignedCue: habit.designedCue?.trim().isNotEmpty ?? false,
      designedCueFamily: family,
    );

    return <StarterChip>[
      if (pinned != null) pinned,
      for (final scored in starters.chips) scored.chip,
    ];
  }
}
