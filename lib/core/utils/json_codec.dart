/// Decoding helpers shared by every model's `fromJson`.
///
/// One model has to survive three encodings of the same value: a Dart object, a
/// SQLite row, and a Supabase JSON payload. SQLite has no boolean type and
/// returns 0/1 where PostgREST returns true/false, and PostgREST returns a
/// JSON number where SQLite returns an int. Every reader here accepts both, so
/// a row read back from the local store and the same row pulled from Supabase
/// decode to the same object.
///
/// Decoding is strict about *missing* and *unrecognised* values: a row that
/// cannot be read is a [FormatException] naming the column, not a silently
/// defaulted model. The one carve-out is [readOpenEnum], for the columns whose
/// value set is deliberately open-ended — see its doc for why strictness is the
/// wrong default there specifically.
library;

/// UTC ISO-8601 at millisecond precision — the one representation on the wire
/// and on disk.
///
/// Timestamps are stored as UTC and every window calculation converts to local
/// first (see `local_dates.dart`). ISO-8601 in UTC also sorts lexicographically,
/// which is what lets the store order and range-scan on a TEXT column — but
/// only at a *fixed width*: `DateTime.toIso8601String` prints six fractional
/// digits when microseconds are non-zero and three when they are not, and
/// `"...00.000Z" > "...00.000123Z"` as a string. Truncating to milliseconds
/// keeps every timestamp the same width, so string order is time order.
/// Sub-millisecond precision means nothing to a habit completion.
String? encodeDateTime(DateTime? value) => value == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(
        value.millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();

DateTime requireDateTime(Map<String, Object?> json, String key) =>
    readDateTime(json, key) ?? (throw _missing(key, json));

DateTime? readDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is! String) throw _wrongType(key, value, 'a date time');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw _wrongType(key, value, 'a date time');
  return parsed.toUtc();
}

/// Reads a boolean written by either SQLite (0/1) or PostgREST (true/false).
bool readBool(Map<String, Object?> json, String key, {bool orElse = false}) =>
    readNullableBool(json, key) ?? orElse;

/// As [readBool], but keeps "not answered" distinct from "answered no".
bool? readNullableBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  if (value is int) return value != 0;
  throw _wrongType(key, value, 'a boolean');
}

String? encodeEnum(Enum? value) => value?.name;

T requireEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
) => readEnum(json, key, values) ?? (throw _missing(key, json));

T? readEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw _wrongType(key, value, 'an enum name');
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException(
    '$key: "$value" is not one of ${values.map((v) => v.name).join(', ')}',
  );
}

/// As [readEnum], but an **unrecognised** value reads as null instead of
/// throwing. A value of the wrong *type* is still a [FormatException].
///
/// For columns whose value set is deliberately open — ones that widen without a
/// schema change and carry no `CHECK`. Strictness is right for a closed set,
/// where an unknown value means the row is corrupt; it is wrong for an open
/// one, where an unknown value most likely means this build is older than the
/// device that wrote it, or the row came down from a server that has since
/// learned a new value.
///
/// The failure being avoided is disproportionate: `fromJson` throwing takes
/// `allHabits()` with it, which takes the whole garden into its unreadable
/// state — over one optional field. Reading it as null degrades exactly as far
/// as the field's own spec says it may.
///
/// **Not a general-purpose loosening.** Reach for [readEnum] unless the column
/// is genuinely open, and say which in a comment at the call site.
T? readOpenEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw _wrongType(key, value, 'an enum name');
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  return null;
}

String requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) throw _missing(key, json);
  if (value is! String) throw _wrongType(key, value, 'a string');
  return value;
}

String? readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw _wrongType(key, value, 'a string');
  return value;
}

int requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) throw _missing(key, json);
  if (value is int) return value;
  // PostgREST hands back JSON numbers, which decode as double.
  if (value is double && value == value.roundToDouble()) return value.toInt();
  throw _wrongType(key, value, 'an integer');
}

FormatException _missing(String key, Map<String, Object?> json) =>
    FormatException('$key is missing (keys: ${json.keys.join(', ')})');

FormatException _wrongType(String key, Object value, String expected) =>
    FormatException('$key: expected $expected, got ${value.runtimeType}');
