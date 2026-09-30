import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/garden/providers/plant_art_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/controllers/check_in_controller.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';
import 'package:taproot/features/reflection/domain/commit_target.dart';
import 'package:taproot/features/reflection/widgets/check_in_commit.dart';
import 'package:taproot/features/reflection/widgets/check_in_done.dart';
import 'package:taproot/features/reflection/widgets/check_in_look_back.dart';
import 'package:taproot/features/reflection/widgets/check_in_sheet.dart';

/// The check-in sheet, and the state that decides what is inside it.
///
/// Sits on the garden (see `GardenPage`) rather than owning a screen, so the
/// roots of the habit being reflected on are visible behind it — which is the
/// reason the check-in is a sheet at all (check-in-design §1).
class CheckInSheetHost extends ConsumerStatefulWidget {
  const CheckInSheetHost({
    required this.entry,
    required this.ticker,
    super.key,
  });

  /// How the sheet was opened: the garden's already-assembled offer, or the
  /// user asking about one habit after watering it. See [CheckInEntry].
  ///
  /// Null on a deep link or a cold start on `/check-in`, and then the whole
  /// assembly runs.
  final CheckInEntry? entry;

  /// The offer that came in with [entry], when one did.
  ///
  /// A requested check-in has none — the garden knew only that there was
  /// something to reflect on — so the sheet shows its spinner for as long as
  /// composing the question takes, exactly as the deep link already did.
  CheckInOffer? get offered => switch (entry) {
    OfferedCheckIn(:final offer) => offer,
    RequestedCheckIn() || null => null,
  };

  final GardenTicker ticker;

  /// The scrim over the garden while the sheet is asking. Fades to
  /// [scrimDone] when the answer lands, so the roots can be seen growing.
  ///
  /// OPEN — calibrated against dusk only (check-in-design §10, question 4).
  static const double scrimAsking = 0.25;
  static const double scrimDone = 0.10;

  static const String nothingHeadline = 'Nothing to ask today';
  static const String nothingBody =
      'Most days there is nothing worth asking. That is the idea — the garden '
      'is a place you visit, not a place that owes you a task.';
  static const String backLabel = 'Back to the garden';
  static const String failedHeadline = 'That question got away';
  static const String failedBody =
      'Nothing has been lost. This device could not put the question together '
      'just now — trying again usually gets it.';
  static const String retryLabel = 'Try again';

  @override
  ConsumerState<CheckInSheetHost> createState() => _CheckInSheetHostState();
}

/// Which part of the check-in is on screen.
enum _SheetStep { lookBack, commit, done }

class _CheckInSheetHostState extends ConsumerState<CheckInSheetHost> {
  _SheetStep _step = _SheetStep.lookBack;

  /// The occasion step 2 asks about, resolved when the answer lands. Null means
  /// there is nothing to commit to and the step is skipped entirely.
  CommitTarget? _commit;

  /// Whether the user asked for a different day, which the done state says
  /// something different about.
  bool _declined = false;

  @override
  void initState() {
    super.initState();
    // After the frame: `load` writes controller state, and doing that during
    // the build that is creating this widget rebuilds a provider mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Reset at the start rather than cleared on the way out: `dispose` runs
      // while the element is already deactivated, so reading the provider
      // container from it is unsafe — and "every check-in starts at the
      // beginning" is the same guarantee either way.
      ref.read(checkInIsDoneProvider.notifier).set(false);
      // Before the load, whenever the entry names the habit — which is both
      // ways in from the garden. Only a deep link has to wait.
      _holdRoots();
      await ref
          .read(checkInControllerProvider.notifier)
          .load(entry: widget.entry);
      if (!mounted) return;
      _holdRoots();
      await _previewCommitStep();
    });
  }

  /// Whether step 2 has anything to ask.
  ///
  /// Resolved when the sheet opens, so the meta row can promise `1 of 2` or
  /// `1 of 1` honestly *before* the answer lands — promising a second step and
  /// then not having one is worse than never promising it. Starts false so the
  /// first frame under-promises rather than over-promises.
  bool _hasCommitStep = false;

  /// Work out whether there will be a commit step, for the meta row.
  ///
  /// Deliberately separate from [_afterAnswer], which resolves it again: the
  /// answer takes time, and the notification's own Yes can land in between —
  /// which is one of the three cases §4.3 skips the step for.
  Future<void> _previewCommitStep() async {
    final offer = ref.read(checkInControllerProvider).offer ?? widget.offered;
    if (offer == null) return;
    final target = await _resolveCommitTarget(offer);
    if (mounted) setState(() => _hasCommitStep = target != null);
  }

  /// Pin the roots at what they were before the answer.
  ///
  /// The reflection is written on answer, so the engine's root depth moves
  /// straight away. Pinning here and releasing at done is what makes the growth
  /// land *with* the done state — which is the entire reason the check-in is a
  /// sheet over the garden rather than a page (check-in-design §7.2).
  ///
  /// Called twice — once before the question is composed and once after — and
  /// the first call is the one that matters. A requested check-in composes its
  /// question against the store, which takes a round trip the user is watching;
  /// pinning only afterwards would be fine today but is one refactor away from
  /// pinning after the write. The second call is for the deep link, which is
  /// the only way in that does not know the habit up front. Holding twice is
  /// not holding twice: the pin is keyed by habit, and nothing has moved the
  /// root depth in between.
  void _holdRoots() {
    if (_heldFor != null) return;
    final habitId =
        widget.entry?.habitId ??
        ref.read(checkInControllerProvider).offer?.habit.id;
    if (habitId == null) return;
    _heldFor = habitId;
    ref
        .read(heldRootDepthProvider.notifier)
        .hold(
          habitId: habitId,
          depth: ref.read(habitRootDepthProvider(habitId)) ?? 0,
        );
  }

  /// The habit whose roots are pinned, so the pin is taken once.
  String? _heldFor;

  /// Reach the done state: lift the scrim and let the roots grow.
  ///
  /// The garden is refreshed first. The reflection was written through the
  /// *check-in* controller, so the garden's engine state still predates it —
  /// releasing the pin without recomputing would grow the roots to exactly
  /// where they already were (check-in-design §8: "R after comes from the
  /// engine's recompute after the local write").
  Future<void> _toDone() async {
    setState(() => _step = _SheetStep.done);
    ref.read(checkInIsDoneProvider.notifier).set(true);
    await ref.read(gardenControllerProvider.notifier).refresh();
    if (!mounted) return;
    // Releasing the pin is the payoff. Rive eases the roots to their new depth
    // over 1.2s, and a Young or Mature plant straightens as its roots pass the
    // stage's threshold — all of it in the art, none of it drawn here.
    ref.read(heldRootDepthProvider.notifier).release();
  }

  /// How the look-back was answered, for the done state's wording.
  InputMode? _answeredWith;

  /// Decide where to go after the look-back answer.
  ///
  /// The commit target is resolved *here* rather than when the sheet opened,
  /// because answering takes time and the notification's own Yes can land in
  /// between — which is one of the three cases §4.3 skips the step for.
  Future<void> _afterAnswer(CheckInOffer offer, InputMode inputMode) async {
    _answeredWith = inputMode;
    final target = await _resolveCommitTarget(offer);
    if (!mounted) return;
    setState(() {
      _commit = target;
      _hasCommitStep = target != null;
    });
    if (target == null) {
      unawaited(_toDone());
    } else {
      setState(() => _step = _SheetStep.commit);
    }
  }

  Future<CommitTarget?> _resolveCommitTarget(CheckInOffer offer) async {
    try {
      final nudges = await ref
          .read(nudgeServiceProvider)
          .nudgesFor(offer.habit.id);
      return commitTargetFor(
        habit: offer.habit,
        nudges: nudges,
        pauses: const [],
        now: ref.read(clockProvider)(),
      );
    } catch (error, stackTrace) {
      // Not surfaced: the reflection is already written, and a ledger the app
      // could not read is not a reason to tell the user their answer failed.
      // Skipping the step is the same thing the rules do when there is nothing
      // to ask.
      dev.log(
        'could not resolve a commit target',
        name: 'CheckInSheetHost',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  void _close() {
    // `maybeOf`, because the sheet is a widget and not a route: it is built
    // inside the garden, and a test — or a future caller — can mount it
    // without a router above it. Closing is then simply not a thing it can do.
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (context.canPop()) {
      context.pop();
    } else {
      // Reached by deep link, so there is nothing to pop back to.
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkInControllerProvider);
    // The offer on screen is the verified one once it arrives, and the one the
    // garden handed over until then — so the sheet never flashes empty.
    final offer = state.offer ?? widget.offered;

    // Status first, offer second. "Nothing to ask" and "failed" have no offer
    // by definition, and reading the offer first put a spinner on both of them
    // that could never resolve.
    final child = switch (state.status) {
      CheckInStatus.nothingToAsk => CheckInMessage(
        headline: CheckInSheetHost.nothingHeadline,
        body: CheckInSheetHost.nothingBody,
        actionLabel: CheckInSheetHost.backLabel,
        onAction: _close,
      ),
      CheckInStatus.failed => CheckInMessage(
        headline: CheckInSheetHost.failedHeadline,
        body: state.errorMessage ?? CheckInSheetHost.failedBody,
        actionLabel: CheckInSheetHost.retryLabel,
        onAction: () => ref
            .read(checkInControllerProvider.notifier)
            .load(entry: widget.entry),
      ),
      // Only reachable on a deep link, before the assembly returns: with an
      // offer in hand there is something to ask straight away.
      CheckInStatus.looking when offer == null => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      CheckInStatus.looking ||
      CheckInStatus.asking ||
      CheckInStatus.answered => switch (_step) {
        _SheetStep.lookBack => CheckInLookBack(
          offer: offer!,
          ticker: widget.ticker,
          onAnswered: (inputMode) => _afterAnswer(offer, inputMode),
          // Closing *is* the acknowledgement for a skip: there is no step 2
          // and no done state to show (check-in-design §4.4).
          onSkipped: _close,
        ),
        // `_commit` cannot be null here — the step is only entered when one
        // was resolved — but the switch cannot know that, and a bang would be
        // a promise rather than a check.
        _SheetStep.commit => switch (_commit) {
          final commit? => CheckInCommit(
            habit: offer!.habit,
            framing: offer.candidate.framing,
            target: commit,
            ticker: widget.ticker,
            onCommitted: ({required bool declined}) {
              _declined = declined;
              unawaited(_toDone());
            },
          ),
          null => const SizedBox.shrink(),
        },
        _SheetStep.done => CheckInDone(
          habitId: offer!.habit.id,
          framing: offer.candidate.framing,
          inputMode: _answeredWith ?? InputMode.chip,
          ticker: widget.ticker,
          declined: _declined,
          commitDay: _commit == null
              ? null
              : commitDayLabel(
                  occasionAt: _commit!.at,
                  now: ref.read(clockProvider)(),
                ),
          // The one insight v1 fires: the habit's first completion nobody
          // asked for. Everything else in reflection-logic §6 needs an action
          // editor that does not exist, and §0.4 forbids an insight without
          // one.
          showAutonomyInsight:
              offer.candidate.occasion.occasion == Occasion.autonomyCompletion,
          onBack: _close,
        ),
      },
    };

    return CheckInSheet(
      habitName: offer?.habit.name ?? '',
      step: switch (_step) {
        // `1 of 1` when there is nothing to commit to: promising a second step
        // and then not having one is worse than never promising it.
        _SheetStep.lookBack => _hasCommitStep ? '1 of 2' : '1 of 1',
        _SheetStep.commit => '2 of 2',
        _SheetStep.done => 'done',
      },
      ticker: widget.ticker,
      child: child,
    );
  }
}

/// Whether the sheet has reached its done state.
///
/// Lifted out of the sheet so the garden behind it can react: the scrim lifts
/// when the answer lands, which is what lets the roots growing behind the sheet
/// actually be seen (check-in-design §3).
final checkInIsDoneProvider = NotifierProvider<CheckInIsDoneController, bool>(
  CheckInIsDoneController.new,
);

class CheckInIsDoneController extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: avoid_positional_boolean_parameters
  void set(bool value) => state = value;
}
