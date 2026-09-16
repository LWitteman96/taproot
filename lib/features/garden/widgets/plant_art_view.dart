import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' as rive;

import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/app/theme/garden_layout.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/domain/plant_art.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/garden/providers/plant_art_providers.dart';

/// The drawn plant, or nothing at all.
///
/// Nothing is the common case for now — five of six species have no art, and a
/// device without the native library has none either. The garden says the whole
/// plant in words anyway, so this draws or it gets out of the way; it never
/// shows an error or a spinner. A plant flickering in a second after the rest
/// of the scene would be worse than never seeing it.
///
/// It renders the artboard at exactly [size] square, which the caller sets from
/// [GardenLayout.stageSize] so every plant in the garden shares one world scale
/// (garden-design §2). It does not position itself: where the artboard's ground
/// line falls is the slot's business, not the art's.
///
/// Wrapped in [ExcludeSemantics] because the slot already carries the whole
/// plant as a semantic label. The picture is a second rendering of what the
/// label says, not another thing to announce.
class PlantArtView extends ConsumerWidget {
  const PlantArtView({
    required this.habitId,
    this.size = GardenLayout.stageSize,
    super.key,
  });

  final String habitId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Two narrow selectors rather than the whole PlantState: a watering changes
    // the plant object, and the art only cares about two fields of it. Species
    // is fixed at creation, so in practice only a stage advance rebuilds this.
    final plantType = ref.watch(habitPlantTypeProvider(habitId));
    if (plantType == null || !hasPlantArt(plantType)) {
      return const SizedBox.shrink();
    }

    final stage = ref.watch(habitStageProvider(habitId));
    if (stage == null) return const SizedBox.shrink();

    // `.value` and not a `when`: while the file is loading this is null, which
    // is the same "draw nothing" branch as never having loaded at all.
    final file = ref.watch(riveFernFileProvider).value;
    if (file == null) return const SizedBox.shrink();

    final ticker = gardenTickerOf(context, ref);

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedSwitcher(
          // A stage advance is the one moment the plant is allowed to be a
          // different plant. Cross-fading is what stops that reading as a
          // glitch; at motionScale 0 this collapses to an instant swap, which
          // is the correct reduced-motion behaviour rather than a lost frame.
          duration: ticker.durationFor(AppMotion.stageAdvanceDuration),
          // Both plants occupy the same box for the length of the fade, rather
          // than the incoming one being laid out after the outgoing one leaves.
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            alignment: Alignment.bottomCenter,
            children: [...previous, if (current != null) current],
          ),
          child: _FernStageView(
            // The key is the whole mechanism: a new stage is a new child, so
            // AnimatedSwitcher builds and fades it while the old one fades out.
            key: ValueKey<Stage>(stage),
            file: file,
            stage: stage,
            habitId: habitId,
            ticker: ticker,
          ),
        ),
      ),
    );
  }
}

/// One artboard, alive for as long as its stage is on screen.
///
/// Stateful because a [rive.RiveWidgetController] owns native resources and has
/// to be disposed. During a stage cross-fade two of these exist at once, each
/// with its own controller and its own view model instance.
class _FernStageView extends ConsumerStatefulWidget {
  const _FernStageView({
    required this.file,
    required this.stage,
    required this.habitId,
    required this.ticker,
    super.key,
  });

  final rive.File file;
  final Stage stage;
  final String habitId;
  final GardenTicker ticker;

  @override
  ConsumerState<_FernStageView> createState() => _FernStageViewState();
}

class _FernStageViewState extends ConsumerState<_FernStageView> {
  rive.RiveWidgetController? _controller;
  rive.ViewModelInstanceNumber? _vitality;

  @override
  void initState() {
    super.initState();
    _build();
  }

  void _build() {
    try {
      final controller = rive.RiveWidgetController(
        widget.file,
        artboardSelector: rive.ArtboardNamed(fernArtboardFor(widget.stage)),
        stateMachineSelector: const rive.StateMachineNamed(
          fernStateMachineName,
        ),
      );
      _vitality = controller
          .dataBind(rive.DataBind.auto())
          .number(fernVitalityProperty);
      _controller = controller;
    } on rive.RiveException {
      // A missing artboard or state machine. The contract test exists to stop
      // this reaching a device, so here it just means no picture.
      _controller = null;
      _vitality = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Push the engine's vitality into the artboard, and make sure it arrives.
  ///
  /// The arrival is the subtle half. `fern/` smooths a changed vitality over
  /// ~0.6s with a `DataConverterInterpolator`, so the new pose is reached by
  /// *elapsed time*, not by the write. While the sway is running that happens
  /// on its own. With ambient motion off nothing advances, so the write would
  /// sit in the converter and never land — the plant would keep its old pose
  /// after a watering.
  ///
  /// Advancing past the smoothing window in one step resolves it to its end
  /// state instead, which is exactly what [GardenTicker] promises a `0` scale
  /// does: "resolve instantly to their end state rather than being skipped, so
  /// nothing is lost, only the travel".
  void _applyVitality(double vitality) {
    final controller = _controller;
    if (controller == null || _vitality == null) return;
    _vitality!.value = vitality;
    if (!widget.ticker.ambientEnabled) {
      controller.stateMachine.advanceAndApply(_settleSeconds);
    }
  }

  /// Comfortably past `fern/`'s smoothing duration, so the converter has
  /// finished rather than being caught mid-ease.
  static const double _settleSeconds = 1;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    // Watched, not read: a watering changes vitality and this has to follow it.
    final vitality = ref.watch(habitVitalityProvider(widget.habitId));
    if (vitality != null) _applyVitality(vitality);

    // `active` gates continued ticking, not the first apply — `advance` calls
    // `advanceAndApply` either way — so a still garden still shows the right
    // pose, it just stops moving afterwards.
    controller.active = widget.ticker.ambientEnabled;

    return rive.RiveWidget(
      controller: controller,
      // The box is the artboard's own aspect and scale, so `contain` maps the
      // 1024 canvas onto it 1:1 and every stage lands at the same world scale.
      fit: rive.Fit.contain,
      alignment: Alignment.center,
      // The slot's hit column owns the tap. A plant that swallowed its own
      // taps would be unselectable everywhere its transparent canvas overlaps
      // a neighbour, which is most of the row.
      hitTestBehavior: rive.RiveHitTestBehavior.none,
    );
  }
}
