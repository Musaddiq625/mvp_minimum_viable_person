import 'package:flutter_test/flutter_test.dart';
import 'package:mvp_minimum_viable_person/engine/models.dart';
import 'package:mvp_minimum_viable_person/engine/survival_engine.dart';

void main() {
  const engine = SurvivalEngine();
  final t0 = DateTime.utc(2026, 10, 20, 12, 0, 0);

  SurvivalState full() => const SurvivalState(
      hydrationH: SurvivalEngine.waterCapH,
      energyH: SurvivalEngine.energyCapH);

  group('slots', () {
    test('maps hours to meal slots', () {
      expect(MealSlot.fromHour(7), MealSlot.morning);
      expect(MealSlot.fromHour(12), MealSlot.afternoon);
      expect(MealSlot.fromHour(18), MealSlot.evening);
      expect(MealSlot.fromHour(23), MealSlot.night);
      expect(MealSlot.fromHour(0), MealSlot.night); // 00:30 is still "night"
      expect(MealSlot.fromHour(3), MealSlot.lateNight);
      expect(MealSlot.fromHour(5), MealSlot.morning);
    });
  });

  group('refill', () {
    test('normal meal adds ~7.6h energy + small water bonus', () {
      final s = engine.eat(full(), 700);
      expect(s.energyH, closeTo(SurvivalEngine.energyCapH, 0.01)); // clamped at cap
      final fromLow = engine.eat(
          const SurvivalState(hydrationH: 10, energyH: 100), 700);
      expect(fromLow.energyH, closeTo(100 + 700 / SurvivalEngine.kcalBurnPerHour, 0.01));
      expect(fromLow.hydrationH, closeTo(10 + (700 / SurvivalEngine.kcalBurnPerHour) * 0.15, 0.01));
    });

    test('glass (250ml) adds 6h hydration', () {
      final s = engine.drink(
          const SurvivalState(hydrationH: 10, energyH: 300), 250);
      expect(s.hydrationH, closeTo(16, 0.01));
    });

    test('bottle (500ml) adds 12h hydration', () {
      final s = engine.drink(
          const SurvivalState(hydrationH: 10, energyH: 300), 500);
      expect(s.hydrationH, closeTo(22, 0.01));
    });

    test('refills clamp at capacity', () {
      final s = engine.drink(full(), 500);
      expect(s.hydrationH, SurvivalEngine.waterCapH);
    });
  });

  group('decay', () {
    test('tanks drain over time', () {
      final s = engine.decay(full(), 10);
      expect(s.hydrationH, closeTo(62, 0.01));
      expect(s.energyH, closeTo(494, 0.01));
    });

    test('hot day drains water faster', () {
      final s = engine.decay(full(), 10, waterRate: 1.5);
      expect(s.hydrationH, closeTo(57, 0.01));
    });

    test('energy drains slower below 25% (metabolic slowdown)', () {
      const low = SurvivalState(hydrationH: 50, energyH: 100);
      final s = engine.decay(low, 10);
      expect(s.energyH, closeTo(92, 0.01)); // 10h * 0.8 = 8h lost
    });

    test('energy decay is piecewise across the threshold', () {
      const at = SurvivalState(hydrationH: 50, energyH: 136); // 10h above threshold
      final s = engine.decay(at, 20);
      // 10h at full rate → hits 126, then 10h at 0.8 → 118
      expect(s.energyH, closeTo(118, 0.01));
    });

    test('never goes below zero', () {
      final s = engine.decay(full(), 10000);
      expect(s.hydrationH, 0);
      expect(s.energyH, 0);
      expect(s.isEmpty, true);
    });
  });

  group('fold', () {
    test('fresh start is empty tanks — nothing logged, nothing counted', () {
      final s = engine.fold([], startTs: t0, now: t0);
      expect(s, const SurvivalState(hydrationH: 0, energyH: 0));
      expect(s.isEmpty, true);
    });

    test('skip two meals, feast after, still kicking (the user story)', () {
      // Ate normally Monday lunch, then nothing until Wednesday dinner feast.
      final events = [
        engine.ateEvent(DateTime.utc(2026, 10, 19, 13), 700),
        engine.drankEvent(DateTime.utc(2026, 10, 19, 14), 250),
        engine.drankEvent(DateTime.utc(2026, 10, 20, 10), 250),
        engine.drankEvent(DateTime.utc(2026, 10, 20, 18), 250),
        engine.ateEvent(DateTime.utc(2026, 10, 20, 20), 1100), // feast
      ];
      // Gap-fill off so we can see raw decay.
      final s = engine.fold(
        events,
        startTs: t0.subtract(const Duration(hours: 30)),
        now: DateTime.utc(2026, 10, 20, 22),
        gapFillEnabled: false,
      );
      expect(s.energyH, greaterThan(0));
      expect(s.hydrationH, greaterThan(0));
      expect(engine.limiting(s), TankKind.hydration); // water is always the limiter
    });

    test('gap-fill assumes normal intake during long absences', () {
      final events = [engine.ateEvent(t0, 700)];
      final withFill = engine.fold(events,
          startTs: t0, now: t0.add(const Duration(hours: 72)),
          gapFillEnabled: true);
      // 72h gap → full missed days assumed maintained → only remainder (0h)
      // decays, so the meal's ~7.6h refill survives intact.
      expect(withFill.energyH,
          closeTo(700 / SurvivalEngine.kcalBurnPerHour, 0.01));
      final noFill = engine.fold(events,
          startTs: t0, now: t0.add(const Duration(hours: 72)),
          gapFillEnabled: false);
      expect(noFill.hydrationH, lessThan(withFill.hydrationH));
    });
  });

  group('headline', () {
    test('hydration is the limiter when lower', () {
      const s = SurvivalState(hydrationH: 20, energyH: 300);
      expect(engine.limiting(s), TankKind.hydration);
      expect(engine.headlineHours(s), 20);
      expect(engine.formatHeadline(s), '20h');
    });

    test('format switches to days and weeks', () {
      expect(
          engine.formatHeadline(
              const SurvivalState(hydrationH: 60, energyH: 60)),
          '3d');
      expect(
          engine.formatHeadline(
              const SurvivalState(hydrationH: 72, energyH: 300)),
          '3d');
      expect(
          engine.formatHeadline(
              const SurvivalState(hydrationH: 72, energyH: 72)),
          '3d');
    });
  });
}
