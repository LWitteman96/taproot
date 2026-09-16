/// What the done state says.
///
/// check-in-design §7.1 is a table of five rows and one hard rule: **no credit
/// values and no reflection count, in any state**. Credit is an internal
/// weighting, and showing "+½ credit · 3.50 reflections" turns a moment of
/// being understood into a scoreboard.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/reflection/widgets/check_in_done.dart';

void main() {
  CheckInDone done({
    Framing framing = Framing.discovery,
    InputMode inputMode = InputMode.chip,
    String? commitDay = 'Tomorrow',
    bool declined = false,
  }) => CheckInDone(
    habitId: 'habit-1',
    framing: framing,
    inputMode: inputMode,
    ticker: GardenTicker.still,
    onBack: () {},
    commitDay: commitDay,
    declined: declined,
  );

  group('the title', () {
    test('a substantive answer deepened the roots', () {
      expect(done().title, CheckInDone.rootsTitle);
    });

    test('a diagnosis is thanked, not congratulated', () {
      // Nothing grew: the habit did not happen. "Roots deepened" over a miss
      // would be the app celebrating the wrong thing.
      expect(
        done(framing: Framing.diagnosis).title,
        CheckInDone.diagnosisTitle,
      );
    });

    test('an honest blank is simply noted', () {
      expect(
        done(inputMode: InputMode.cantRemember).title,
        CheckInDone.blankTitle,
      );
    });
  });

  group('the sub line', () {
    test('says how deep the roots are, in the app-wide words', () {
      // `rootDepthLabel`'s bands, not the prototype's — one vocabulary for
      // roots, or the garden's card and the sheet describe the same plant
      // differently.
      expect(done().subLine(0.6), 'Established roots · Tomorrow is set');
      expect(done().subLine(0.1), 'Shallow roots · Tomorrow is set');
    });

    test('an honest blank still counts', () {
      expect(
        done(inputMode: InputMode.cantRemember).subLine(0.4),
        'An honest blank still counts. · Tomorrow is set',
      );
    });

    test('a different day is acknowledged rather than corrected', () {
      // A decline is data, not a failure.
      expect(
        done(declined: true).subLine(0.6),
        'Established roots · ${CheckInDone.differentDaySub}',
      );
    });

    test('a skipped commit step mentions no day at all', () {
      // Promising "Tomorrow is set" when nothing was set would be a small lie
      // in the one place the app is asking to be trusted.
      expect(done(commitDay: null).subLine(0.6), 'Established roots');
    });

    test('never a credit value, never a reflection count', () {
      for (final mode in InputMode.values) {
        for (final framing in Framing.values) {
          final line = done(framing: framing, inputMode: mode).subLine(0.62);
          expect(line, isNot(contains('credit')));
          expect(line, isNot(contains('½')));
          expect(line, isNot(matches(RegExp(r'\d'))));
        }
      }
    });
  });
}
