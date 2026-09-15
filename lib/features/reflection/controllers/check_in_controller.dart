import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';

/// Where the check-in is.
enum CheckInStatus {
  /// Still working out whether there is anything to ask.
  looking,

  /// Nothing to ask — the usual answer, and not a failure.
  nothingToAsk,

  /// A question is on screen.
  asking,

  /// Answered and written down.
  answered,

  /// The question could not be assembled or the answer could not be saved.
  failed,
}

@immutable
class CheckInState {
  const CheckInState({
    this.status = CheckInStatus.looking,
    this.offer,
    this.isSaving = false,
    this.errorMessage,
  });

  final CheckInStatus status;
  final CheckInOffer? offer;
  final bool isSaving;
  final String? errorMessage;

  CheckInState copyWith({
    CheckInStatus? status,
    CheckInOffer? Function()? offer,
    bool? isSaving,
    String? Function()? errorMessage,
  }) => CheckInState(
    status: status ?? this.status,
    offer: offer != null ? offer() : this.offer,
    isSaving: isSaving ?? this.isSaving,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );
}

/// The evening check-in: one question, one tap, written down.
class CheckInController extends Notifier<CheckInState> {
  late final CheckInAssembler _assembler;
  late final String Function() _newId;
  late final DateTime Function() _clock;

  @override
  CheckInState build() {
    _assembler = ref.read(checkInAssemblerProvider);
    _newId = ref.read(newIdProvider);
    _clock = ref.read(clockProvider);

    // Kicked off rather than awaited: `build` is synchronous, and the screen
    // renders its looking state and fills in.
    Future<void>.microtask(load);
    return const CheckInState();
  }

  void _log(String action, String message) =>
      dev.log(message, name: 'CheckInController.$action');

  /// Works out whether there is a question worth asking.
  Future<void> load() async {
    state = state.copyWith(
      status: CheckInStatus.looking,
      errorMessage: () => null,
    );
    try {
      final offer = await _assembler.nextCheckIn();
      if (!ref.mounted) return;
      state = state.copyWith(
        status: offer == null
            ? CheckInStatus.nothingToAsk
            : CheckInStatus.asking,
        offer: () => offer,
      );
    } catch (error, stackTrace) {
      _log('load', 'could not assemble a check-in: $error');
      await Sentry.captureException(error, stackTrace: stackTrace);
      if (!ref.mounted) return;
      state = state.copyWith(
        status: CheckInStatus.failed,
        errorMessage: () =>
            'We could not put a question together just now. Nothing is lost.',
      );
    }
  }

  /// The user tapped one of the cue chips.
  Future<void> answerWithCue(StarterChip chip) => _record(
    inputMode: InputMode.chip,
    cueReported: chip.label,
    cueType: chip.cueType,
  );

  /// The user typed their own cue. `Something else` is the exception, not the
  /// default (design-spec §3).
  Future<void> answerWithTypedCue(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _record(
      inputMode: InputMode.typed,
      cueReported: trimmed,
      // The user's own words carry no type until they tell us or the app
      // infers one. `unknown` is honest, and is deliberately *not* treated as
      // an internal state by convergence.
      cueType: CueType.unknown,
    );
  }

  /// The user tapped a friction chip on a Diagnosis.
  Future<void> answerWithFriction(FrictionChip chip) => _record(
    inputMode: InputMode.chip,
    frictionReported: chip.label,
    frictionType: chip.frictionType,
  );

  /// The user typed their own friction.
  ///
  /// The type is left null rather than guessed. Friction *type* is what the
  /// §6 routing keys off — forgetting is a cue failure, reluctance is a reward
  /// failure, and they have opposite fixes — so mapping free text to one of
  /// them on a keyword would route real users to the wrong intervention. An
  /// untyped friction is honest, and the text is kept for when there is a
  /// mapping worth trusting.
  Future<void> answerWithTypedFriction(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _record(inputMode: InputMode.typed, frictionReported: trimmed);
  }

  /// A first-class answer, not a gap (reflection-logic §4).
  ///
  /// A rising can't-remember rate is itself the signal that a habit is running
  /// on autopilot without awareness — a tall plant on shallow roots, exactly as
  /// the metaphor promises.
  Future<void> cantRemember() => _record(inputMode: InputMode.cantRemember);

  /// The user closed the check-in without answering.
  Future<void> skip() => _record(inputMode: InputMode.skipped);

  Future<void> _record({
    required InputMode inputMode,
    String? cueReported,
    CueType cueType = CueType.unknown,
    String? frictionReported,
    FrictionType? frictionType,
  }) async {
    final offer = state.offer;
    if (offer == null || state.isSaving) return;

    state = state.copyWith(isSaving: true, errorMessage: () => null);

    final designedCue = offer.habit.designedCue?.trim().toLowerCase();
    final reflection = Reflection(
      id: _newId(),
      habitId: offer.habit.id,
      createdAt: _clock(),
      occasion: offer.occasion,
      framing: offer.framing,
      inputMode: inputMode,
      cueReported: cueReported,
      cueType: cueType,
      // Null rather than false when there is nothing to match against: the
      // share of true across validations is the cue-reliability number the
      // cue-testing phase shows, and a habit with no designed cue must not
      // drag it down.
      matchedDesignedCue: designedCue == null || cueReported == null
          ? null
          : cueReported.trim().toLowerCase() == designedCue,
      frictionReported: frictionReported,
      frictionType: frictionType,
      wasNudged: offer.candidate.occasion.wasNudged,
    );

    try {
      await ref.read(reflectionServiceProvider).saveReflection(reflection);
      _log('record', '${offer.habit.id}: ${inputMode.name}');
      if (!ref.mounted) return;
      state = state.copyWith(status: CheckInStatus.answered, isSaving: false);
    } catch (error, stackTrace) {
      _log('record', 'could not save: $error');
      await Sentry.captureException(error, stackTrace: stackTrace);
      if (!ref.mounted) return;
      state = state.copyWith(
        isSaving: false,
        errorMessage: () => 'That did not save. Try again in a moment.',
      );
    }
  }
}

final checkInControllerProvider =
    NotifierProvider.autoDispose<CheckInController, CheckInState>(
      CheckInController.new,
    );
