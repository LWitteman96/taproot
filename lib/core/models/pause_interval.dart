import 'package:meta/meta.dart';

import 'package:taproot/core/utils/json_codec.dart';

/// A stretch of paused days (growth spec §7).
///
/// Paused days are excluded from every window — they are not misses — and
/// vitality freezes across them. Without this, honesty is punished and users
/// learn to lie to the app.
@immutable
class PauseInterval {
  const PauseInterval({required this.startedAt, this.endedAt});

  final DateTime startedAt;

  /// Null while the pause is still running.
  final DateTime? endedAt;

  bool get isOpen => endedAt == null;

  /// The interval only. Row identity — `id` and `habit_id` — belongs to the
  /// `habit_pauses` row and is added by the repository, because the engine
  /// reasons about the stretch of days, not about which row recorded it.
  factory PauseInterval.fromJson(Map<String, Object?> json) => PauseInterval(
    startedAt: requireDateTime(json, 'started_at'),
    endedAt: readDateTime(json, 'ended_at'),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'started_at': encodeDateTime(startedAt),
    'ended_at': encodeDateTime(endedAt),
  };

  PauseInterval copyWith({
    DateTime? startedAt,
    DateTime? Function()? endedAt,
  }) => PauseInterval(
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt != null ? endedAt() : this.endedAt,
  );

  @override
  String toString() => 'PauseInterval($startedAt → ${endedAt ?? 'open'})';
}
