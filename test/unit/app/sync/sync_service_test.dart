import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/connectivity/connectivity_providers.dart';
import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/app/supabase/supabase_config.dart';
import 'package:taproot/app/sync/sync_drain.dart';
import 'package:taproot/app/sync/sync_service.dart';
import 'package:taproot/app/sync/sync_state.dart';

import '../../../utils/store_fixtures.dart';

/// A drain the test can count, stall or break.
class ControllableDrain implements SyncDrain {
  int runs = 0;

  /// Completed by the test to let a drain finish.
  Completer<void>? gate;

  /// Thrown instead of draining.
  Object? failure;

  @override
  Future<void> drain() async {
    runs++;
    if (gate != null) await gate!.future;
    if (failure case final thrown?) throw thrown;
  }
}

class Harness {
  Harness({bool configured = true}) {
    container = ProviderContainer(
      overrides: [
        supabaseConfigProvider.overrideWithValue(
          configured
              ? const SupabaseConfig(
                  url: 'http://127.0.0.1:54331',
                  publishableKey: 'a-json-web-token',
                )
              : const SupabaseConfig(url: '', publishableKey: ''),
        ),
        syncDrainProvider.overrideWithValue(drain),
        clockProvider.overrideWithValue(clock.call),
        // The connectivity stream, in the test's hands. Deliberately not
        // seeded: the app starts knowing nothing, which is the case the edge
        // rule is subtle about.
        isOnlineProvider.overrideWith((ref) => connectivity.stream),
      ],
    );
    // Registered in this order so the LIFO teardown disposes the container —
    // and with it the provider's subscription — before the stream behind it
    // goes away.
    //
    // `close()` is deliberately not awaited. A broadcast controller's close
    // future completes when every listener has taken its done event, and with
    // Riverpod's subscription in the middle that never happened here: awaiting
    // it hung the teardown, which the runner reports as the *test* timing out
    // 30 seconds after its body has already passed. Worth recognising — the
    // failure names the assertion, and the assertion is fine.
    addTearDown(() {
      connectivity.close();
    });
    addTearDown(container.dispose);
  }

  final TestClock clock = TestClock(DateTime(2026, 3, 4, 9));
  final ControllableDrain drain = ControllableDrain();
  final StreamController<bool> connectivity =
      StreamController<bool>.broadcast();
  late final ProviderContainer container;

  SyncState get state => container.read(syncServiceProvider);
  SyncService get service => container.read(syncServiceProvider.notifier);

  /// Starts the service, the way the app does.
  ///
  /// A real `listen`, not a `read`. Riverpod 3 **pauses** a provider whose
  /// listeners are all paused — and a provider nobody listens to at all is in
  /// that set — which pauses the connectivity subscription underneath it, so
  /// the edge never arrives. A bare `read` builds the notifier and then lets it
  /// go quiet, which looks like the service ignoring the network.
  void start() => container.listen(
    syncServiceProvider,
    (previous, next) {},
    onError: (_, _) {},
  );

  /// Lets the stream event and the drain it starts run to completion.
  Future<void> settle() => pumpEventQueue();

  Future<void> goOnline() async {
    connectivity.add(true);
    await settle();
  }

  Future<void> goOffline() async {
    connectivity.add(false);
    await settle();
  }
}

void main() {
  group('SyncService', () {
    group('the connectivity edge', () {
      test('the first true drains, though nothing was ever false', () async {
        // The launch case, and the one worth writing the rule down for. A
        // device opened on wifi emits `true` as its first reading and nothing
        // before it. Requiring a real false first swallows that emission, so
        // the app never syncs until the network drops and comes back — which
        // on a phone that never leaves the house is never. A null previous
        // value means "was offline", not "unknown".
        final harness = Harness();
        harness.start();

        await harness.goOnline();

        expect(harness.drain.runs, 1);
        expect(harness.state.status, SyncStatus.idle);
        expect(harness.state.lastSucceededAt, harness.clock.now);
      });

      test('offline then online drains', () async {
        final harness = Harness();
        harness.start();

        await harness.goOffline();
        expect(harness.drain.runs, 0);

        await harness.goOnline();
        expect(harness.drain.runs, 1);
      });

      test('staying online does not drain again', () async {
        // The plugin re-emits on interface changes that are not transitions —
        // wifi to mobile, a vpn coming up. None of those is a reason to sync.
        final harness = Harness();
        harness.start();

        await harness.goOnline();
        await harness.goOnline();
        await harness.goOnline();

        expect(harness.drain.runs, 1);
      });

      test('going offline does not drain', () async {
        final harness = Harness();
        harness.start();

        await harness.goOnline();
        await harness.goOffline();

        expect(harness.drain.runs, 1);
      });

      test('a stream error is not an offline reading', () async {
        // If an error were recorded as offline, the next good reading would
        // look like a rising edge and manufacture a drain out of the plugin's
        // recovery. The error means "we could not tell", which changes nothing.
        final harness = Harness();
        harness.start();

        await harness.goOnline();
        expect(harness.drain.runs, 1);

        harness.connectivity.addError(StateError('the plugin fell over'));
        await harness.settle();
        await harness.goOnline();

        expect(harness.drain.runs, 1);
      });
    });

    group('a build with no backend', () {
      test('is unavailable rather than idle', () async {
        // Distinct states on purpose: an app showing "all backed up" while
        // backing nothing up is lying, and idle is what that lie looks like.
        final harness = Harness(configured: false);
        harness.start();

        expect(harness.state.status, SyncStatus.unavailable);
        expect(harness.state.isAvailable, isFalse);
      });

      test('never drains, however the network behaves', () async {
        final harness = Harness(configured: false);
        harness.start();

        await harness.goOnline();
        await harness.goOffline();
        await harness.goOnline();
        await harness.service.syncNow();

        expect(harness.drain.runs, 0);
        expect(harness.state.status, SyncStatus.unavailable);
      });
    });

    group('draining', () {
      test('never spins: the state says syncing while it runs', () async {
        final harness = Harness();
        harness.start();

        harness.drain.gate = Completer<void>();
        final pending = harness.service.syncNow();
        await harness.settle();

        expect(harness.state.status, SyncStatus.syncing);
        expect(harness.state.isSyncing, isTrue);

        harness.drain.gate!.complete();
        await pending;
        expect(harness.state.status, SyncStatus.idle);
      });

      test('a failure is surfaced as state, not thrown', () async {
        final harness = Harness();
        harness.start();

        harness.drain.failure = StateError('the network went away mid-push');
        await harness.service.syncNow();

        expect(harness.state.status, SyncStatus.failed);
        expect(harness.state.errorMessage, couldNotSyncMessage);
      });

      test(
        'a failure keeps the last success, rather than erasing it',
        () async {
          // "Last backed up on Tuesday" is the true and useful thing to say
          // after a failure. Clearing it replaces it with nothing.
          final harness = Harness();
          harness.start();

          await harness.goOnline();
          final succeededAt = harness.state.lastSucceededAt;
          expect(succeededAt, isNotNull);

          harness.drain.failure = StateError('the network went away mid-push');
          await harness.service.syncNow();

          expect(harness.state.status, SyncStatus.failed);
          expect(harness.state.lastSucceededAt, succeededAt);
        },
      );

      test('a later success clears the message', () async {
        final harness = Harness();
        harness.start();

        harness.drain.failure = StateError('the network went away mid-push');
        await harness.service.syncNow();
        expect(harness.state.errorMessage, isNotNull);

        harness.drain.failure = null;
        await harness.service.syncNow();

        expect(harness.state.status, SyncStatus.idle);
        expect(harness.state.errorMessage, isNull);
      });

      test('the next edge retries after a failure', () async {
        final harness = Harness();
        harness.start();

        harness.drain.failure = StateError('the network went away mid-push');
        await harness.goOnline();
        expect(harness.state.status, SyncStatus.failed);

        harness.drain.failure = null;
        await harness.goOffline();
        await harness.goOnline();

        expect(harness.drain.runs, 2);
        expect(harness.state.status, SyncStatus.idle);
      });
    });

    group('re-entrancy', () {
      test(
        'a second request queues rather than running beside the first',
        () async {
          // Two concurrent drains would race for the same pending rows and the
          // same cursor for no gain.
          final harness = Harness();
          harness.start();

          final gate = Completer<void>();
          harness.drain.gate = gate;
          final first = harness.service.syncNow();
          await harness.settle();
          expect(harness.drain.runs, 1);

          // Both of these find a drain in flight, mark it dirty and return at
          // once rather than waiting on it.
          final second = harness.service.syncNow();
          final third = harness.service.syncNow();
          await harness.settle();
          expect(harness.drain.runs, 1, reason: 'still just the one in flight');

          // Cleared before releasing, so the queued repeat runs straight through.
          harness.drain.gate = null;
          gate.complete();
          await Future.wait(<Future<void>>[first, second, third]);

          expect(
            harness.drain.runs,
            2,
            reason: 'two queued requests collapse into one repeat, not two',
          );
          expect(harness.state.status, SyncStatus.idle);
        },
      );

      test('an edge during a drain is not dropped', () async {
        // The drain already running may have read the pending set before the
        // write that edge is about to make pushable.
        final harness = Harness();
        harness.start();

        harness.drain.gate = Completer<void>();
        await harness.goOnline();
        expect(harness.drain.runs, 1);

        await harness.goOffline();
        harness.connectivity.add(true);
        await harness.settle();
        expect(
          harness.drain.runs,
          1,
          reason: 'queued behind the one in flight',
        );

        final gate = harness.drain.gate!;
        harness.drain.gate = null;
        gate.complete();
        await harness.settle();

        expect(harness.drain.runs, 2);
      });
    });
  });
}
