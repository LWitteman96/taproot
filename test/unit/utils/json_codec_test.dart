import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/utils/json_codec.dart';

/// The codec is the seam between three encodings of the same value: Dart, a
/// SQLite row, and a Supabase JSON payload. SQLite has no boolean type and
/// hands back 0/1; PostgREST hands back true/false. Every reader here has to
/// accept both, or the same model breaks depending on which side it came from.
void main() {
  group('date times', () {
    test('encode to UTC ISO-8601 regardless of the input zone', () {
      final local = DateTime(2026, 1, 5, 9, 30);

      expect(encodeDateTime(local), local.toUtc().toIso8601String());
      expect(encodeDateTime(local.toUtc()), local.toUtc().toIso8601String());
    });

    test('encode at a fixed width, so string order is time order', () {
      // toIso8601String prints six fractional digits only when microseconds
      // are non-zero, and "…00.000Z" sorts *after* "…00.000123Z" as a string.
      // Every range scan in the store depends on that not happening.
      final coarse = DateTime.utc(2026, 3, 12, 8, 0, 0, 0, 0);
      final fine = DateTime.utc(2026, 3, 12, 8, 0, 0, 0, 123);

      expect(encodeDateTime(coarse), '2026-03-12T08:00:00.000Z');
      expect(encodeDateTime(fine), '2026-03-12T08:00:00.000Z');
      expect(encodeDateTime(coarse)!.length, encodeDateTime(fine)!.length);
      expect(
        encodeDateTime(
          DateTime.utc(2026, 3, 12, 8, 0, 1),
        )!.compareTo(encodeDateTime(fine)!),
        greaterThan(0),
      );
    });

    test('encode null to null', () {
      expect(encodeDateTime(null), isNull);
    });

    test('decode back to the same instant, as UTC', () {
      final local = DateTime(2026, 1, 5, 9, 30);
      final json = <String, Object?>{'at': encodeDateTime(local)};

      final decoded = requireDateTime(json, 'at');

      expect(decoded.isUtc, isTrue);
      expect(decoded.isAtSameMomentAs(local), isTrue);
    });

    test(
      'a missing required date time is a FormatException naming the key',
      () {
        expect(
          () => requireDateTime(const <String, Object?>{}, 'completed_at'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('completed_at'),
            ),
          ),
        );
      },
    );

    test('an optional date time decodes null', () {
      expect(readDateTime(const <String, Object?>{'at': null}, 'at'), isNull);
    });
  });

  group('booleans', () {
    test('read SQLite integers', () {
      expect(readBool(const <String, Object?>{'sent': 1}, 'sent'), isTrue);
      expect(readBool(const <String, Object?>{'sent': 0}, 'sent'), isFalse);
    });

    test('read PostgREST booleans', () {
      expect(readBool(const <String, Object?>{'sent': true}, 'sent'), isTrue);
      expect(readBool(const <String, Object?>{'sent': false}, 'sent'), isFalse);
    });

    test('fall back to the default when absent or null', () {
      expect(readBool(const <String, Object?>{}, 'sent'), isFalse);
      expect(
        readBool(const <String, Object?>{'sent': null}, 'sent', orElse: true),
        isTrue,
      );
    });

    test('a nullable boolean keeps null distinct from false', () {
      expect(
        readNullableBool(const <String, Object?>{'matched': null}, 'matched'),
        isNull,
      );
      expect(readNullableBool(const <String, Object?>{}, 'matched'), isNull);
      expect(
        readNullableBool(const <String, Object?>{'matched': 0}, 'matched'),
        isFalse,
      );
    });
  });

  group('enums', () {
    test('round-trip by name', () {
      final json = <String, Object?>{'cue_type': encodeEnum(CueType.location)};

      expect(json['cue_type'], 'location');
      expect(requireEnum(json, 'cue_type', CueType.values), CueType.location);
    });

    test('an unrecognised name is a FormatException listing the key', () {
      expect(
        () => requireEnum(
          const <String, Object?>{'framing': 'gratitude'},
          'framing',
          Framing.values,
        ),
        throwsA(
          isA<FormatException>()
              .having((error) => error.message, 'message', contains('framing'))
              .having(
                (error) => error.message,
                'message',
                contains('gratitude'),
              ),
        ),
      );
    });

    test('an optional enum decodes null', () {
      expect(
        readEnum(
          const <String, Object?>{'friction_type': null},
          'friction_type',
          FrictionType.values,
        ),
        isNull,
      );
      expect(encodeEnum(null), isNull);
    });
  });

  group('scalars', () {
    test('require a string', () {
      expect(
        requireString(const <String, Object?>{'name': 'Run'}, 'name'),
        'Run',
      );
      expect(
        () => requireString(const <String, Object?>{'name': null}, 'name'),
        throwsFormatException,
      );
    });

    test('require an int, accepting a JSON double that is whole', () {
      expect(requireInt(const <String, Object?>{'f': 3}, 'f'), 3);
      expect(requireInt(const <String, Object?>{'f': 3.0}, 'f'), 3);
      expect(
        () => requireInt(const <String, Object?>{'f': 3.5}, 'f'),
        throwsFormatException,
      );
    });
  });
}
