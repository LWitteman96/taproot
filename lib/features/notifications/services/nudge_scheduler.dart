import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'package:taproot/core/engine/autonomy.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_decision.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';

/// What one planning pass did, per occasion.
@immutable
class PlannedOccasion {
  const PlannedOccasion({
    required this.nudgeId,
    required this.habitId,
    required this.occasion,
    required this.decision,
    required this.isNew,
  });

  final String nudgeId;
  final String habitId;
  final ExpectedOccasion occasion;
  final NudgeDecision decision;

  /// False when the row was already in the ledger and this pass left it alone.
  final bool isNew;

  @override
  String toString() =>
      'PlannedOccasion(${occasion.date}, $decision, new: $isNew)';
}

/// The outcome of a planning pass, for logging and for tests.
@immutable
class NudgePlan {
  const NudgePlan({required this.access, required this.occasions});

  final NotificationAccess access;
  final List<PlannedOccasion> occasions;

  Iterable<PlannedOccasion> get scheduled =>
      occasions.where((occasion) => occasion.decision.shouldSend);

  /// Occasions the engine deliberately stayed silent on — autonomy's
  /// denominator, and the only silence that means anything.
  Iterable<PlannedOccasion> get withheld =>
      occasions.where((occasion) => occasion.decision.isDeliberateSilence);

  Iterable<PlannedOccasion> suppressedBy(NudgeSuppression reason) =>
      occasions.where((occasion) => occasion.decision.suppression == reason);

  @override
  String toString() =>
      'NudgePlan(${occasions.length} occasions, '
      '${scheduled.length} scheduled, ${withheld.length} withheld)';
}

/// Plans expected occasions, writes the ledger, and queues the notifications.
///
/// **The invariant this class exists for: every expected occasion gets a
/// ledger row, including — especially — the ones deliberately left silent.**
/// Autonomy is completions on un-nudged occasions over un-nudged occasions
/// (growth spec §6), so the silent occasions *are* the denominator. They
/// cannot be inferred later from the absence of a notification, because the
/// absence of a notification is indistinguishable from the absence of an
/// occasion. If this class ever schedules a nudge without writing a row, or
/// stays silent without writing a row, the measurement is gone and nothing
/// visibly breaks.
///
/// It is re-run on launch and after every completion. Passes are idempotent:
/// an occasion already in the ledger keeps its row, its id and its recorded
/// outcome, and only dates with no row are decided afresh.
class NudgeScheduler {
  NudgeScheduler({
    required HabitRepository habits,
    required NudgeRepository nudges,
    required HabitInputsLoader inputs,
    required NotificationGateway gateway,
    ReflectionPromptComposer reflection = const NoReflectionPrompt(),
    DateTime Function()? clock,
    String Function()? newId,
  }) : _habits = habits,
       _nudges = nudges,
       _inputs = inputs,
       _gateway = gateway,
       _reflection = reflection,
       _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  static final Logger _log = Logger('NudgeScheduler');

  final HabitRepository _habits;
  final NudgeRepository _nudges;
  final HabitInputsLoader _inputs;
  final NotificationGateway _gateway;
  final ReflectionPromptComposer _reflection;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Re-plans every live habit.
  ///
  /// The cap is applied across habits rather than per habit, so five habits
  /// cannot quietly queue five times the ceiling. Habits are planned in
  /// creation order, which means an overflow always drops the *newest* habit's
  /// furthest-out nudges — deterministic, and reported rather than silent.
  Future<NudgePlan> planAll() async {
    final access = await _gateway.currentAccess();
    final habits = await _habits.allHabits();
    final pending = access.canPost
        ? await _gateway.pendingNotificationIds()
        : const <int>{};

    final planned = <PlannedOccasion>[];
    var queued = pending.length;

    for (final habit in habits) {
      final forHabit = await _planHabit(
        habit: habit,
        access: access,
        pending: pending,
        queuedSoFar: queued,
      );
      planned.addAll(forHabit);
      queued += forHabit
          .where((occasion) => occasion.decision.shouldSend)
          .length;
    }

    final plan = NudgePlan(access: access, occasions: planned);
    final overCap = plan.suppressedBy(NudgeSuppression.overCap).length;
    if (overCap > 0) {
      _log.warning(
        '$overCap occasion(s) recorded without a notification: the '
        '${EngineConstants.maximumPendingNudges} pending-notification ceiling '
        'was reached. They are in the ledger as un-nudged.',
      );
    }
    _log.info('$plan');
    return plan;
  }

  /// Re-plans one habit. Called after a completion, when the stage — and so
  /// the fade rate — may just have changed.
  Future<NudgePlan> planHabit(String habitId) async {
    final habit = await _habits.habitById(habitId);
    if (habit == null) {
      return const NudgePlan(
        access: NotificationAccess.denied,
        occasions: <PlannedOccasion>[],
      );
    }

    final access = await _gateway.currentAccess();
    final pending = access.canPost
        ? await _gateway.pendingNotificationIds()
        : const <int>{};
    return NudgePlan(
      access: access,
      occasions: await _planHabit(
        habit: habit,
        access: access,
        pending: pending,
        queuedSoFar: pending.length,
      ),
    );
  }

  Future<List<PlannedOccasion>> _planHabit({
    required Habit habit,
    required NotificationAccess access,
    required Set<int> pending,
    required int queuedSoFar,
  }) async {
    // A paused habit expects nothing. Writing occasions through a pause would
    // put days the engine has agreed not to count into the denominator the
    // engine measures autonomy over.
    if (habit.isPaused) return const <PlannedOccasion>[];

    final inputs = await _inputs.load(habit.id);
    if (inputs == null) return const <PlannedOccasion>[];

    final now = _clock();
    final today = LocalDate.from(now);
    final stage = evaluateGrowth(inputs: inputs, at: now).stage;
    final rate = nudgeRateForStage(stage);

    final existing = <LocalDate, NudgeRecord>{
      for (final nudge in inputs.nudges)
        LocalDate.from(nudge.expectedOccasionAt): nudge,
    };

    final windowStart = today.addDays(-EngineConstants.nudgeBackfillDays);
    final occasions = expectedOccasionsBetween(
      createdAt: habit.createdAt,
      targetFrequency: habit.targetFrequency,
      from: windowStart,
      to: today.addDays(EngineConstants.nudgeHorizonDays),
      pauses: inputs.pauses,
    );

    // The fade rule reads the whole history, not the window being planned: the
    // sent share it steers is a property of the habit's life, which is what
    // makes it self-correcting when the stage — and the rate — changes.
    //
    // Seeded from the rows *before* the window and then advanced occasion by
    // occasion through it, so every decision sees the share as it stood at
    // that occasion. Counting only rows in the past instead would have left
    // every occasion in one horizon deciding against the same numbers — so a
    // pass handed out seven sends or seven silences in a row, and the rate was
    // only honoured between passes rather than across occasions.
    var priorOccasions = 0;
    var priorSent = 0;
    for (final nudge in inputs.nudges) {
      if (!LocalDate.from(nudge.expectedOccasionAt).isBefore(windowStart)) {
        continue;
      }
      priorOccasions++;
      if (nudge.sent) priorSent++;
    }

    final planned = <PlannedOccasion>[];
    var queued = queuedSoFar;

    for (final occasion in occasions) {
      final known = existing[occasion.date];
      if (known != null) {
        // Already decided. Re-deciding would let a row flip from silent to
        // nudged (or back) after the fact, and the ledger is a record of what
        // happened, not of what the current stage would do.
        //
        // What *is* re-done is the queueing: a row that says a nudge was sent,
        // for an occasion still ahead, with nothing pending at its id, is a
        // notification the OS lost — a reinstall, a restore, a cleared alarm
        // table. Left alone it would be a nudge the ledger claims and the user
        // never gets, which is the one direction that corrupts the
        // measurement rather than just missing a reminder.
        if (known.sent &&
            access.canPost &&
            queued < EngineConstants.maximumPendingNudges &&
            !pending.contains(notificationIdFor(known.id)) &&
            nudgeDeliveryTime(occasion).isAfter(now)) {
          final requeued = await _queue(
            habit: habit,
            occasion: occasion,
            nudgeId: known.id,
            deliverAt: nudgeDeliveryTime(occasion),
          );
          if (requeued) queued++;
        }

        priorOccasions++;
        if (known.sent) priorSent++;
        planned.add(
          PlannedOccasion(
            nudgeId: known.id,
            habitId: habit.id,
            occasion: occasion,
            decision: known.sent
                ? const NudgeDecision.send()
                : const NudgeDecision.suppress(NudgeSuppression.withheld),
            isNew: false,
          ),
        );
        continue;
      }

      final deliverAt = nudgeDeliveryTime(occasion);
      final decision = _decide(
        rate: rate,
        priorOccasions: priorOccasions,
        priorSent: priorSent,
        deliverAt: deliverAt,
        now: now,
        access: access,
        queued: queued,
      );

      final nudgeId = _newId();
      // The row goes in **before** the notification is queued and regardless
      // of what was decided. A crash between the two leaves an occasion the
      // ledger honestly calls un-nudged; the other order leaves an occasion
      // nobody recorded, which is the failure that cannot be detected.
      await _nudges.saveNudge(
        NudgeRecord(
          id: nudgeId,
          habitId: habit.id,
          expectedOccasionAt: occasion.date.startOfDay,
          sent: false,
          scheduledFor: decision.shouldSend ? deliverAt : null,
        ),
      );

      var sent = false;
      if (decision.shouldSend) {
        sent = await _queue(
          habit: habit,
          occasion: occasion,
          nudgeId: nudgeId,
          deliverAt: deliverAt,
        );
        if (sent) {
          await _nudges.markSent(nudgeId);
          queued++;
        }
      }

      planned.add(
        PlannedOccasion(
          nudgeId: nudgeId,
          habitId: habit.id,
          occasion: occasion,
          decision: decision.shouldSend && !sent
              ? const NudgeDecision.suppress(NudgeSuppression.deliveryPassed)
              : decision,
          isNew: true,
        ),
      );

      priorOccasions++;
      if (sent) priorSent++;
    }

    return planned;
  }

  NudgeDecision _decide({
    required double rate,
    required int priorOccasions,
    required int priorSent,
    required DateTime deliverAt,
    required DateTime now,
    required NotificationAccess access,
    required int queued,
  }) {
    // The fade decision is made first, and made unconditionally. Deciding
    // "would we nudge?" only when we *can* nudge would make the sent share
    // depend on permission state, so a user who declined notifications and
    // later granted them would resume mid-pattern at the wrong rate.
    final wouldSend = shouldSendNudge(
      nudgeRate: rate,
      priorOccasions: priorOccasions,
      priorSent: priorSent,
    );
    if (!wouldSend) {
      return const NudgeDecision.suppress(NudgeSuppression.withheld);
    }
    if (!deliverAt.isAfter(now)) {
      return const NudgeDecision.suppress(NudgeSuppression.deliveryPassed);
    }
    if (!access.canPost) {
      return const NudgeDecision.suppress(NudgeSuppression.noPermission);
    }
    if (queued >= EngineConstants.maximumPendingNudges) {
      return const NudgeDecision.suppress(NudgeSuppression.overCap);
    }
    return const NudgeDecision.send();
  }

  /// Queues one notification. False when the platform refused it — the row
  /// stays un-sent, which is the honest record.
  Future<bool> _queue({
    required Habit habit,
    required ExpectedOccasion occasion,
    required String nudgeId,
    required DateTime deliverAt,
  }) async {
    try {
      final prompt = await _reflection.promptFor(
        habit: habit,
        occasion: occasion,
        deliverAt: deliverAt,
      );
      await _gateway.schedule(
        ScheduledNudge(
          notificationId: notificationIdFor(nudgeId),
          payload: NudgePayload(nudgeId: nudgeId, habitId: habit.id),
          checkIn: composeEveningCheckIn(
            habit: habit,
            occasion: occasion,
            reflectionPrompt: prompt,
          ),
          deliverAt: deliverAt,
        ),
      );
      return true;
    } catch (error, stackTrace) {
      // Not rethrown: a platform that will not queue one notification must not
      // abort the pass, or one bad occasion costs every later habit its
      // ledger rows. The occasion is already recorded as un-nudged.
      _log.warning('could not queue nudge $nudgeId', error, stackTrace);
      return false;
    }
  }
}

/// A stable 31-bit notification id for a ledger row.
///
/// The platforms key notifications by `int`, the ledger keys occasions by
/// UUID, and re-planning has to be able to *replace* a pending notification
/// rather than duplicate it — so the mapping has to be a pure function of the
/// row id rather than a counter.
int notificationIdFor(String nudgeId) => nudgeId.hashCode & 0x7fffffff;
