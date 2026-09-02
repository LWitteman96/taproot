import 'package:meta/meta.dart';

/// One expected occasion in the nudge ledger.
///
/// A row exists for every expected occasion **including the ones the engine
/// deliberately stayed silent on** (growth spec §6). Those skipped nudges are
/// the measurement instrument for autonomy — they cannot be inferred from the
/// absence of a notification.
@immutable
class NudgeRecord {
  const NudgeRecord({
    required this.id,
    required this.habitId,
    required this.expectedOccasionAt,
    required this.sent,
    this.scheduledFor,
    this.confirmed = false,
    this.declined = false,
  });

  final String id;
  final String habitId;

  /// The occasion this row accounts for. Its local date is what a completion
  /// is matched against.
  final DateTime expectedOccasionAt;

  /// False when the engine chose to fade this nudge. Those are the occasions
  /// autonomy is measured over.
  final bool sent;

  final DateTime? scheduledFor;
  final bool confirmed;
  final bool declined;

  NudgeRecord copyWith({
    String? id,
    String? habitId,
    DateTime? expectedOccasionAt,
    bool? sent,
    DateTime? Function()? scheduledFor,
    bool? confirmed,
    bool? declined,
  }) => NudgeRecord(
    id: id ?? this.id,
    habitId: habitId ?? this.habitId,
    expectedOccasionAt: expectedOccasionAt ?? this.expectedOccasionAt,
    sent: sent ?? this.sent,
    scheduledFor: scheduledFor != null ? scheduledFor() : this.scheduledFor,
    confirmed: confirmed ?? this.confirmed,
    declined: declined ?? this.declined,
  );

  @override
  String toString() => 'NudgeRecord($id, $expectedOccasionAt, sent: $sent)';
}
