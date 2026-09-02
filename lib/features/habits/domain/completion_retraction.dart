import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Whether a completion can still be undone at [at].
///
/// A completion is undoable for the rest of the **local calendar day** it falls
/// on. Two things follow from that boundary, and both are deliberate:
///
/// - It covers the accidental tap while browsing the garden *and* the honest
///   evening correction, without letting anyone rewrite last week.
/// - Because it is bounded to one day, an undo can only ever un-earn a stage
///   the habit reached that same day. The ladder is a replay over history, so a
///   shrinking history replays a lower stage — the window is what keeps that
///   from reaching back into a plant someone grew weeks ago.
///
/// The boundary is midnight, not a stopwatch: a tap at 23:00 stops being
/// undoable an hour later, one at 00:30 stays undoable for nearly a day. That
/// asymmetry is the point — midnight is the edge users reason about, and it is
/// the same edge every engine window uses.
///
/// One known limit: a completion *backfilled* onto an earlier day is judged on
/// the day it records, not the day it was entered, so it is not undoable. Undo
/// is scoped to today's tap; correcting an older entry is the unbounded case
/// this policy deliberately does not open.
bool isRetractable(Completion completion, {required DateTime at}) =>
    LocalDate.from(completion.completedAt) == LocalDate.from(at);
