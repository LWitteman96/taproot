import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/startup/app_startup.dart';

import '../../../utils/store_fixtures.dart';

/// An opener that fails the first [failures] calls and then succeeds.
///
/// Counting the calls is the whole point: a retry that re-reads a cached error
/// looks identical to a working one from the outside, and only the call count
/// tells the two apart.
class CountingOpener {
  CountingOpener({this.failures = 0});

  final int failures;
  int calls = 0;
  final List<Database> opened = <Database>[];

  Future<Database> call() async {
    calls++;
    if (calls <= failures) {
      throw StateError('the database file is unreadable');
    }
    final database = await openTestDatabase();
    opened.add(database);
    return database;
  }
}

ProviderContainer containerWith(CountingOpener opener) {
  final container = ProviderContainer(
    overrides: [databaseOpenerProvider.overrideWithValue(opener.call)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Waits for an asynchronous close to land, or gives up.
///
/// `ref.onDispose(database.close)` starts the close synchronously, but sqflite
/// finishes it on its background isolate, so the flag flips several event-loop
/// turns later. A single `Duration.zero` hop was enough most of the time, which
/// is the worst kind of enough.
Future<void> waitForClose(Database database) async {
  for (var attempt = 0; attempt < 200 && database.isOpen; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Matcher throwsMessage(String fragment) => throwsA(
  isA<Object>().having(
    (error) => error.toString(),
    'toString',
    contains(fragment),
  ),
);

void main() {
  group('app startup', () {
    test('resolves once the database is open', () async {
      final opener = CountingOpener();
      final container = containerWith(opener);

      await container.read(appStartupProvider.future);

      expect(opener.calls, 1);
      expect(container.read(appStartupProvider).hasValue, isTrue);
      expect(container.read(appDatabaseProvider), isA<Database>());
      expect(container.read(appDatabaseProvider).isOpen, isTrue);
    });

    test(
      'opens the database exactly once however many readers there are',
      () async {
        final opener = CountingOpener();
        final container = containerWith(opener);

        await container.read(appStartupProvider.future);
        container.read(appDatabaseProvider);
        await container.read(openedDatabaseProvider.future);

        expect(opener.calls, 1);
      },
    );

    test('a failed open lands in the provider rather than crashing', () async {
      final opener = CountingOpener(failures: 1);
      final container = containerWith(opener);

      await expectLater(
        container.read(appStartupProvider.future),
        throwsMessage('the database file is unreadable'),
      );
      expect(container.read(appStartupProvider).hasError, isTrue);
    });

    test(
      'reading the database before it is open throws rather than returning null',
      () {
        final opener = CountingOpener();
        final container = containerWith(opener);

        // Riverpod wraps anything a provider throws, and the wrapper is not part
        // of its public API, so this asserts on the message rather than the type.
        expect(
          () => container.read(appDatabaseProvider),
          throwsMessage('AsyncValueIsLoadingException'),
        );
      },
    );

    test(
      'reading the database after a failed open surfaces that failure',
      () async {
        final opener = CountingOpener(failures: 1);
        final container = containerWith(opener);

        await expectLater(
          container.read(appStartupProvider.future),
          throwsMessage('the database file is unreadable'),
        );
        expect(
          () => container.read(appDatabaseProvider),
          throwsMessage('the database file is unreadable'),
        );
      },
    );

    test(
      'retrying re-opens the database instead of re-reading the failure',
      () async {
        final opener = CountingOpener(failures: 1);
        final container = containerWith(opener);

        await expectLater(
          container.read(appStartupProvider.future),
          throwsMessage('the database file is unreadable'),
        );
        expect(opener.calls, 1);

        retryAppStartup(container);

        await container.read(appStartupProvider.future);
        expect(opener.calls, 2);
        expect(container.read(appDatabaseProvider).isOpen, isTrue);
      },
    );

    test(
      'invalidating the startup provider alone would re-read the cached failure',
      () async {
        // This is the trap [appStartupRetryTargets] exists to avoid, and it is
        // asserted rather than described so that narrowing the retry target
        // fails the suite instead of shipping a dead retry button.
        final opener = CountingOpener(failures: 1);
        final container = containerWith(opener);

        await expectLater(
          container.read(appStartupProvider.future),
          throwsMessage('the database file is unreadable'),
        );

        container.invalidate(appStartupProvider);

        await expectLater(
          container.read(appStartupProvider.future),
          throwsMessage('the database file is unreadable'),
        );
        expect(
          opener.calls,
          1,
          reason: 'the opener was never called again, so nothing was retried',
        );
      },
    );

    test('closes the database when the container is disposed', () async {
      final opener = CountingOpener();
      final container = ProviderContainer(
        overrides: [databaseOpenerProvider.overrideWithValue(opener.call)],
      );

      await container.read(appStartupProvider.future);
      final database = opener.opened.single;
      expect(database.isOpen, isTrue);

      container.dispose();
      await waitForClose(database);

      expect(database.isOpen, isFalse);
    });

    test('closes the superseded database when startup is retried', () async {
      final opener = CountingOpener();
      final container = containerWith(opener);

      await container.read(appStartupProvider.future);
      final first = opener.opened.single;

      retryAppStartup(container);
      await container.read(appStartupProvider.future);
      await waitForClose(first);

      expect(opener.opened, hasLength(2));
      expect(first.isOpen, isFalse, reason: 'the first handle must not leak');
      expect(opener.opened.last.isOpen, isTrue);
    });
  });
}
