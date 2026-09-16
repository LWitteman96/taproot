import 'package:meta/meta.dart';

/// What sync is doing, as far as the UI is concerned.
enum SyncStatus {
  /// Nothing to do, or the last drain finished. The normal resting state.
  idle,

  /// A drain is running. Never blocks anything — the local store is primary,
  /// so this is information, not a wait.
  syncing,

  /// The last drain threw. The next connectivity edge retries; there is no
  /// backoff loop, because the trigger is an event rather than a poll.
  failed,

  /// There is a backend, but nobody is signed in.
  ///
  /// Distinct from [idle] for the same reason [unavailable] is: a drain that
  /// returned early because there was nowhere to send anything did not back
  /// anything up, and [SyncState.lastSucceededAt] must not move for it. Distinct
  /// from [unavailable] because this one is fixed by signing in, and the UI
  /// has something to offer the user about it.
  signedOut,

  /// This build has no backend to sync with.
  ///
  /// A designed state, not an error: only the dev flavor has credentials until
  /// a remote project is provisioned. Distinct from [idle] on purpose — an app
  /// that shows "all backed up" while backing nothing up is lying, and the
  /// difference is invisible from the status alone if the two share a value.
  unavailable,
}

/// The sync engine's state.
@immutable
class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSucceededAt,
    this.errorMessage,
  });

  final SyncStatus status;

  /// When a drain last finished cleanly, or null if one never has.
  ///
  /// This is the number worth showing a user who wants to know their work is
  /// safe — "synced 4 minutes ago" answers the question that [status] only
  /// implies.
  final DateTime? lastSucceededAt;

  /// A sentence for the user about the last failure, cleared by the next
  /// success. Failures reach the UI as state rather than as an exception, the
  /// same way the garden's do.
  final String? errorMessage;

  bool get isSyncing => status == SyncStatus.syncing;

  /// Whether this build can sync at all.
  bool get isAvailable => status != SyncStatus.unavailable;

  /// Whether the last drain actually moved data.
  ///
  /// The question [lastSucceededAt] is only meaningful for. Read it before
  /// rendering "all backed up": [SyncStatus.idle] is the only status that
  /// earns that sentence.
  bool get isBackedUp => status == SyncStatus.idle && lastSucceededAt != null;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? Function()? lastSucceededAt,
    String? Function()? errorMessage,
  }) => SyncState(
    status: status ?? this.status,
    lastSucceededAt: lastSucceededAt != null
        ? lastSucceededAt()
        : this.lastSucceededAt,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.status == status &&
      other.lastSucceededAt == lastSucceededAt &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(status, lastSucceededAt, errorMessage);

  @override
  String toString() => 'SyncState($status, last success: $lastSucceededAt)';
}

/// The app's voice for a failed drain. Kept here so a test can name it without
/// matching a string literal twice.
const String couldNotSyncMessage =
    'Your garden could not be backed up just now. Nothing has been lost — it '
    'is all on this device, and this will try again by itself.';
