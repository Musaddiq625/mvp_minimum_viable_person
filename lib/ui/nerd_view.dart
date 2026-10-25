import 'package:flutter/material.dart';

import '../ai/gemma_service.dart';
import '../app_state.dart';
import '../engine/badges.dart';
import '../engine/survival_engine.dart';
import 'theme.dart';

/// Long-press the bar → both tanks, absolute numbers, stats, badges.
/// The only "details" surface in the app.
void showNerdView(BuildContext context, AppState app, GemmaService? gemma) {
  showModalBottomSheet(
    context: context,
    backgroundColor: MvpTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 44),
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final stats = app.stats;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nerd view',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MvpTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                _TankRow(
                  label: 'Water 💧',
                  hours: app.state.hydrationH,
                  cap: SurvivalEngine.waterCapH,
                ),
                const SizedBox(height: 12),
                _TankRow(
                  label: 'Food 🍔',
                  hours: app.state.energyH,
                  cap: SurvivalEngine.energyCapH,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat('day ${stats['days']}', 'of being alive'),
                    _Stat('${stats['meals']}', 'meals logged'),
                    _Stat('${stats['drinks']}', 'drinks logged'),
                  ],
                ),
                const SizedBox(height: 16),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        size: 12, color: MvpTheme.textMuted),
                    SizedBox(width: 6),
                    Text(
                      'Achievements',
                      style: TextStyle(
                        color: MvpTheme.textMuted,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final b in evaluateBadges(
                      events: app.eventLog,
                      daysAlive: app.daysAlive,
                      spamCount: app.spamCount,
                      heardAi: app.aiLines > 0,
                      modelReady: gemma?.status == GemmaStatus.ready,
                      state: app.state,
                    ))
                      _BadgeChip(b),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _TankRow extends StatelessWidget {
  const _TankRow({required this.label, required this.hours, required this.cap});

  final String label;
  final double hours;
  final double cap;

  @override
  Widget build(BuildContext context) {
    final frac = (hours / cap).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(
              '${hours.round()}h',
              style: const TextStyle(fontSize: 13, color: MvpTheme.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 8,
            backgroundColor: MvpTheme.bg,
            color: frac <= 0.1 ? MvpTheme.warn : MvpTheme.accent,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w300),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: MvpTheme.textMuted),
      ),
    ],
  );
}

/// One badge chip — earned shows the name lit; locked shows the
/// requirement faintly, so the whole journey is visible up front.
class _BadgeChip extends StatelessWidget {
  const _BadgeChip(this.badge);

  final SurvivalBadge badge;

  @override
  Widget build(BuildContext context) {
    final earned = badge.earned;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: earned ? MvpTheme.accent.withValues(alpha: 0.10) : null,
        border: Border.all(
          color: earned
              ? MvpTheme.accentDim
              : MvpTheme.textMuted.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        earned
            ? '${badge.emoji} ${badge.name}'
            : '${badge.emoji} ${badge.name} · ${badge.hint}',
        style: TextStyle(
          fontSize: 10,
          color: earned
              ? MvpTheme.accent
              : MvpTheme.textMuted.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
