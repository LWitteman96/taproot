import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/app/theme/garden_layout.dart';
import 'package:taproot/core/utils/flavor.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/domain/garden_camera.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/domain/plant_art.dart';
import 'package:taproot/features/garden/domain/plant_descriptions.dart';
import 'package:taproot/features/garden/providers/garden_scene_providers.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/garden/widgets/garden_header.dart';
import 'package:taproot/features/garden/widgets/empty_plot.dart';
import 'package:taproot/features/garden/widgets/garden_scene.dart';
import 'package:taproot/features/garden/widgets/selection_glow.dart';
import 'package:taproot/features/garden/widgets/plant_art_view.dart';
import 'package:taproot/features/garden/widgets/plant_detail_card.dart';
import 'package:taproot/features/garden/widgets/plant_silhouette.dart';
import 'package:taproot/features/habits/domain/plant_choices.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';
import 'package:taproot/features/reflection/widgets/check_in_sheet.dart';
import 'package:taproot/features/reflection/widgets/check_in_sheet_host.dart';

/// The home screen: one garden, not a list of cards.
///
/// A single vertical cross-section — sky above, a grass line, soil below — with
/// every habit standing on the same ground at the same world scale. Governed by
/// `docs/garden-design.md`; the scene layers and their order are its §3.
///
/// design-spec §6: the emotional job is *"look how far you've come,"* not
/// *"here's what you still owe."* Hence a greeting rather than a title, a
/// status line rather than a count, and no red anywhere.
class GardenPage extends ConsumerWidget {
  const GardenPage({this.checkIn, super.key});

  /// The offer to open the check-in sheet with, when the screen was reached
  /// through `/check-in` or the garden's own Reflect button.
  ///
  /// The sheet lives on this screen rather than on its own, because the roots
  /// growing behind it *is* the payoff (check-in-design §1). A route that
  /// replaced the garden would have nothing to grow.
  final CheckInOffer? checkIn;

  static const String emptyHeadline = 'Nothing planted yet';
  static const String emptyBody =
      'A garden starts with one habit — the thing you do, what sets it off, '
      'and what you get out of it.';
  static const String plantLabel = 'Plant something';
  static const String wateredMessage = 'Watered';
  static const String unreadableHeadline = 'Your garden could not be read';
  static const String unreadableBody =
      'Nothing has been lost. This device could not open its store just now — '
      'trying again usually gets it.';
  static const String retryLabel = 'Try again';
  static const String checkInInvitation = 'Got a moment?';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Failures reach the user here rather than at the gesture. The controller
    // turns every one of them into a sentence, so this only has to show it and
    // then forget it — a message that outlives its snack bar comes back on the
    // next rebuild.
    ref.listen<String?>(gardenErrorProvider, (previous, next) {
      if (next == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(next)));
      // Deferred to the next microtask, not called here. Clearing inside the
      // listener writes the controller's state during the frame the listener is
      // running in, so `gardenErrorProvider` rebuilds twice in one frame and the
      // debug scheduler throws `StateError: Tried to rebuild ... multiple times
      // in the same frame` — on every error path, in every debug build.
      Future<void>.microtask(() {
        if (!context.mounted) return;
        ref.read(gardenControllerProvider.notifier).clearError();
      });
    });

    final isLoading = ref.watch(gardenIsLoadingProvider);
    final loadFailed = ref.watch(gardenLoadFailedProvider);
    final habitIds = ref.watch(plantIdsProvider);
    final mode = ref.watch(timeOfDayModeProvider);
    final ticker = gardenTickerOf(context, ref);
    final selectedId = ref.watch(selectedHabitIdProvider);

    // Opening the sheet selects the reflected plant, and closing leaves it
    // selected (check-in-design §8).
    final reflectingId = checkIn?.habit.id;
    final reflectingIndex = reflectingId == null
        ? -1
        : habitIds.indexOf(reflectingId);
    final camera = reflectingIndex < 0
        ? GardenCamera.home
        : GardenCamera.onPlant(reflectingIndex);

    // A garden that could not be read is not an empty garden, and saying
    // "nothing planted yet" to someone whose store failed is the app telling
    // them their work is gone. A failed *refresh* with plants already on screen
    // keeps the plants — the snack bar is enough there.
    final state = switch ((isLoading, loadFailed, habitIds.isEmpty)) {
      (true, _, _) => _GardenViewState.loading,
      (false, true, true) => _GardenViewState.unreadable,
      (false, _, true) => _GardenViewState.empty,
      (false, _, false) => _GardenViewState.planted,
    };

    // The scene is a dark-ground scene whatever the system setting, so the
    // chrome on it is the dark scheme (garden-design §8). Theming here rather
    // than at the app level keeps every other screen following the system.
    return Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: GardenColors.bgApp,
        body: _CameraMove(
          target: camera,
          ticker: ticker,
          builder: (context, live, progress) => GardenScene(
            mode: mode,
            groundLineFraction: live.groundLineFraction,
            scrimOpacity: CheckInSheetHost.scrimAsking * progress,
            ground: (context, groundLine, viewport) => _Ground(
              groundLine: groundLine,
              viewport: viewport,
              habitIds: state == _GardenViewState.planted ? habitIds : const [],
              ticker: ticker,
              camera: live,
              // The plot is the empty garden's whole content, and it follows
              // the plants once there are any. It is absent while loading and
              // when the store could not be read: offering to plant something
              // on top of a garden that may already exist invites making it
              // worse. It is also absent behind the sheet, which is not a
              // moment for starting something new.
              showPlot:
                  checkIn == null &&
                  (state == _GardenViewState.planted ||
                      state == _GardenViewState.empty),
            ),
            // The header stays put behind the sheet rather than being hidden:
            // the greeting is the garden, and the sheet is over the garden.
            header: SafeArea(
              bottom: false,
              child: GardenHeader(
                checkInChip:
                    checkIn == null && state == _GardenViewState.planted
                    ? const _CheckInInvitation()
                    : null,
              ),
            ),
            detailCard: switch (state) {
              // No card while loading: the scene with nothing on it is the
              // loading state, and a card outline with no content in it reads
              // as a plant that failed rather than as one that has not arrived.
              _ when checkIn != null => null,
              _GardenViewState.loading => null,
              _GardenViewState.unreadable => const _UnreadableGarden(),
              _GardenViewState.empty => const _EmptyGarden(),
              _GardenViewState.planted =>
                selectedId == null
                    ? null
                    : _SelectedPlantCard(habitId: selectedId, ticker: ticker),
            },
            sheet: checkIn == null
                ? null
                : CheckInSheetHost(offered: checkIn!, ticker: ticker),
          ),
        ),
      ),
    );
  }
}

/// Runs the camera between two positions.
///
/// The move belongs to the sheet's entry — 520ms on the same curve — so the two
/// read as one movement rather than as two things happening at once
/// (check-in-design §3). [progress] is 0 at home and 1 on the plant, which is
/// also what the scrim fades on.
class _CameraMove extends StatelessWidget {
  const _CameraMove({
    required this.target,
    required this.ticker,
    required this.builder,
  });

  final GardenCamera target;
  final GardenTicker ticker;
  final Widget Function(
    BuildContext context,
    GardenCamera live,
    double progress,
  )
  builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(
      begin: target.isHome ? 0 : 1,
      end: target.isHome ? 0 : 1,
    ),
    duration: ticker.durationFor(CheckInSheet.entryDuration),
    curve: CheckInSheet.entryCurve,
    builder: (context, progress, _) => builder(
      context,
      GardenCamera.lerp(GardenCamera.home, target, progress),
      progress,
    ),
  );
}

enum _GardenViewState { loading, unreadable, empty, planted }

/// The ground, the plants on it and the empty plot at the end — the layers that
/// scroll.
///
/// Stateful because it owns the scroll position: selecting a plant has to be
/// able to bring it into view, which needs a controller that outlives a build.
class _Ground extends ConsumerStatefulWidget {
  const _Ground({
    required this.groundLine,
    required this.viewport,
    required this.habitIds,
    required this.ticker,
    required this.camera,
    required this.showPlot,
  });

  final double groundLine;
  final Size viewport;
  final List<String> habitIds;
  final GardenTicker ticker;

  /// Where the camera is. At home the row scrolls; on a plant it does not —
  /// the sheet is about one habit, and letting the garden slide under it would
  /// invite losing the plant the question is about.
  final GardenCamera camera;

  /// False while loading and when the store could not be read: an offer to
  /// plant something, over a garden that may or may not already have plants in
  /// it, is an invitation to make the problem worse.
  final bool showPlot;

  @override
  ConsumerState<_Ground> createState() => _GroundState();
}

class _GroundState extends ConsumerState<_Ground> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Bring a slot fully into view if it is not already.
  ///
  /// Deliberately does nothing when the plant is already visible: scrolling on
  /// every selection would move the garden under a user who tapped exactly what
  /// they meant to tap.
  void _revealSlot(int index) {
    if (!_scroll.hasClients) return;
    final centre = GardenLayout.slotCentre(index);
    final half = GardenLayout.slotPitch / 2;
    final offset = _scroll.offset;
    final width = _scroll.position.viewportDimension;

    final double? target;
    if (centre - half < offset) {
      target = centre - half;
    } else if (centre + half > offset + width) {
      target = centre + half - width;
    } else {
      target = null;
    }
    if (target == null) return;

    final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
    if (widget.ticker.isStill) {
      _scroll.jumpTo(clamped);
    } else {
      _scroll.animateTo(
        clamped,
        duration: widget.ticker.durationFor(SelectionGlow.slideDuration),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _select(int index, String habitId) {
    ref.read(selectedHabitIdProvider.notifier).select(habitId);
    // After the frame, so the scroll view has laid out the slot being revealed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealSlot(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedHabitIdProvider);
    final selectedIndex = widget.habitIds.indexOf(selectedId ?? '');
    final sceneWidth = GardenLayout.sceneWidth(
      widget.habitIds.length,
      viewportWidth: widget.viewport.width,
    );

    final ground = GardenGroundLayer(
      groundLine: widget.groundLine,
      viewport: widget.viewport,
      sceneWidth: sceneWidth,
      plants: [
        if (selectedIndex >= 0)
          SelectionGlow(
            centreX: GardenLayout.slotCentre(selectedIndex),
            groundLine: widget.groundLine,
            ticker: widget.ticker,
          ),
        for (final (index, habitId) in widget.habitIds.indexed)
          Positioned(
            left: GardenLayout.slotCentre(index) - GardenLayout.slotPitch / 2,
            top: 0,
            bottom: 0,
            width: GardenLayout.slotPitch,
            child: _Plant(
              habitId: habitId,
              groundLine: widget.groundLine,
              onTap: () => _select(index, habitId),
            ),
          ),
        if (widget.showPlot)
          Positioned(
            left:
                GardenLayout.slotCentre(widget.habitIds.length) -
                GardenLayout.slotPitch / 2,
            top: 0,
            bottom: 0,
            width: GardenLayout.slotPitch,
            child: EmptyPlot(
              groundLine: widget.groundLine,
              onTap: () => context.push(AppRoutes.habitCreation),
            ),
          ),
      ],
    );

    if (!widget.camera.isHome) {
      // Scaled about the focused plant rather than scrolled to it. A transform
      // moves the scene as one, so every plant is still drawn at world scale —
      // the camera is closer, the world has not changed size.
      return Transform(
        transform: widget.camera.transformFor(
          viewport: widget.viewport,
          groundLine: widget.groundLine,
        ),
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: sceneWidth,
          child: ground,
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: ground,
    );
  }
}

/// One plant, standing on the ground line.
///
/// Bottom-aligned in a column the height of the sky, so the plant's base sits
/// on the ground line whatever its stage — size differences are growth, never
/// layout (garden-design §2).
class _Plant extends ConsumerWidget {
  const _Plant({
    required this.habitId,
    required this.groundLine,
    required this.onTap,
  });

  final String habitId;
  final double groundLine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plant = ref.watch(plantStateProvider(habitId));
    if (plant == null) return const SizedBox.shrink();

    final growth = plant.growth;
    final species = plantChoiceById(plant.habit.plantType)?.label ?? 'Plant';
    final drawn = hasPlantArt(plant.habit.plantType);

    // How far the plant reaches above the ground, which is what the hit column
    // is measured from. The art's is fixed by the canvas; a silhouette's is its
    // own height.
    final reach = drawn
        ? GardenLayout.stageAboveGround
        : PlantSilhouette.sizeFor(growth.stage).height;

    return Semantics(
      button: true,
      label: plantSemanticLabel(
        habitName: plant.habit.name,
        stage: growth.stage,
        vitality: growth.vitality,
        rootDepth: growth.roots.depth,
        isShallowRooted: growth.isShallowRooted,
        isPaused: plant.habit.isPaused,
      ),
      onTap: onTap,
      child: PlantHitColumn(
        groundLine: groundLine,
        plantHeight: reach,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (drawn)
              // Anchored on canvas y = 900, not on the canvas bottom: the
              // artboard is square and larger than the plant, so the rest of it
              // hangs below the ground line where the soil covers it. The roots
              // artboard continues underneath, its own top edge on the same
              // line, which is why the box is taller than it is wide.
              Positioned(
                left: (GardenLayout.slotPitch - GardenLayout.stageSize) / 2,
                top: groundLine - GardenLayout.stageAboveGround,
                width: GardenLayout.stageSize,
                height: GardenLayout.stageSize + GardenLayout.rootsDepth,
                child: PlantArtView(habitId: habitId),
              )
            else ...[
              // The plant's base sits *on* the line, not above a caption that
              // sits on it. Size differences between plants are growth, never
              // layout (garden-design §2), and that only holds if they share a
              // floor.
              Positioned(
                left: 0,
                right: 0,
                top: groundLine - reach,
                child: Center(
                  child: PlantSilhouette(
                    species: species,
                    stage: growth.stage,
                    vitality: growth.vitality,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: groundLine + GardenLayout.grassBandHeight + 4,
                child: Center(
                  child: PlantSilhouetteLabel(
                    species: species,
                    stage: growth.stage,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The detail card for the selected plant, plus the undo offer after watering.
class _SelectedPlantCard extends ConsumerWidget {
  const _SelectedPlantCard({required this.habitId, required this.ticker});

  final String habitId;
  final GardenTicker ticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plant = ref.watch(plantStateProvider(habitId));
    if (plant == null) return const SizedBox.shrink();

    final controller = ref.read(gardenControllerProvider.notifier);
    final undoable = plant.undoableCompletion;

    return PlantDetailCard(
      plant: plant,
      ticker: ticker,
      onWatered: () async {
        await controller.water(habitId);
      },
      onUndo: undoable == null
          ? null
          : () => controller.undo(habitId, undoable.id),
    );
  }
}

/// The way into the evening check-in.
///
/// Shown **only when there is something worth asking**, which is most of the
/// point: reflection-logic §2 expects no check-in on most days, and a standing
/// button that usually opens a screen saying "nothing to ask" would teach the
/// user to stop pressing it.
class _CheckInInvitation extends ConsumerWidget {
  const _CheckInInvitation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(checkInOfferProvider);

    return offer.maybeWhen(
      data: (value) => value == null
          ? const SizedBox.shrink()
          : Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.eco_outlined),
                label: Text(
                  '${GardenPage.checkInInvitation} '
                  '${value.habit.name.toLowerCase()}',
                ),
                // The offer goes with the tap. The screen re-verifies it — a
                // notification answer can land in between — but against one
                // habit rather than reassembling every habit's ledgers and
                // growth ladder to re-elect the one just named here.
                onPressed: () => context.push(AppRoutes.checkIn, extra: value),
              ),
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// What the app looks like when the store could not be read.
///
/// Deliberately not the empty state: the difference between "you have not
/// planted anything" and "we could not look" is the whole message. Drawn in the
/// card's place so the garden is still there behind it (garden-design §4.6).
class _UnreadableGarden extends ConsumerWidget {
  const _UnreadableGarden();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SceneMessage(
    headline: GardenPage.unreadableHeadline,
    body: GardenPage.unreadableBody,
    actionLabel: GardenPage.retryLabel,
    onAction: () => ref.read(gardenControllerProvider.notifier).refresh(),
  );
}

/// What the app looks like before anything is planted.
///
/// Mostly transient, now that the entry gate is real: a user with no habits is
/// redirected into habit creation, so this is what shows in the frame before
/// the gate resolves.
class _EmptyGarden extends StatelessWidget {
  const _EmptyGarden();

  @override
  Widget build(BuildContext context) => _SceneMessage(
    headline: GardenPage.emptyHeadline,
    body: GardenPage.emptyBody,
    // No button. The empty plot standing in slot 0 *is* the offer
    // (garden-design §4.5), and §4.6 asks this card for the headline and body
    // only — two identical invitations on one screen would make the user
    // choose between them for no reason.
    //
    // Carried over from the card list rather than dropped with it: this is the
    // only place in the app that says which flavor is running, and the empty
    // garden is where a fresh install lands.
    footnote: 'flavor: ${getFlavor().name}',
  );
}

/// A message where the detail card would be, in the card's own clothes.
class _SceneMessage extends StatelessWidget {
  const _SceneMessage({
    required this.headline,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.footnote,
  });

  final String headline;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? footnote;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: GardenColors.card.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0x17FFFFFF)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: const TextStyle(
              fontFamily: 'Newsreader',
              fontSize: 24,
              color: GardenColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.small),
          Text(
            body,
            style: TextStyle(
              fontFamily: 'Karla',
              fontSize: 14,
              color: GardenColors.ink.withValues(alpha: 0.8),
            ),
          ),
          if (actionLabel case final label?) ...[
            const SizedBox(height: AppSpacing.medium),
            FilledButton(onPressed: onAction, child: Text(label)),
          ],
          if (footnote case final footnote?) ...[
            const SizedBox(height: AppSpacing.small),
            Text(
              footnote,
              style: TextStyle(
                fontFamily: 'Karla',
                fontSize: 11,
                color: GardenColors.ink.withValues(alpha: 0.45),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
