import 'models.dart';
import 'survival_engine.dart';

/// Per-slot portion configuration + drink size. Persisted to settings;
/// pre-filled with defaults so setup is skippable.
class PortionPresets {
  PortionPresets({
    Map<MealSlot, Portion>? portions,
    Map<MealSlot, String>? favFoods,
    Map<MealSlot, int>? favKcal,
    this.drinkSize = DrinkSize.glass,
  })  : portions = portions ?? defaultPortions(),
        favFoods = favFoods ?? {},
        favKcal = favKcal ?? {};

  final Map<MealSlot, Portion> portions;
  final Map<MealSlot, String> favFoods;

  /// AI-estimated calories for the fav food per slot. When present it feeds
  /// the survival math directly — the local model literally sits inside
  /// the engine loop.
  final Map<MealSlot, int> favKcal;
  DrinkSize drinkSize;

  /// How the portion picker scales an AI estimate (appetite, not dish size).
  static const Map<Portion, double> portionScale = {
    Portion.small: 0.7,
    Portion.normal: 1.0,
    Portion.large: 1.4,
  };

  // Fresh mutable map per call — the presets screen writes into it.
  static Map<MealSlot, Portion> defaultPortions() => {
        MealSlot.morning: Portion.normal,
        MealSlot.afternoon: Portion.large,
        MealSlot.evening: Portion.normal,
        MealSlot.night: Portion.large,
        MealSlot.lateNight: Portion.small,
      };

  Portion portionFor(MealSlot slot) => portions[slot] ?? Portion.normal;

  String favFor(MealSlot slot) => favFoods[slot] ?? '';

  /// kcal an `ATE` tap at this slot adds. AI estimate wins when present;
  /// portion presets are the fallback.
  int kcalFor(MealSlot slot) {
    final est = favKcal[slot];
    if (est != null) {
      final scale = portionScale[portionFor(slot)]!;
      return (est * scale).round();
    }
    return SurvivalEngine.portionKcal[portionFor(slot)]!;
  }

  PortionPresets copy() => PortionPresets(
        portions: Map.of(portions),
        favFoods: Map.of(favFoods),
        favKcal: Map.of(favKcal),
        drinkSize: drinkSize,
      );

  Map<String, dynamic> toJson() => {
        'portions': {for (final e in portions.entries) e.key.name: e.value.name},
        'favFoods': favFoods,
        'favKcal': {for (final e in favKcal.entries) e.key.name: e.value},
        'drinkSize': drinkSize.name,
      };

  factory PortionPresets.fromJson(Map<String, dynamic> j) {
    Portion parsePortion(Object? v) =>
        Portion.values.asNameMap()[v] ?? Portion.normal;
    return PortionPresets(
      portions: {
        for (final e in (j['portions'] as Map? ?? {}).entries)
          MealSlot.values.asNameMap()[e.key] ?? MealSlot.morning:
              parsePortion(e.value),
      },
      favFoods: {
        for (final e in (j['favFoods'] as Map? ?? {}).entries)
          MealSlot.values.asNameMap()[e.key] ?? MealSlot.morning: '$e.value',
      },
      favKcal: {
        for (final e in (j['favKcal'] as Map? ?? {}).entries)
          MealSlot.values.asNameMap()[e.key] ?? MealSlot.morning:
              (e.value as num).toInt(),
      },
      drinkSize:
          DrinkSize.values.asNameMap()[j['drinkSize']] ?? DrinkSize.glass,
    );
  }
}
