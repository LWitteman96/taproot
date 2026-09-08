import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:taproot/app/logging/logging.dart';
import 'package:taproot/core/utils/flavor.dart';

void main() {
  group('setupLogging', () {
    final records = <LogRecord>[];

    setUp(records.clear);
    tearDown(stopLogging);

    test('delivers a service logger to the sink', () {
      setupLogging(flavor: Flavor.dev, sink: records.add);

      Logger('LocalHabitService').severe('saveHabit failed');

      expect(records, hasLength(1));
      expect(records.single.loggerName, 'LocalHabitService');
      expect(records.single.message, 'saveHabit failed');
    });

    test('dev and stg let everything through', () {
      for (final flavor in <Flavor>[Flavor.dev, Flavor.stg]) {
        records.clear();
        setupLogging(flavor: flavor, sink: records.add);

        Logger('Sync').fine('a chatty detail');

        expect(records, hasLength(1), reason: '$flavor should log at FINE');
      }
    });

    test('prod keeps quiet below a warning', () {
      setupLogging(flavor: Flavor.prod, sink: records.add);

      Logger('Sync')
        ..fine('a chatty detail')
        ..info('a routine event')
        ..warning('something to look at');

      expect(records.map((record) => record.message), <String>[
        'something to look at',
      ]);
    });

    test('calling it twice does not double every line', () {
      setupLogging(flavor: Flavor.dev, sink: records.add);
      setupLogging(flavor: Flavor.dev, sink: records.add);

      Logger('Sync').info('once, please');

      expect(records, hasLength(1));
    });

    test('carries the error and stack trace through', () {
      setupLogging(flavor: Flavor.dev, sink: records.add);
      final error = StateError('boom');

      Logger(
        'LocalHabitService',
      ).severe('saveHabit failed', error, StackTrace.current);

      expect(records.single.error, same(error));
      expect(records.single.stackTrace, isNotNull);
    });

    test('stopLogging detaches the sink', () {
      setupLogging(flavor: Flavor.dev, sink: records.add);
      stopLogging();

      Logger('Sync').severe('nobody is listening');

      expect(records, isEmpty);
    });
  });
}
