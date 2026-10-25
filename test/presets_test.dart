import 'package:flutter_test/flutter_test.dart';
import 'package:mvp_minimum_viable_person/engine/models.dart';
import 'package:mvp_minimum_viable_person/engine/presets.dart';
import 'package:mvp_minimum_viable_person/engine/survival_engine.dart';

void main() {
  group('PortionPresets.kcalFor', () {
    test('falls back to portion kcal with no AI estimate', () {
      final p = PortionPresets()
        ..portions[MealSlot.night] = Portion.large;
      expect(p.kcalFor(MealSlot.night),
          SurvivalEngine.portionKcal[Portion.large]);
    });

    test('AI estimate wins and scales with portion', () {
      final p = PortionPresets()
        ..favKcal[MealSlot.night] = 800
        ..portions[MealSlot.night] = Portion.normal;
      expect(p.kcalFor(MealSlot.night), 800); // scale 1.0

      p.portions[MealSlot.night] = Portion.small;
      expect(p.kcalFor(MealSlot.night), 560); // 800 * 0.7
    });

    test('json round-trips favKcal', () {
      final p = PortionPresets()
        ..favKcal[MealSlot.morning] = 450;
      final back = PortionPresets.fromJson(p.toJson());
      expect(back.favKcal[MealSlot.morning], 450);
      expect(back.kcalFor(MealSlot.morning), 450);
    });
  });
}
