import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/roots.dart';
import 'package:taproot/core/models/reflection.dart';

import '../../utils/engine_builders.dart';

void main() {
  setUp(resetFixtureIds);

  group('root credit is framing x input mode', () {
    test('an autonomy answer is worth the most', () {
      expect(rootCreditFor(reflectionOn(0, framing: Framing.autonomy)), 1.5);
    });

    test('validation, discovery and diagnosis are worth a full point', () {
      expect(rootCreditFor(reflectionOn(0, framing: Framing.validation)), 1.0);
      expect(rootCreditFor(reflectionOn(0, framing: Framing.discovery)), 1.0);
      expect(rootCreditFor(reflectionOn(0, framing: Framing.diagnosis)), 1.0);
    });

    test('typing instead of tapping a chip changes nothing', () {
      expect(
        rootCreditFor(
          reflectionOn(
            0,
            framing: Framing.discovery,
            inputMode: InputMode.typed,
          ),
        ),
        1.0,
      );
    });

    test('a one-tap confirmation is worth half', () {
      expect(
        rootCreditFor(reflectionOn(0, framing: Framing.confirmation)),
        0.5,
      );
    });

    test("'can't remember' is worth 0.25 whatever was asked", () {
      // Honest evidence of autopilot is worth something, but it builds no cue
      // understanding and must never be worth what an answer is worth.
      for (final framing in Framing.values) {
        expect(
          rootCreditFor(
            reflectionOn(
              0,
              framing: framing,
              inputMode: InputMode.cantRemember,
            ),
          ),
          0.25,
          reason: 'framing: $framing',
        );
      }
    });

    test('a skipped prompt is worth nothing', () {
      expect(
        rootCreditFor(
          reflectionOn(
            0,
            framing: Framing.discovery,
            inputMode: InputMode.skipped,
          ),
        ),
        0,
      );
    });
  });

  group('R_raw = N / (N + 4)', () {
    test('the spec worked values', () {
      expect(rawRootDepth(4), closeTo(0.50, 1e-9));
      expect(rawRootDepth(10), closeTo(0.714286, 1e-6));
      expect(rawRootDepth(20), closeTo(0.833333, 1e-6));
    });

    test('is zero at zero and saturates below one', () {
      expect(rawRootDepth(0), 0);
      expect(rawRootDepth(1000), lessThan(1.0));
      expect(rawRootDepth(1000), greaterThan(0.99));
    });

    test('is steep early and flat later', () {
      // The fifth reflection teaches you a lot, the fiftieth almost nothing.
      expect(rawRootDepth(5) - rawRootDepth(4), greaterThan(0.04));
      expect(rawRootDepth(51) - rawRootDepth(50), lessThan(0.002));
    });
  });

  group('N is a weighted sum', () {
    test('adds credit per reflection', () {
      final habit = inputs(
        reflections: <Reflection>[
          reflectionOn(0, framing: Framing.autonomy),
          reflectionOn(1, framing: Framing.discovery),
          reflectionOn(2, framing: Framing.confirmation),
          reflectionOn(3, inputMode: InputMode.cantRemember),
          reflectionOn(4, inputMode: InputMode.skipped),
        ],
      );

      expect(
        weightedReflectionCount(inputs: habit, at: day(10)),
        closeTo(1.5 + 1.0 + 0.5 + 0.25, 1e-9),
      );
    });

    test('ignores reflections after the evaluation instant', () {
      final habit = inputs(reflections: reflectionsDaily(count: 10));

      expect(
        weightedReflectionCount(inputs: habit, at: day(3)),
        closeTo(4, 1e-9),
      );
    });
  });

  group('convergence c', () {
    test('six of eight naming the same cue gives 0.75', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 6; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
          reflectionOn(
            6,
            cueReported: 'felt restless',
            cueType: CueType.internal,
          ),
          reflectionOn(7, cueReported: 'lunchtime', cueType: CueType.time),
        ],
      );

      expect(
        computeConvergence(inputs: habit, at: day(10)),
        closeTo(0.75, 1e-9),
      );
    });

    test('a single consistent cue converges completely', () {
      final habit = inputs(reflections: reflectionsDaily(count: 8));

      expect(computeConvergence(inputs: habit, at: day(10)), 1.0);
    });

    test('eight different cues is noise, not a designed loop', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 8; i++) reflectionOn(i, cueReported: 'cue $i'),
        ],
      );

      expect(
        computeConvergence(inputs: habit, at: day(10)),
        closeTo(0.125, 1e-9),
      );
    });

    test('is measured over the last eight reflections only', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 12; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
          for (var i = 12; i < 20; i++) reflectionOn(i, cueReported: 'cue $i'),
        ],
      );

      expect(
        computeConvergence(inputs: habit, at: day(30)),
        closeTo(0.125, 1e-9),
      );
    });

    test('respects the evaluation instant', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 4; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
          for (var i = 4; i < 12; i++) reflectionOn(i, cueReported: 'cue $i'),
        ],
      );

      expect(computeConvergence(inputs: habit, at: day(3)), 1.0);
    });
  });

  group('c must not be vacuously true', () {
    test("eight can't-remembers converge on nothing, not on everything", () {
      // A naive modal share of an empty set returns 1.0, which would inflate
      // roots for precisely the least self-aware user.
      final habit = inputs(
        reflections: reflectionsDaily(
          count: 8,
          inputMode: InputMode.cantRemember,
        ),
      );

      expect(computeConvergence(inputs: habit, at: day(10)), 0.0);
    });

    test('fewer than three cue-bearing reflections gives c = 0', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 6; i++)
            reflectionOn(i, inputMode: InputMode.cantRemember),
          reflectionOn(6, cueReported: 'after breakfast'),
          reflectionOn(7, cueReported: 'after breakfast'),
        ],
      );

      expect(computeConvergence(inputs: habit, at: day(10)), 0.0);
    });

    test('three cue-bearing reflections is enough to measure', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 5; i++)
            reflectionOn(i, inputMode: InputMode.cantRemember),
          for (var i = 5; i < 8; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
        ],
      );

      expect(computeConvergence(inputs: habit, at: day(10)), 1.0);
    });

    test('skips are excluded from both numerator and denominator', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 4; i++)
            reflectionOn(i, inputMode: InputMode.skipped),
          for (var i = 4; i < 8; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
        ],
      );

      expect(computeConvergence(inputs: habit, at: day(10)), 1.0);
      expect(
        countsTowardConvergence(reflectionOn(0, inputMode: InputMode.skipped)),
        isFalse,
      );
      expect(
        countsTowardConvergence(
          reflectionOn(0, inputMode: InputMode.cantRemember),
        ),
        isFalse,
      );
      expect(countsTowardConvergence(reflectionOn(0)), isTrue);
    });
  });

  group('the internal-cue exemption', () {
    test('internal states converge on type, not on label', () {
      // "When I feel stressed" is not a badly-designed loop, so varying the
      // exact wording must not halve its roots.
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 8; i++)
            reflectionOn(
              i,
              cueReported: 'internal $i',
              cueType: CueType.internal,
            ),
        ],
      );

      expect(computeConvergence(inputs: habit, at: day(10)), 1.0);
    });

    test('external cues are still compared by exact label', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 4; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
          for (var i = 4; i < 8; i++)
            reflectionOn(i, cueReported: 'after coffee'),
        ],
      );

      expect(
        computeConvergence(inputs: habit, at: day(10)),
        closeTo(0.5, 1e-9),
      );
    });

    test('a mixed history takes the larger group', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 5; i++)
            reflectionOn(i, cueReported: 'mood $i', cueType: CueType.internal),
          for (var i = 5; i < 8; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
        ],
      );

      expect(
        computeConvergence(inputs: habit, at: day(10)),
        closeTo(0.625, 1e-9),
      );
    });

    test('convergence keys group internal cues and separate external ones', () {
      final stressed = reflectionOn(
        0,
        cueReported: 'felt stressed',
        cueType: CueType.internal,
      );
      final restless = reflectionOn(
        1,
        cueReported: 'felt restless',
        cueType: CueType.internal,
      );
      final breakfast = reflectionOn(2, cueReported: 'after breakfast');
      final coffee = reflectionOn(3, cueReported: 'after coffee');

      expect(convergenceKeyFor(stressed), convergenceKeyFor(restless));
      expect(convergenceKeyFor(breakfast), isNot(convergenceKeyFor(coffee)));
      expect(convergenceKeyFor(breakfast), isNot(convergenceKeyFor(stressed)));
    });
  });

  group('R = R_raw x (0.5 + 0.5c)', () {
    test('a scattered cue history halves root depth', () {
      final scattered = inputs(
        reflections: reflectionsDaily(
          count: 8,
          inputMode: InputMode.cantRemember,
        ),
      );
      final roots = computeRoots(inputs: scattered, at: day(10));

      expect(roots.weightedReflections, closeTo(2.0, 1e-9));
      expect(roots.raw, closeTo(2 / 6, 1e-9));
      expect(roots.convergence, 0.0);
      expect(roots.cueBearingReflections, 0);
      expect(roots.depth, closeTo(2 / 6 * 0.5, 1e-9));
    });

    test('twenty converged reflections clear the Bloom root gate', () {
      final habit = inputs(reflections: reflectionsDaily(count: 20));
      final roots = computeRoots(inputs: habit, at: day(30));

      expect(roots.weightedReflections, closeTo(20, 1e-9));
      expect(roots.convergence, 1.0);
      expect(roots.depth, closeTo(0.833333, 1e-6));
      expect(roots.depth, greaterThanOrEqualTo(0.75));
    });

    test('twenty reflections at c = 0.75 do not', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 12; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
          for (var i = 12; i < 18; i++)
            reflectionOn(i, cueReported: 'after breakfast'),
          reflectionOn(
            18,
            cueReported: 'walked past the gym',
            cueType: CueType.location,
          ),
          reflectionOn(
            19,
            cueReported: 'partner was going',
            cueType: CueType.social,
          ),
        ],
      );
      final roots = computeRoots(inputs: habit, at: day(30));

      expect(roots.convergence, closeTo(0.75, 1e-9));
      expect(roots.depth, closeTo(0.833333 * 0.875, 1e-6));
      expect(roots.depth, lessThan(0.75));
    });

    test('a user coasting on confirmations deepens roots, but slowly', () {
      final habit = inputs(
        reflections: reflectionsDaily(count: 20, framing: Framing.confirmation),
      );
      final roots = computeRoots(inputs: habit, at: day(30));

      expect(roots.weightedReflections, closeTo(10, 1e-9));
      expect(roots.depth, closeTo(10 / 14, 1e-9));
      expect(roots.depth, lessThan(0.75), reason: 'no blooming on taps alone');
    });

    test('roots are zero before any reflection', () {
      final roots = computeRoots(inputs: inputs(), at: day(10));

      expect(roots.weightedReflections, 0);
      expect(roots.depth, 0);
      expect(roots.convergence, 0);
    });
  });

  group('cue reliability', () {
    test('is the designed cue hit rate — "your cue worked 6 of 8 times"', () {
      final habit = inputs(
        reflections: <Reflection>[
          for (var i = 0; i < 6; i++)
            reflectionOn(
              i,
              framing: Framing.validation,
              matchedDesignedCue: true,
            ),
          for (var i = 6; i < 8; i++)
            reflectionOn(
              i,
              framing: Framing.validation,
              matchedDesignedCue: false,
            ),
        ],
      );

      expect(cueReliability(inputs: habit, at: day(10)), closeTo(0.75, 1e-9));
    });

    test('is null before the designed cue has been tested', () {
      final habit = inputs(reflections: reflectionsDaily(count: 4));

      expect(cueReliability(inputs: habit, at: day(10)), isNull);
    });

    test('is available as a raw fraction after three reflections', () {
      // Cold start: "your cue fired 2 of 3 times" is small, true, and framed as
      // calibration rather than as a score.
      final habit = inputs(
        reflections: <Reflection>[
          reflectionOn(
            0,
            framing: Framing.validation,
            matchedDesignedCue: true,
          ),
          reflectionOn(
            1,
            framing: Framing.validation,
            matchedDesignedCue: true,
          ),
          reflectionOn(
            2,
            framing: Framing.validation,
            matchedDesignedCue: false,
          ),
        ],
      );

      expect(cueReliability(inputs: habit, at: day(10)), closeTo(2 / 3, 1e-9));
    });
  });
}
