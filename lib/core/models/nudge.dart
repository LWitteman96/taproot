import 'package:meta/meta.dart';

import 'package:taproot/core/utils/json_codec.dart';

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
    this.mergedIds = const <String>[],
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

  /// The other ledger ids this row absorbed, if it is a collapsed one.
  ///
  /// **A read-time artifact, never persisted.** `collapseDuplicateOccasions`
  /// merges rows that two devices each minted for one expected occasion, and
  /// the record it returns is synthetic: [id] comes from one row and [sent] may
  /// come from another. That is right for the *measurement* — one occasion, one
  /// entry in autonomy's denominator — and wrong for anything that treats [id]
  /// as an addressable identity.
  ///
  /// The scheduler is exactly that: it asks the OS whether
  /// `notificationIdFor(id)` is still pending, and a `sent` OR'd in from a row
  /// whose notification it never queued reads as one the OS lost, so it queues
  /// a second notification for an evening that already has one. Carrying the
  /// absorbed ids lets it ask about all of them instead.
  ///
  /// Empty for every row that came out of the store on its own, which is all of
  /// them until two devices plan the same evening. [toJson] omits it and
  /// [fromJson] does not read it — there is no column, and a collapse is
  /// recomputed on every read.
  final List<String> mergedIds;

  factory NudgeRecord.fromJson(Map<String, Object?> json) => NudgeRecord(
    id: requireString(json, 'id'),
    habitId: requireString(json, 'habit_id'),
    expectedOccasionAt: requireDateTime(json, 'expected_occasion_at'),
    sent: readBool(json, 'sent'),
    scheduledFor: readDateTime(json, 'scheduled_for'),
    confirmed: readBool(json, 'confirmed'),
    declined: readBool(json, 'declined'),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'habit_id': habitId,
    'expected_occasion_at': encodeDateTime(expectedOccasionAt),
    'scheduled_for': encodeDateTime(scheduledFor),
    'sent': sent,
    'confirmed': confirmed,
    'declined': declined,
  };

  NudgeRecord copyWith({
    String? id,
    String? habitId,
    DateTime? expectedOccasionAt,
    bool? sent,
    DateTime? Function()? scheduledFor,
    bool? confirmed,
    bool? declined,
    List<String>? mergedIds,
  }) => NudgeRecord(
    id: id ?? this.id,
    habitId: habitId ?? this.habitId,
    expectedOccasionAt: expectedOccasionAt ?? this.expectedOccasionAt,
    sent: sent ?? this.sent,
    scheduledFor: scheduledFor != null ? scheduledFor() : this.scheduledFor,
    confirmed: confirmed ?? this.confirmed,
    declined: declined ?? this.declined,
    mergedIds: mergedIds ?? this.mergedIds,
  );

  /// Every ledger id that accounts for this occasion, this row's own first.
  ///
  /// What a caller wants whenever it is asking about the *occasion* rather than
  /// about this particular row — see [mergedIds].
  List<String> get occasionIds => <String>[id, ...mergedIds];

  @override
  String toString() => 'NudgeRecord($id, $expectedOccasionAt, sent: $sent)';
}
