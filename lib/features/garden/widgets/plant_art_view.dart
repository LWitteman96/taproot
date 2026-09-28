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

/// The drawn plant and the roots beneath it, on one shared view model.
///
/// Nothing is still the common case — four of six species have no art, and a
/// device without the native library has none either. The garden says the whole
/// plant in words anyway, so this draws or it gets out of the way; it never
/// shows an error or a spinner.
///
/// Species-agnostic: everything it needs comes off the [PlantArt] for the
/// habit's `plantType`, so adding a species is a line in `plantArts` and an
/// asset, not a change here.
///
/// **The two artboards share one [rive.ViewModelInstance].** `roots` drives the
/// root system on one and a lean on the other, so two auto-bound instances
/// would let the plant lean about roots that disagree with the ones drawn under
/// it — silently, because both binds resolve perfectly well. Nesting the roots
/// inside the plant is the obvious alternative and does not work: a bind inside
/// a `NestedArtboard` resolves to nothing, with a clean build and an empty
/// `problems` list (`fern/NOTES.md`, "The stacking contract").
///
/// Wrapped in [ExcludeSemantics] because the slot already carries the whole
/// plant as a semantic label. The picture is a second rendering of what the
/// label says, not another thing to announce.
class PlantArtView extends ConsumerStatefulWidget {
  const PlantArtView({
    required this.habitId,
    this.size = GardenLayout.stageSize,
    super.key,
  });

  final String habitId;

  /// The stage artboard's drawn size, square. The roots hang below it at the
  /// same width and their own height.
  final double size;

  @override
  ConsumerState<PlantArtView> createState() => _PlantArtViewState();
}

class _PlantArtViewState extends ConsumerState<PlantArtView> {
  /// One per habit, created once and handed to both artboards.
  rive.ViewModelInstance? _instance;
  rive.ViewModelInstanceNumber? _vitality;
  rive.ViewModelInstanceNumber? _roots;
  rive.File? _boundTo;

  void _bind(rive.File file, PlantArt art) {
    if (identical(_boundTo, file)) return;
    // `createDefaultInstance` rather than a controller's `dataBind`: the
    // instance has to exist before either artboard does, because both of them
    // are handed this one.
    final artboard = file.artboard(art.artboardFor(Stage.mature));
    final viewModel = artboard == null
        ? null
        : file.defaultArtboardViewModel(artboard);
    _instance = viewModel?.createDefaultInstance();
    _vitality = _instance?.number(plantVitalityProperty);
    _roots = _instance?.number(plantRootsProperty);
    _boundTo = file;
  }

  @override
  Widget build(BuildContext context) {
    final plantType = ref.watch(habitPlantTypeProvider(widget.habitId));
    final art = plantArtFor(plantType);
    if (art == null) return const SizedBox.shrink();

    final stage = ref.watch(habitStageProvider(widget.habitId));
    if (stage == null) return const SizedBox.shrink();

    // `.value` and not a `when`: while the file is loading this is null, which
    // is the same "draw nothing" branch as never having loaded at all. The
    // family is keyed by species, so a garden of ferns and oaks decodes two
    // files between them rather than one per plant.
    final file = ref.watch(plantArtFileProvider(art.plantType)).value;
    if (file == null) return const SizedBox.shrink();
    _bind(file, art);

    final instance = _instance;
    if (instance == null) return const SizedBox.shrink();

    final ticker = gardenTickerOf(context, ref);
    // Watched, not read: a watering changes vitality and a check-in changes
    // roots, and both have to reach the art.
    _vitality?.value = ref.watch(habitVitalityProvider(widget.habitId)) ?? 1;
    // Not the engine's value directly: while a check-in is being answered the
    // roots are pinned at their pre-answer depth, so the growth lands with the
    // done state rather than mid-question (check-in-design §7.2).
    _roots?.value = ref.watch(drawnRootDepthProvider(widget.habitId));

    return ExcludeSemantics(
      child: SizedBox(
        width: widget.size,
        height: widget.size + GardenLayout.rootsDepth,
        child: Column(
          children: [
            SizedBox.square(
              dimension: widget.size,
              child: AnimatedSwitcher(
                // A stage advance is the one moment the plant is allowed to be
                // a different plant. Cross-fading is what stops that reading as
                // a glitch; at motionScale 0 it collapses to an instant swap,
                // which is the correct reduced-motion behaviour rather than a
                // lost frame.
                duration: ticker.durationFor(AppMotion.stageAdvanceDuration),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.bottomCenter,
                  children: [...previous, if (current != null) current],
                ),
                child: _Artboard(
                  // The key is the whole mechanism: a new stage is a new child,
                  // so AnimatedSwitcher fades it in as the old one fades out.
                  // Species is in the key too: a habit that changed plant would
                  // otherwise keep the old species' controller for the stage it
                  // was already on.
                  key: ValueKey<String>('${art.plantType}.${stage.name}'),
                  file: file,
                  instance: instance,
                  artboard: art.artboardFor(stage),
                  stateMachine: art.stateMachineName,
                  ticker: ticker,
                ),
              ),
            ),
            // The roots do not change with the stage, so they sit outside the
            // switcher: a stage advance should not restart the root system, and
            // cross-fading it against itself would only make it flicker.
            SizedBox(
              width: widget.size,
              height: GardenLayout.rootsDepth,
              child: _Artboard(
                file: file,
                instance: instance,
                artboard: art.rootsArtboard,
                stateMachine: art.stateMachineName,
                ticker: ticker,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One artboard, driven by an instance it does not own.
class _Artboard extends StatefulWidget {
  const _Artboard({
    required this.file,
    required this.instance,
    required this.artboard,
    required this.stateMachine,
    required this.ticker,
    super.key,
  });

  final rive.File file;
  final rive.ViewModelInstance instance;
  final String artboard;
  final String stateMachine;
  final GardenTicker ticker;

  @override
  State<_Artboard> createState() => _ArtboardState();
}

class _ArtboardState extends State<_Artboard> {
  rive.RiveWidgetController? _controller;

  /// Comfortably past the longer of the generator's two interpolators. Every
  /// species is built by `plantgen` with the same pair, so this is one number.
  static const double _settleSeconds = 1.5;

  @override
  void initState() {
    super.initState();
    try {
      final controller = rive.RiveWidgetController(
        widget.file,
        artboardSelector: rive.ArtboardNamed(widget.artboard),
        stateMachineSelector: rive.StateMachineNamed(widget.stateMachine),
      );
      // byInstance, never auto: auto would mint this artboard its own copy of
      // the numbers and quietly decouple it from the rest of the plant.
      controller.dataBind(rive.DataBind.byInstance(widget.instance));
      _controller = controller;
    } on rive.RiveException {
      // A missing artboard or state machine. The contract test exists to stop
      // this reaching a device, so here it just means no picture.
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    // `active` gates continued ticking, not the first apply — `advance` calls
    // `advanceAndApply` either way — so a still garden still shows the right
    // pose, it just stops moving afterwards.
    controller.active = widget.ticker.ambientEnabled;
    if (!widget.ticker.ambientEnabled) {
      // `fern/` eases a changed value over 0.6s (vitality) and 1.2s (roots), so
      // the pose is reached by *elapsed time*, not by the write. With ambient
      // motion off nothing advances, and a watering would leave the plant where
      // it was. Advancing past the longer window in one step resolves it to its
      // end state, which is what GardenTicker promises a 0 scale does: "resolve
      // instantly to their end state rather than being skipped".
      controller.stateMachine.advanceAndApply(_settleSeconds);
    }

    return rive.RiveWidget(
      controller: controller,
      // The box is the artboard's own aspect and scale, so `contain` maps the
      // canvas onto it 1:1 and every stage lands at the same world scale.
      fit: rive.Fit.contain,
      alignment: Alignment.center,
      // The slot's hit column owns the tap. A plant that swallowed its own taps
      // would be unselectable everywhere its transparent canvas overlaps a
      // neighbour, which is most of the row.
      hitTestBehavior: rive.RiveHitTestBehavior.none,
    );
  }
}
