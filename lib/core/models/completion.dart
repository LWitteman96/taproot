import 'package:meta/meta.dart';

/// How a completion got recorded.
enum CompletionSource { tap, nudgeConfirmation, backfill }

/// A watering event.
///
/// Completions are append-only and keyed by `(habitId, id)` with [id]
/// generated client-side before insert, so multi-device sync is a union rather
/// than a merge.
@immutable
class Completion {
  const Completion({
    required this.id,
    required this.habitId,
    required this.completedAt,
    this.wasNudged = false,
    this.source = CompletionSource.tap,
  });

  /// Client-generated UUID, stable across devices.
  final String id;
  final String habitId;

  /// Stored UTC; every window calculation converts to local first.
  final DateTime completedAt;

  /// Whether a nudge was sent for this occasion. The un-nudged completions are
  /// what autonomy measures (growth spec §6).
  final bool wasNudged;

  final CompletionSource source;

  Completion copyWith({
    String? id,
    String? habitId,
    DateTime? completedAt,
    bool? wasNudged,
    CompletionSource? source,
  }) => Completion(
    id: id ?? this.id,
    habitId: habitId ?? this.habitId,
    completedAt: completedAt ?? this.completedAt,
    wasNudged: wasNudged ?? this.wasNudged,
    source: source ?? this.source,
  );

  @override
  String toString() => 'Completion($id, $completedAt, wasNudged: $wasNudged)';
}
