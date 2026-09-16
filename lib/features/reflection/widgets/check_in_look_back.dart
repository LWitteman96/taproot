import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/reflection/controllers/check_in_controller.dart';
import 'package:taproot/features/reflection/domain/check_in_question.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';
import 'package:taproot/features/reflection/widgets/check_in_chip.dart';

/// Step 1: look back.
///
/// Fact, question, chips, footer. The two yes/no framings ask first and expand
/// into the chip list only if the answer was no — reflection-logic §3 asks for
/// that specifically, and the built check-in used to show the full list
/// immediately, which made a Validation indistinguishable from a Discovery.
///
/// **The reflection is written as soon as it is answered**, not when the sheet
/// finishes (check-in-design §4.2). A user who swipes the sheet away after
/// answering keeps their answer.
class CheckInLookBack extends ConsumerStatefulWidget {
  const CheckInLookBack({
    required this.offer,
    required this.ticker,
    required this.onAnswered,
    required this.onSkipped,
    super.key,
  });

  final CheckInOffer offer;
  final GardenTicker ticker;

  /// The answer is written; the sheet should move to the commit step.
  final VoidCallback onAnswered;

  /// Recorded as skipped; the sheet should close.
  final VoidCallback onSkipped;

  static const String yesLabel = 'Yes';
  static const String validationNoLabel = 'No, something else';
  static const String confirmationNoLabel = 'Actually, no';
  static const String somethingElseLabel = 'Something else';
  static const String cantRememberLabel = "Can't remember";
  static const String skipLabel = 'Skip';
  static const String nextLabel = 'Next';
  static const String backLabel = 'Back';
  static const String saveLabel = 'Save';

  /// Whether reflection #1 is offered `Can't remember`.
  ///
  /// OPEN — starter-chip-library §9 has not settled it. Shown by default,
  /// behind this flag so it can be tested either way (check-in-design §5).
  static const bool allowCantRememberOnFirstReflection = true;

  static String typingPrompt(Framing framing) => framing == Framing.diagnosis
      ? 'What got in the way?'
      : 'What got you going?';

  static String typingPlaceholder(Framing framing) =>
      framing == Framing.diagnosis
      ? 'e.g. dentist ran over'
      : 'e.g. the dog woke me up';

  @override
  ConsumerState<CheckInLookBack> createState() => _CheckInLookBackState();
}

class _CheckInLookBackState extends ConsumerState<CheckInLookBack> {
  /// True once the user has said the designed cue was *not* what happened, so
  /// the chip list is showing. Only the yes/no framings have this stage.
  bool _expanded = false;
  bool _typing = false;

  /// What is showing as selected while the hold plays out.
  String? _held;

  final TextEditingController _typed = TextEditingController();

  bool get _isYesNo =>
      !_expanded &&
      (widget.offer.candidate.framing == Framing.validation ||
          widget.offer.candidate.framing == Framing.confirmation) &&
      widget.offer.habit.designedCue?.trim().isNotEmpty == true;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  /// Hold the selection, then advance.
  ///
  /// With motion off there is no auto-advance at all: the chip stays selected
  /// and a Next button appears, because a screen that moves on by itself is
  /// exactly what reduced motion is asking us not to do.
  Future<void> _answer(String label, Future<void> Function() write) async {
    setState(() => _held = label);
    await write();
    if (!mounted) return;
    if (widget.ticker.isStill) return;
    await Future<void>.delayed(CheckInChip.selectionHold);
    if (mounted) widget.onAnswered();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(checkInControllerProvider.notifier);
    final isSaving = ref.watch(
      checkInControllerProvider.select((state) => state.isSaving),
    );
    final now = ref.watch(clockProvider)();
    final offer = widget.offer;
    final framing = offer.candidate.framing;

    if (_typing) return _buildTyping(controller, framing, isSaving);

    final answered = _held != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          checkInFact(
            framing: framing,
            habit: offer.habit,
            occasionAt: offer.candidate.occasion.at,
            now: now,
          ),
          style: TextStyle(
            fontFamily: 'Karla',
            fontSize: 15,
            color: GardenColors.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          checkInQuestion(
            framing: framing,
            habit: offer.habit,
            expanded: _expanded,
          ),
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
          children: _chips(controller, framing, isSaving),
        ),
        const SizedBox(height: 14),
        // Hidden while a yes/no framing is un-expanded: `Something else` and
        // `Can't remember` are answers to an open question, and there is not
        // one on screen yet.
        if (!_isYesNo) _buildFooter(controller, framing, isSaving),
        if (_isYesNo)
          Align(
            alignment: Alignment.centerRight,
            child: CheckInFooterLink(
              label: CheckInLookBack.skipLabel,
              isQuiet: true,
              onPressed: isSaving ? null : () => _skip(controller),
            ),
          ),
        if (answered && widget.ticker.isStill) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.onAnswered,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: GardenColors.accent,
                foregroundColor: GardenColors.onAccent,
              ),
              child: const Text(CheckInLookBack.nextLabel),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _chips(
    CheckInController controller,
    Framing framing,
    bool isSaving,
  ) {
    if (_isYesNo) {
      final noLabel = framing == Framing.validation
          ? CheckInLookBack.validationNoLabel
          : CheckInLookBack.confirmationNoLabel;
      return [
        CheckInChip(
          label: CheckInLookBack.yesLabel,
          isPinned: true,
          isSelected: _held == CheckInLookBack.yesLabel,
          ticker: widget.ticker,
          // Yes *is* the answer: it reports the designed cue, and the engine
          // reads `matchedDesignedCue` off it.
          onPressed: isSaving
              ? null
              : () => _answer(
                  CheckInLookBack.yesLabel,
                  () => controller.answerWithTypedCue(
                    widget.offer.habit.designedCue!,
                  ),
                ),
        ),
        CheckInChip(
          label: noLabel,
          ticker: widget.ticker,
          // Not an answer by itself — only the pick after it is
          // (check-in-design §5). So this records nothing and opens the list.
          onPressed: isSaving ? null : () => setState(() => _expanded = true),
        ),
      ];
    }

    if (framing == Framing.diagnosis) {
      return [
        for (final chip in widget.offer.frictionChips)
          CheckInChip(
            label: chip.label,
            isSelected: _held == chip.label,
            ticker: widget.ticker,
            onPressed: isSaving
                ? null
                : () => _answer(
                    chip.label,
                    () => controller.answerWithFriction(chip),
                  ),
          ),
      ];
    }

    final designed = widget.offer.habit.designedCue?.trim().toLowerCase();
    return [
      for (final chip in _cueChips(designed))
        CheckInChip(
          label: chip.label,
          // The designed cue is pinned first on the open framings, and absent
          // from the expansion — the user has just said it was not that.
          isPinned: !_expanded && chip.label.toLowerCase() == designed,
          isSelected: _held == chip.label,
          ticker: widget.ticker,
          onPressed: isSaving
              ? null
              : () => _answer(chip.label, () => controller.answerWithCue(chip)),
        ),
    ];
  }

  List<StarterChip> _cueChips(String? designedCue) {
    final chips = widget.offer.cueChips;
    if (!_expanded || designedCue == null) return chips;
    return [
      for (final chip in chips)
        if (chip.label.toLowerCase() != designedCue) chip,
    ];
  }

  Widget _buildFooter(
    CheckInController controller,
    Framing framing,
    bool isSaving,
  ) {
    final showCantRemember =
        framing != Framing.diagnosis &&
        (!widget.offer.isFirstReflection ||
            CheckInLookBack.allowCantRememberOnFirstReflection);

    return Row(
      children: [
        CheckInFooterLink(
          label: CheckInLookBack.somethingElseLabel,
          onPressed: isSaving ? null : () => setState(() => _typing = true),
        ),
        if (showCantRemember)
          CheckInFooterLink(
            label: CheckInLookBack.cantRememberLabel,
            onPressed: isSaving
                ? null
                : () => _answer(
                    CheckInLookBack.cantRememberLabel,
                    controller.cantRemember,
                  ),
          ),
        const Spacer(),
        CheckInFooterLink(
          label: CheckInLookBack.skipLabel,
          isQuiet: true,
          onPressed: isSaving ? null : () => _skip(controller),
        ),
      ],
    );
  }

  Future<void> _skip(CheckInController controller) async {
    await controller.skip();
    if (mounted) widget.onSkipped();
  }

  Widget _buildTyping(
    CheckInController controller,
    Framing framing,
    bool isSaving,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        CheckInLookBack.typingPrompt(framing),
        style: const TextStyle(
          fontFamily: 'Newsreader',
          fontSize: 27,
          height: 1.15,
          color: GardenColors.ink,
        ),
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _typed,
        autofocus: true,
        maxLines: 1,
        style: const TextStyle(
          fontFamily: 'Karla',
          fontSize: 16,
          color: GardenColors.ink,
        ),
        decoration: InputDecoration(
          hintText: CheckInLookBack.typingPlaceholder(framing),
          hintStyle: TextStyle(
            fontFamily: 'Karla',
            color: GardenColors.ink.withValues(alpha: 0.4),
          ),
          filled: true,
          fillColor: const Color(0x0FFFFFFF),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0x2EFFFFFF)),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _typing = false),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                side: const BorderSide(color: Color(0x2EFFFFFF)),
              ),
              child: const Text(CheckInLookBack.backLabel),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 13,
            child: FilledButton(
              onPressed: _typed.text.trim().isEmpty || isSaving
                  ? null
                  : () => _answer(_typed.text.trim(), () async {
                      if (framing == Framing.diagnosis) {
                        await controller.answerWithTypedFriction(_typed.text);
                      } else {
                        await controller.answerWithTypedCue(_typed.text);
                      }
                    }),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: GardenColors.accent,
                foregroundColor: GardenColors.onAccent,
              ),
              child: const Text(CheckInLookBack.saveLabel),
            ),
          ),
        ],
      ),
    ],
  );
}
