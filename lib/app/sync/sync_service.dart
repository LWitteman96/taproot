import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:taproot/app/connectivity/connectivity_providers.dart';
import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/app/supabase/supabase_config.dart';
import 'package:taproot/app/sync/sync_drain.dart';
import 'package:taproot/app/sync/sync_state.dart';

/// Decides when to synchronise.
///
/// The trigger is a **false → true connectivity edge**, not a timer and not a
/// poll: the moment worth spending battery on is the moment the network comes
/// back, and every other moment the local store has already served the user.
///
/// The edge has one subtlety that is easy to get wrong and invisible when you
/// do — see [_onConnectivity].
final syncServiceProvider = NotifierProvider<SyncService, SyncState>(
  SyncService.new,
);

class SyncService extends Notifier<SyncState> {
  static final Logger _log = Logger('SyncService');

  late final SyncDrain _drain;
  late final DateTime Function() _clock;

  /// What connectivity last said, or null if it has not said anything yet.
  ///
  /// Null is not "unknown, do nothing" — see [_onConnectivity].
  bool? _wasOnline;

  /// True while a drain is in flight, so a second one cannot start beside it.
  bool _isDraining = false;

  /// Set when an edge arrives mid-drain. That edge must not be dropped: the
  /// drain already running may have read the pending set before the write that
  /// edge is about to make it possible to push.
  bool _drainAgain = false;

  @override
  SyncState build() {
    _drain = ref.read(syncDrainProvider);
    _clock = ref.read(clockProvider);

    // Asked before anything else. A build with no credentials has nothing to
    // subscribe to and nothing to report, and saying so is better than an
    // idle sync that never runs and looks like one that has nothing to do.
    if (!ref.read(supabaseConfigProvider).isConfigured) {
      _log.info('no backend is configured for this flavor; sync is off');
      return const SyncState(status: SyncStatus.unavailable);
    }

    ref.listen<AsyncValue<bool>>(isOnlineProvider, (previous, next) {
      // Only data. A stream error says the plugin could not tell us, which is
      // not the same as being offline and must not be recorded as one — doing
      // so would manufacture an edge out of the recovery.
      final isOnline = next.value;
      if (isOnline != null) _onConnectivity(isOnline);
    }, fireImmediately: true);

    return const SyncState();
  }

  /// Runs a drain on the rising edge, and only on the rising edge.
  ///
  /// **A null previous value counts as offline.** The app launches with no
  /// connectivity reading at all, and the first thing the stream emits on a
  /// device that is already online is `true`. Treating null as "unknown" and
  /// requiring a real false first swallows exactly that emission, so an app
  /// opened on wifi never syncs until the network drops and returns — which on
  /// a phone that never leaves the house is never. It is the launch case, not
  /// an edge case, and it fails silently in precisely the situation nobody
  /// tests in.
  void _onConnectivity(bool isOnline) {
    final wasOnline = _wasOnline ?? false;
    _wasOnline = isOnline;

    if (wasOnline || !isOnline) return;
    _log.fine('the network came back; draining');
    unawaited(syncNow());
  }

  /// Pushes and pulls once, now.
  ///
  /// Public because the edge is not the only reason to sync — a pull-to-refresh
  /// and a post-sign-in drain both land here — and because a test should be
  /// able to ask for one without staging a network.
  ///
  /// Re-entrant by queueing rather than by running twice: a second caller marks
  /// the running drain dirty and returns, and the drain repeats when it
  /// finishes. Two concurrent drains would race each other for the same pending
  /// rows and the same cursor for no gain, and dropping the second request
  /// loses the writes it was told about.
  Future<void> syncNow() async {
    if (state.status == SyncStatus.unavailable) return;
    if (_isDraining) {
      _drainAgain = true;
      return;
    }

    _isDraining = true;
    try {
      do {
        _drainAgain = false;
        state = state.copyWith(
          status: SyncStatus.syncing,
          errorMessage: () => null,
        );

        final outcome = await _drain.drain();
        if (!ref.mounted) return;

        // A clean return is not a round trip. `drain()` returns early without
        // throwing when nobody is signed in — correctly, since signed out is a
        // designed state rather than a failure — and stamping the clock for
        // that would make `lastSucceededAt` mean "a drain was attempted"
        // rather than "your work is safe somewhere else". `SyncStatus`'s own
        // doc-comment makes the argument: an app that shows "all backed up"
        // while backing nothing up is lying, and the difference is invisible
        // from the status alone if the two share a value.
        //
        // Nothing signs a user in yet, so this is currently the *only* path a
        // dev build takes — the first UI to render "synced 4 minutes ago"
        // would otherwise be wired to a value that has never once been true.
        state = switch (outcome) {
          DrainOutcome.drained => state.copyWith(
            status: SyncStatus.idle,
            lastSucceededAt: _clock,
            errorMessage: () => null,
          ),
          DrainOutcome.signedOut => state.copyWith(
            status: SyncStatus.signedOut,
            errorMessage: () => null,
          ),
        };
      } while (_drainAgain);
    } catch (error, stackTrace) {
      _log.warning('the drain could not finish', error, stackTrace);
      if (!ref.mounted) return;
      // lastSucceededAt is deliberately left where it was. "Last backed up on
      // Tuesday" is the true and useful thing to say after a failure; clearing
      // it would replace it with nothing.
      state = state.copyWith(
        status: SyncStatus.failed,
        errorMessage: () => couldNotSyncMessage,
      );
    } finally {
      _isDraining = false;
    }
  }
}
