import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Collapses ledger rows that account for the same expected occasion.
///
/// **Why there can be more than one.** The ledger's rule is one row per habit
/// per local date, and the local write path enforces it — `saveNudge` throws
/// `DuplicateOccasionException` on a clash. Sync does not go through that path:
/// it writes rows by key, and two devices that each planned the same evening
/// minted their own UUID for it. So a pull can put a second row for one
/// occasion next to the first, and neither device did anything wrong.
///
/// **Why it matters.** Those rows are autonomy's denominator (growth spec §6).
/// Two rows for one occasion means one expected occasion counted twice, so a
/// habit that stood on its own once looks like it stood on its own once out of
/// two — autonomy halves, and the graduation gate it feeds moves out of reach
/// for a user whose only mistake was owning a second device. The fade counters
/// read the same rows and would fade against an inflated history.
///
/// **Why at read rather than by deleting one.** No client role has DELETE on
/// any table, deliberately: sync is a union, so rows must never go backwards.
/// A duplicate is therefore permanent on the server and would be re-pulled
/// forever, which makes dropping it locally a thing that undoes itself every
/// cycle. Collapsing at read is idempotent, survives re-pulls, and needs no
/// grant that would weaken the union.
///
/// The merge:
///
/// - **Identity goes to the lowest id**, which is arbitrary but *stable*. Both
///   devices reach the same answer without talking to each other, and they keep
///   reaching it after a re-pull — which a "first one written" rule would not,
///   since the rows can arrive in either order.
/// - **Flags are OR'd.** `sent` means a notification was queued with the OS, so
///   if either device queued one, one was queued. `confirmed` and `declined`
///   are answers the user gave, and an answer given on one device is still an
///   answer — it may have been written by a background isolate from the shade,
///   which is the normal path.
/// - **`scheduledFor` is the earliest of them**, because that is the one that
///   would have fired first. It is a record of what was planned, not an
///   instruction: `NudgeScheduler` recomputes `nudgeDeliveryTime(occasion)`
///   from the occasion itself, and that recomputation is authoritative. This
///   column exists so a later diagnostic can see what the devices intended.
/// - **The absorbed ids are carried**, on [NudgeRecord.mergedIds]. The merged
///   record is synthetic — its `id` comes from one row and its `sent` may come
///   from another — so anything treating the id as an *addressable identity*
///   rather than as a label needs the rest of them. The scheduler does: it asks
///   the OS whether `notificationIdFor(id)` is still pending, and without the
///   absorbed ids a `sent` OR'd in from the other row looks like a notification
///   the OS lost, so it queues a second one for an evening that already has
///   one. Two nudges, one occasion, and nothing to cancel the first with
///   because that id is never looked up again.
List<NudgeRecord> collapseDuplicateOccasions(Iterable<NudgeRecord> nudges) {
  final byOccasion = <String, List<NudgeRecord>>{};
  for (final nudge in nudges) {
    final key = '${nudge.habitId} ${LocalDate.from(nudge.expectedOccasionAt)}';
    byOccasion.putIfAbsent(key, () => <NudgeRecord>[]).add(nudge);
  }

  final collapsed = byOccasion.values.map(_merge).toList()
    ..sort((a, b) {
      final byTime = a.expectedOccasionAt.compareTo(b.expectedOccasionAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  return collapsed;
}

NudgeRecord _merge(List<NudgeRecord> group) {
  if (group.length == 1) return group.single;

  final canonical = group.reduce((a, b) => a.id.compareTo(b.id) <= 0 ? a : b);

  DateTime? earliestScheduled;
  var sent = false;
  var confirmed = false;
  var declined = false;
  for (final nudge in group) {
    sent |= nudge.sent;
    confirmed |= nudge.confirmed;
    declined |= nudge.declined;

    final scheduledFor = nudge.scheduledFor;
    if (scheduledFor == null) continue;
    if (earliestScheduled == null || scheduledFor.isBefore(earliestScheduled)) {
      earliestScheduled = scheduledFor;
    }
  }

  return canonical.copyWith(
    sent: sent,
    confirmed: confirmed,
    declined: declined,
    scheduledFor: () => earliestScheduled,
    mergedIds: <String>[
      for (final nudge in group)
        if (nudge.id != canonical.id) nudge.id,
    ]..sort(),
  );
}
