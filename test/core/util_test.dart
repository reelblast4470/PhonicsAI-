import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/responsive/responsive.dart';
import 'package:phonicsai/core/security/secure_vault.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/core/util/date_util.dart';
import 'package:phonicsai/core/util/math_util.dart';

void main() {
  group('Breakpoint', () {
    test('phone / tablet / desktop classes', () {
      expect(Breakpoint.of(360), Breakpoint.compact);
      expect(Breakpoint.of(600), Breakpoint.medium);
      expect(Breakpoint.of(840), Breakpoint.expanded);
      expect(Breakpoint.of(1400), Breakpoint.large);
      expect(Breakpoint.of(1600), Breakpoint.extraLarge);
    });

    test('rail only appears from medium up', () {
      expect(Breakpoint.compact.showRail, isFalse);
      expect(Breakpoint.medium.showRail, isTrue);
    });

    test('content width grows but is always capped', () {
      expect(Breakpoint.compact.maxContentWidth, double.infinity);
      expect(
        Breakpoint.extraLarge.maxContentWidth <= 1300,
        isTrue,
        reason: 'desktop must not stretch a lesson across a 4K window',
      );
    });
  });

  group('DateUtil', () {
    test('daysBetween ignores time of day', () {
      expect(
        DateUtil.daysBetween(
          DateTime(2026, 9, 1, 23, 59),
          DateTime(2026, 9, 3, 0, 1),
        ),
        2,
      );
    });

    test('weekStart is always a Monday', () {
      final monday = DateUtil.weekStart(DateTime(2026, 9, 14, 18));
      expect(monday.weekday, DateTime.monday);
      expect(monday, DateTime(2026, 9, 14));
    });

    test('isSameDay', () {
      expect(
        DateUtil.isSameDay(DateTime(2026, 9, 14, 8), DateTime(2026, 9, 14, 20)),
        isTrue,
      );
    });
  });

  group('MathUtil', () {
    test('ratio survives empty denominators', () {
      expect(MathUtil.ratio(3, 0), 0);
      expect(MathUtil.ratio(3, 4), 0.75);
      expect(MathUtil.ratio(9, 4), 1, reason: 'clamped to 1');
    });

    test('percentRound', () {
      expect(MathUtil.percentRound(0.8739), 87);
      expect(MathUtil.percentRound(-0.2), 0);
    });

    test('ema trails the newest value and alpha=1 returns it', () {
      expect(MathUtil.ema([0, 1], alpha: 1), 1);
      expect(MathUtil.ema([1, 0], alpha: 1), 0);
      // alpha .35 on [0,1] keeps 65% of the older sample.
      expect(MathUtil.ema([0, 1]), closeTo(0.35, 1e-9));
    });

    test('mean/stdDev on small samples', () {
      expect(MathUtil.mean([]), 0);
      expect(MathUtil.stdDev([1]), 0);
      expect(MathUtil.mean([1, 2, 3]), 2);
    });

    test('stdDev of two identical samples is zero', () {
      expect(MathUtil.stdDev([0.5, 0.5]), closeTo(0, 1e-9));
    });
  });

  group('KeyValueStore json helpers', () {
    test('round trip + corrupt payload', () async {
      final store = InMemoryKeyValueStore({'k': '{"n":3}'});
      await store.setString('bad', 'nope');
      final value = store.getJson<int>('k', (j) => j['n'] as int);
      expect(value, 3);
      expect(store.getJson<int>('bad', (j) => 0), isNull);
      expect(store.getJson<int>('missing', (j) => 0), isNull);
    });
  });

  group('PinHasher', () {
    const hasher = PinHasher();
    test('same pin+salt is stable, different salt is not', () {
      expect(hasher.digest('1234', 'aa'), hasher.digest('1234', 'aa'));
      expect(hasher.digest('1234', 'aa'), isNot(hasher.digest('1234', 'bb')));
      expect(hasher.digest('1234', 'aa'), isNot(hasher.digest('1235', 'aa')));
    });

    test('salt is random per call', () {
      expect(hasher.newSalt(), isNot(hasher.newSalt()));
    });
  });
}
