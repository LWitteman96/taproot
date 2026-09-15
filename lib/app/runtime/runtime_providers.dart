/// The two non-deterministic sources the app reads from, behind providers so a
/// test can replace them.
///
/// They live together because they fail the same way. The engine takes an
/// explicit `at` for every derivation, and completions are keyed by an id
/// generated client-side before insert — both of which are only testable while
/// callers ask for time and identity rather than reaching for [DateTime.now]
/// and `Uuid()` in the middle of a method. One override each keeps that seam
/// intact past the engine's edge.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Now, in **local** time.
///
/// Local is not incidental. Every window in the engine is local-calendar
/// arithmetic, and a UTC "now" would droop half the world's plants at the wrong
/// midnight.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// A fresh identifier for a row that is about to be written.
///
/// Completions are append-only events keyed by `(habitId, id)` with the id
/// minted here, on the device, before the insert — which is what makes
/// multi-device sync a union rather than a merge.
final newIdProvider = Provider<String Function()>((ref) {
  const uuid = Uuid();
  return uuid.v4;
});
