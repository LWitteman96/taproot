import 'package:meta/meta.dart';

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
