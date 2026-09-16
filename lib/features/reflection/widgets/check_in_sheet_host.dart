import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/reflection/controllers/check_in_controller.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';
import 'package:taproot/features/reflection/widgets/check_in_sheet.dart';

/// The check-in sheet, and the state that decides what is inside it.
///
/// Sits on the garden (see `GardenPage`) rather than owning a screen, so the
/// roots of the habit being reflected on are visible behind it — which is the
/// reason the check-in is a sheet at all (check-in-design §1).
class CheckInSheetHost extends ConsumerStatefulWidget {
  const CheckInSheetHost({
    required this.offered,
    required this.ticker,
    super.key,
  });

  /// The offer the garden already assembled. It is re-verified rather than
  /// trusted — a notification answer can land in between — but re-verifying one
  /// habit is a fraction of electing a winner among all of them again.
  final CheckInOffer offered;

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

class _CheckInSheetHostState extends ConsumerState<CheckInSheetHost> {
  @override
  void initState() {
    super.initState();
    // After the frame: `load` writes controller state, and doing that during
    // the build that is creating this widget rebuilds a provider mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(checkInControllerProvider.notifier)
            .load(offered: widget.offered);
      }
    });
  }

  void _close() {
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

    final child = switch (state.status) {
      // No loading state on the happy path: the garden already assembled this
      // offer, so there is something to ask before the re-verification returns.
      CheckInStatus.looking ||
      CheckInStatus.asking ||
      CheckInStatus.answered => _Placeholder(offer: offer),
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
            .load(offered: widget.offered),
      ),
    };

    return CheckInSheet(
      habitName: offer.habit.name,
      step: '1 of 2',
      ticker: widget.ticker,
      child: child,
    );
  }
}

/// Step 1's content lands here in build step 3.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.offer});

  final CheckInOffer offer;

  @override
  Widget build(BuildContext context) => const SizedBox(height: 120);
}
