/// Core value types for the survival engine. Pure Dart, no Flutter imports.
library;

enum TankKind { hydration, energy }

enum Portion { small, normal, large }

enum DrinkSize {
  glass(250),
  bottle(500);

  const DrinkSize(this.ml);
  final int ml;
}

/// Time-of-day buckets used to map an `ATE` tap to a configured portion.
enum MealSlot {
  morning(5, 11, 'Morning'),
  afternoon(11, 16, 'Afternoon'),
  evening(16, 21, 'Evening'),
  night(21, 25, 'Night'), // 21:00 → 01:00
  lateNight(25, 29, 'Late night'); // 01:00 → 05:00

  const MealSlot(this.startHour, this.endHour, this.label);
  final int startHour;
  final int endHour;
  final String label;

  static MealSlot fromHour(int hour) {
    final h = hour < 5 ? hour + 24 : hour;
    for (final s in values) {
      if (h >= s.startHour && h < s.endHour) return s;
    }
    return MealSlot.lateNight;
  }
}

enum EventType { ate, drank }

enum EventSource { app, notification, widget }

class SurvivalEvent {
  const SurvivalEvent({
    required this.type,
    required this.tsUtc,
    this.kcal = 0,
    this.ml = 0,
    this.source = EventSource.app,
  });

  final EventType type;
  final DateTime tsUtc;
  final int kcal;
  final int ml;
  final EventSource source;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'ts': tsUtc.toIso8601String(),
        'kcal': kcal,
        'ml': ml,
        'source': source.name,
      };

  factory SurvivalEvent.fromJson(Map<String, dynamic> j) => SurvivalEvent(
        type: EventType.values.byName(j['type'] as String),
        tsUtc: DateTime.parse(j['ts'] as String),
        kcal: j['kcal'] as int? ?? 0,
        ml: j['ml'] as int? ?? 0,
        source: EventSource.values.byName(j['source'] as String? ?? 'app'),
      );
}
