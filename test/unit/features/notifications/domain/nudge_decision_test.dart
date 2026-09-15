import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/autonomy.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/notifications/domain/nudge_decision.dart';

/// Nudge fading (growth spec §6).
///
/// Fading is load-bearing rather than a politeness feature: the occasions it
/// stays silent on are the only ones autonomy can be measured over. So the
/// rule is tested for the *rate it actually produces*, not for a tendency.
void main() {
  /// Replays [occasions] decisions at a fixed rate and returns which ones were
  /// nudged, in order.
  List<bool> replay(double rate, int occasions) {
    final sent = <bool>[];
    var priorSent = 0;
    for (var index = 0; index < occasions; index++) {
      final send = shouldSendNudge(
        nudgeRate: rate,
        priorOccasions: index,
        priorSent: priorSent,
      );
      sent.add(send);
      if (send) priorSent++;
    }
    return sent;
  }

  int countSent(double rate, int occasions) =>
      replay(rate, occasions).where((sent) => sent).length;

  group('the fade rate is exact, not approximate', () {
    test('Young nudges 7 occasions in every 10', () {
      expect(countSent(0.70, 10), 7);
      expect(countSent(0.70, 20), 14);
      expect(countSent(0.70, 100), 70);
    });

    test('Mature nudges 4 in every 10', () {
      expect(countSent(0.40, 10), 4);
      expect(countSent(0.40, 100), 40);
    });

    test('Bloom spot-checks 1 in every 10', () {
      expect(countSent(0.10, 10), 1);
      expect(countSent(0.10, 100), 10);
    });

    test('every stage in the table lands on its own rate', () {
      for (final stage in Stage.values) {
        final rate = nudgeRateForStage(stage);
        expect(
          countSent(rate, 100),
          (rate * 100).round(),
          reason: '${stage.name} at $rate',
        );
      }
    });
  });

  group('the shape of the pattern', () {
    test('Sprout and Seedling are nudged every time', () {
      // 100% is not "almost always" — a habit that has not reached Young has
      // no un-nudged occasions at all, and so no autonomy measurement yet.
      expect(replay(1.0, 30), everyElement(isTrue));
    });

    test('it front-loads, so a new habit is never silent first', () {
      for (final rate in <double>[0.10, 0.40, 0.70, 1.0]) {
        expect(replay(rate, 5).first, isTrue, reason: 'rate $rate');
      }
    });

    test('it never opens a silent run longer than the rate implies', () {
      // The reason this is a rule rather than a coin flip: a random draw at
      // Bloom's 0.10 can go 30 occasions without a spot check, and the user
      // experiences that as the app having forgotten him.
      var longestGap = 0;
      var currentGap = 0;
      for (final sent in replay(0.10, 100)) {
        currentGap = sent ? 0 : currentGap + 1;
        longestGap = currentGap > longestGap ? currentGap : longestGap;
      }
      expect(longestGap, lessThanOrEqualTo(10));
    });

    test('it is deterministic — two replays of a ledger agree', () {
      expect(replay(0.70, 40), replay(0.70, 40));
    });
  });

  test('a rate change is absorbed rather than restarted', () {
    // A habit climbing Young → Mature carries Young's sent share with it. The
    // rule withholds until the share has fallen to the new rate instead of
    // resetting a counter and nudging through the transition.
    var priorSent = 14;
    var priorOccasions = 20; // 0.70 of 20

    final afterClimb = <bool>[];
    for (var step = 0; step < 10; step++) {
      final send = shouldSendNudge(
        nudgeRate: 0.40,
        priorOccasions: priorOccasions,
        priorSent: priorSent,
      );
      afterClimb.add(send);
      priorOccasions++;
      if (send) priorSent++;
    }

    expect(afterClimb, everyElement(isFalse));
    expect(priorSent / priorOccasions, closeTo(14 / 30, 1e-9));
  });

  group('decisions name why they are silent', () {
    test('only a withheld occasion is the engine measuring something', () {
      expect(
        const NudgeDecision.suppress(
          NudgeSuppression.withheld,
        ).isDeliberateSilence,
        isTrue,
      );

      for (final reason in <NudgeSuppression>[
        NudgeSuppression.deliveryPassed,
        NudgeSuppression.noPermission,
        NudgeSuppression.overCap,
      ]) {
        expect(
          NudgeDecision.suppress(reason).isDeliberateSilence,
          isFalse,
          reason: '${reason.name} is the app failing, not the engine choosing',
        );
      }
    });

    test('a send is not a suppression', () {
      expect(const NudgeDecision.send().shouldSend, isTrue);
      expect(const NudgeDecision.send().suppression, isNull);
    });
  });

  test('the stage table is the one in the growth spec', () {
    expect(EngineConstants.nudgeRateByStage[Stage.sprout], 1.0);
    expect(EngineConstants.nudgeRateByStage[Stage.seedling], 1.0);
    expect(EngineConstants.nudgeRateByStage[Stage.young], 0.70);
    expect(EngineConstants.nudgeRateByStage[Stage.mature], 0.40);
    expect(EngineConstants.nudgeRateByStage[Stage.bloom], 0.10);
  });
}
