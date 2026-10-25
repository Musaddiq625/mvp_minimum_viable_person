import 'models.dart';
import 'survival_engine.dart';

/// One badge in the journey. [hint] is the requirement shown while locked.
class SurvivalBadge {
  const SurvivalBadge(this.emoji, this.name, this.hint, this.earned);

  final String emoji;
  final String name;
  final String hint;
  final bool earned;
}

/// The badge progression — ordered like a journey: install → first taps →
/// habits → milestones → meta. Every badge rewards *logging* or surviving,
/// never deprivation.
List<SurvivalBadge> evaluateBadges({
  required List<SurvivalEvent> events,
  required int daysAlive,
  required int spamCount,
  required bool heardAi,
  required bool modelReady,
  required SurvivalState state,
}) {
  final meals = events.where((e) => e.type == EventType.ate).length;
  final drinks = events.where((e) => e.type == EventType.drank).length;
  final loggedDays = events.map((e) {
    final l = e.tsUtc.toLocal();
    return DateTime(l.year, l.month, l.day);
  }).toSet().length;
  final nightOwl = events.any((e) {
    final h = e.tsUtc.toLocal().hour;
    return h >= 1 && h < 5;
  });
  final delegated = events.any((e) => e.source != EventSource.app);

  final badges = <SurvivalBadge>[
    SurvivalBadge('🧠', 'Brain owner', 'install a 3gb brain', modelReady),
    SurvivalBadge(
        '💀', 'Dying, but stylishly', 'run a tank under 10%', state.isHungry),
    SurvivalBadge('👆', 'First tap', 'log anything', events.isNotEmpty),
    SurvivalBadge('💧', 'Hydrated', 'drink once', drinks >= 1),
    SurvivalBadge('🍔', 'Fed', 'eat once', meals >= 1),
    SurvivalBadge(
        '⚡', 'Spam certified', 'tap twice in 5 seconds', spamCount >= 1),
    SurvivalBadge('🦉', 'Night owl', 'log between 1–5 am', nightOwl),
    SurvivalBadge(
        '📲', 'Delegator', 'log from the widget or a notification', delegated),
    SurvivalBadge(
        '👂', 'Heard the brain', 'get a line from the model', heardAi),
    SurvivalBadge('👻', 'Ghost day', 'survive a day you never logged',
        daysAlive >= 2 && loggedDays < daysAlive),
    SurvivalBadge(
        '🏦', 'Tomorrow sorted', 'bank 24h+ of water', state.hydrationH >= 24),
    SurvivalBadge('🐪', 'Camel', '10 drinks', drinks >= 10),
    SurvivalBadge('🐄', 'Grazer', '10 meals', meals >= 10),
    SurvivalBadge('🛋️', 'Bare minimum', '7 days on ≤2 logs a day',
        daysAlive >= 7 && meals + drinks <= daysAlive * 2),
    SurvivalBadge('🪴', 'Houseplant', '30 days of consistency', daysAlive >= 30),
  ];
  final earned = badges.where((b) => b.earned).length;
  badges.add(SurvivalBadge('🏆', 'The MVP', 'earn 8 badges', earned >= 8));
  return badges;
}
