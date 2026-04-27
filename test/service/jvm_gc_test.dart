import 'package:gitrinth/src/service/jvm_gc.dart';
import 'package:test/test.dart';

void main() {
  group('gcFlagsForJavaMajor', () {
    test('Java <8 -> empty', () {
      expect(gcFlagsForJavaMajor(7), isEmpty);
      expect(gcFlagsForJavaMajor(0), isEmpty);
    });

    test('Java 8-14 → unlock experimental + Shenandoah', () {
      for (final major in const [8, 11, 14]) {
        expect(
          gcFlagsForJavaMajor(major),
          const ['-XX:+UnlockExperimentalVMOptions', '-XX:+UseShenandoahGC'],
          reason: 'JDK $major needs unlocked Shenandoah',
        );
      }
    });

    test('Java 15-20 -> Shenandoah only', () {
      for (final major in const [15, 16, 17, 18, 19, 20]) {
        expect(
          gcFlagsForJavaMajor(major),
          const ['-XX:+UseShenandoahGC'],
          reason: 'JDK $major does not need the unlock flag',
        );
      }
    });

    test('Java 21+ → ZGC', () {
      expect(gcFlagsForJavaMajor(21), const ['-XX:+UseZGC']);
      expect(gcFlagsForJavaMajor(25), const ['-XX:+UseZGC']);
      expect(gcFlagsForJavaMajor(99), const ['-XX:+UseZGC']);
    });
  });
}
