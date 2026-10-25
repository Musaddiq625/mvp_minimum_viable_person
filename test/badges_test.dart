import 'package:flutter_test/flutter_test.dart';
import 'package:mvp_minimum_viable_person/engine/badges.dart';
import 'package:mvp_minimum_viable_person/engine/models.dart';
import 'package:mvp_minimum_viable_person/engine/survival_engine.dart';

void main() {
  const empty = SurvivalState(hydrationH: 0, energyH: 0);
  const healthy = SurvivalState(hydrationH: 30, energyH: 200);

  // Local times — toLocal() in the badge check is TZ-dependent, so build
  // local DateTimes and store their UTC instant for deterministic tests.
  SurvivalEvent ate([int hour = 12, int day = 1, EventSource src = EventSource.app]) =>
      SurvivalEvent(
          type: EventType.ate,
          tsUtc: DateTime(2026, 10, day, hour).toUtc(),
          kcal: 700,
          source: src);
  SurvivalEvent drank([int hour = 12, int day = 1, EventSource src = EventSource.app]) =>
      SurvivalEvent(
          type: EventType.drank,
          tsUtc: DateTime(2026, 10, day, hour).toUtc(),
          ml: 250,
          source: src);

  List<SurvivalBadge> eval(
          {List<SurvivalEvent> events = const [],
          int daysAlive = 1,
          int spam = 0,
          bool ai = false,
          bool model = true,
          SurvivalState state = empty}) =>
      evaluateBadges(
          events: events,
          daysAlive: daysAlive,
          spamCount: spam,
          heardAi: ai,
          modelReady: model,
          state: state);

  Set<String> names(List<SurvivalBadge> bs) =>
      bs.where((b) => b.earned).map((b) => b.name).toSet();

  test('fresh install earns brain + dying (the journey starts)', () {
    expect(names(eval()), containsAll(['Brain owner', 'Dying, but stylishly']));
  });

  test('first taps unlock the opening badges', () {
    final n = names(eval(events: [ate(), drank()], state: healthy));
    expect(n, containsAll(['First tap', 'Fed', 'Hydrated']));
    expect(n, isNot(contains('Delegator')));
  });

  test('night owl, delegator, spam, ai', () {
    expect(names(eval(events: [ate(3)])), contains('Night owl'));
    expect(
        names(eval(events: [drank(12, 1, EventSource.widget)])),
        contains('Delegator'));
    expect(names(eval(spam: 1)), contains('Spam certified'));
    expect(names(eval(ai: true)), contains('Heard the brain'));
  });

  test('ghost day needs a logged-free day', () {
    final n = names(eval(events: [ate(12, 1)], daysAlive: 3));
    expect(n, contains('Ghost day'));
  });

  test('the mvp unlocks at 8 earned badges', () {
    final full = eval(events: [
      ate(3, 1, EventSource.widget),
      drank(12, 2),
      ate(13, 3),
    ], daysAlive: 3, spam: 1, ai: true, state: healthy);
    expect(names(full), contains('The MVP'));
    expect(names(eval()), isNot(contains('The MVP')));
  });
}
