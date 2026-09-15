import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/domain/plant_descriptions.dart';

void main() {
  group('plant descriptions', () {
    test('every stage has a label', () {
      for (final stage in Stage.values) {
        expect(stageLabel(stage), isNotEmpty);
      }
    });

    test('vitality bands run from thriving to fully wilted', () {
      expect(vitalityLabel(1), 'thriving');
      expect(vitalityLabel(0.8), 'healthy');
      expect(vitalityLabel(0.4), 'drooping');
      expect(vitalityLabel(0.1), 'wilting');
      expect(vitalityLabel(0), 'fully wilted');
    });

    test('root depth is described as understanding, not effort', () {
      expect(rootDepthLabel(0.9), 'deep roots');
      expect(rootDepthLabel(0.6), 'established roots');
      expect(rootDepthLabel(0.35), 'taking root');
      expect(rootDepthLabel(0.1), 'shallow roots');
      expect(rootDepthLabel(0), 'no roots yet');
    });

    test('the semantic label carries what the picture would have said', () {
      final label = plantSemanticLabel(
        habitName: 'Morning walk',
        stage: Stage.young,
        vitality: 0.3,
        rootDepth: 0.1,
        isShallowRooted: true,
        isPaused: false,
      );

      expect(label, contains('Morning walk'));
      expect(label, contains('young'));
      expect(label, contains('drooping'));
      expect(label, contains('shallow roots'));
      expect(label, contains('growing faster than its roots'));
    });

    test('a paused plant reads as paused rather than as drooping', () {
      // Paused days are excluded from every engine window, so reporting the
      // vitality of a habit nobody is being asked to do would be a rebuke for
      // something the user explicitly turned off.
      final label = plantSemanticLabel(
        habitName: 'Morning walk',
        stage: Stage.young,
        vitality: 0,
        rootDepth: 0.4,
        isShallowRooted: false,
        isPaused: true,
      );

      expect(label, contains('paused'));
      expect(label, isNot(contains('wilted')));
    });
  });
}
