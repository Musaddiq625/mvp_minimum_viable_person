import 'models.dart';

/// The survival engine: two reserve tanks measured in "survival hours".
///
/// Hydration tank: 0..72h (rule-of-3 days). Energy tank: 0..504h (~3 weeks).
/// Reserves are a pure function of the event log + `now` — no running timers.
///
/// Pop-science estimates for a joke app. Not medical advice. Drink water.
class SurvivalEngine {
  // Tank capacities (hours of survival).
  static const double waterCapH = 72.0;
  static const double energyCapH = 504.0;

  // Conversion constants.
  static const double kcalBurnPerHour = 2200 / 24; // ~91.67
  static const double hoursPerMl = waterCapH / 3000; // 0.024
  static const double foodWaterBonus = 0.15; // food carries ~15% as water

  // Energy drain slows below 25% reserves — metabolic slowdown. This is what
  // lets "skips meals, still survives for months" emerge naturally.
  static const double energySlowdownThreshold = 0.25 * energyCapH; // 126h
  static const double energySlowdownRate = 0.8;

  // Context modifiers.
  static const double hotWaterDrain = 1.5;
  static const double movedWaterDrain = 1.3;

  // Gap-fill: absent for ≥24h, we assume the user self-maintained during each
  // full missed day; only the sub-24h remainder actually drains the tanks.
  static const double gapFillThresholdH = 24.0;

  // Home bars show "coverage of the next 24h", not fraction of the full
  // 72h/504h capacity — otherwise a real meal is an invisible 1.5% sliver.
  // The countdown + per-tank times still report true remaining hours.
  static const double barHorizonH = 24.0;

  static const Map<Portion, int> portionKcal = {
    Portion.small: 400,
    Portion.normal: 700,
    Portion.large: 1100,
  };

  const SurvivalEngine();

  /// Effective decay time for a gap, honoring the gap-fill rule.
  double effectiveGapHours(double gapH, {required bool gapFillEnabled}) {
    if (!gapFillEnabled || gapH < gapFillThresholdH) return gapH;
    return gapH % gapFillThresholdH;
  }

  /// Apply decay over [hours] elapsed. Water drains at [waterRate] units/h;
  /// energy drains at 1.0/h until it crosses the slowdown threshold, then 0.8/h.
  SurvivalState decay(
    SurvivalState s,
    double hours, {
    double waterRate = 1.0,
  }) {
    if (hours <= 0) return s;
    final hydration = (s.hydrationH - hours * waterRate).clamp(0.0, waterCapH);
    final energy = _decayEnergy(s.energyH, hours);
    return SurvivalState(hydrationH: hydration, energyH: energy);
  }

  double _decayEnergy(double start, double hours) {
    if (start <= energySlowdownThreshold) {
      return (start - hours * energySlowdownRate).clamp(0.0, energyCapH);
    }
    final hoursAtFullRate = start - energySlowdownThreshold; // rate is 1.0/h
    if (hours <= hoursAtFullRate) return start - hours;
    return (energySlowdownThreshold - (hours - hoursAtFullRate) * energySlowdownRate)
        .clamp(0.0, energyCapH);
  }

  /// Refill from a food event. kcal converts to survival hours; food also
  /// carries a small hydration bonus.
  SurvivalState eat(SurvivalState s, int kcal, {bool seconds = false}) {
    var hours = kcal / kcalBurnPerHour;
    if (seconds) hours *= 1.5;
    return SurvivalState(
      hydrationH: (s.hydrationH + hours * foodWaterBonus).clamp(0.0, waterCapH),
      energyH: (s.energyH + hours).clamp(0.0, energyCapH),
    );
  }

  /// Refill from a drink event.
  SurvivalState drink(SurvivalState s, int ml) => SurvivalState(
        hydrationH: (s.hydrationH + ml * hoursPerMl).clamp(0.0, waterCapH),
        energyH: s.energyH,
      );

  SurvivalState applyEvent(SurvivalState s, SurvivalEvent e) => switch (e.type) {
        EventType.ate => eat(s, e.kcal),
        EventType.drank => drink(s, e.ml),
      };

  /// Fold the whole event log to a state at [now].
  ///
  /// Tanks start EMPTY at [startTs] — the app only knows what you log.
  /// Fresh install or wipe means "nothing counted, you're starving" until
  /// the first ATE/DRANK refills. Each event decays the gap before it,
  /// then applies its refill.
  SurvivalState fold(
    List<SurvivalEvent> events, {
    required DateTime startTs,
    required DateTime now,
    double waterRate = 1.0,
    bool gapFillEnabled = true,
  }) {
    var s = const SurvivalState(hydrationH: 0, energyH: 0);
    var t = startTs.toUtc();
    final sorted = List.of(events)
      ..sort((a, b) => a.tsUtc.compareTo(b.tsUtc));

    for (final e in sorted) {
      if (e.tsUtc.isBefore(t)) continue;
      final gap = e.tsUtc.difference(t).inSeconds / 3600.0;
      s = decay(s, effectiveGapHours(gap, gapFillEnabled: gapFillEnabled),
          waterRate: waterRate);
      s = applyEvent(s, e);
      t = e.tsUtc;
    }
    final tail = now.toUtc().difference(t).inSeconds / 3600.0;
    return decay(s, effectiveGapHours(tail, gapFillEnabled: gapFillEnabled),
        waterRate: waterRate);
  }

  /// The tank that will get you first.
  TankKind limiting(SurvivalState s) =>
      s.hydrationH <= s.energyH ? TankKind.hydration : TankKind.energy;

  double headlineHours(SurvivalState s) =>
      s.hydrationH <= s.energyH ? s.hydrationH : s.energyH;

  double headlineFraction(SurvivalState s) =>
      limiting(s) == TankKind.hydration
          ? s.hydrationH / waterCapH
          : s.energyH / energyCapH;

  /// "41h" / "12d" / "3w" — coarse on purpose, these are estimates.
  String formatHeadline(SurvivalState s) {
    final h = headlineHours(s);
    if (h < 48) return '${h.round()}h';
    if (h < 21 * 24) return '${(h / 24).round()}d';
    return '${(h / (24 * 7)).round()}w';
  }

  /// "1d 17h 33m 08s" — the live countdown under the headline. Seconds
  /// included on purpose: watching it tick IS the proof decay runs.
  String formatCountdown(double hours) {
    var secs = (hours * 3600).floor();
    if (secs < 0) secs = 0;
    final d = secs ~/ 86400;
    final h = (secs % 86400) ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = (secs % 60).toString().padLeft(2, '0');
    if (d > 0) return '${d}d ${h}h ${m}m ${s}s';
    if (secs >= 3600) return '${h}h ${m}m ${s}s';
    if (secs >= 60) return '${m}m ${s}s';
    return '${secs}s';
  }

  /// "13d" / "41h" / "8m" — per-tank remaining time for the bar rows.
  String formatRemaining(double hours) {
    if (hours >= 48) return '${(hours / 24).round()}d';
    if (hours >= 1) return '${hours.round()}h';
    return '${(hours * 60).round()}m';
  }

  /// Build the event produced by an `ATE` tap at [nowLocal] using presets.
  SurvivalEvent ateEvent(
    DateTime nowLocal,
    int kcal, {
    EventSource source = EventSource.app,
  }) =>
      SurvivalEvent(
        type: EventType.ate,
        tsUtc: nowLocal.toUtc(),
        kcal: kcal,
        source: source,
      );

  SurvivalEvent drankEvent(
    DateTime nowLocal,
    int ml, {
    EventSource source = EventSource.app,
  }) =>
      SurvivalEvent(
        type: EventType.drank,
        tsUtc: nowLocal.toUtc(),
        ml: ml,
        source: source,
      );
}

class SurvivalState {
  const SurvivalState({required this.hydrationH, required this.energyH});

  final double hydrationH;
  final double energyH;

  bool get isHungry =>
      hydrationH <= 0.10 * SurvivalEngine.waterCapH ||
      energyH <= 0.10 * SurvivalEngine.energyCapH;

  bool get isEmpty => hydrationH <= 0 || energyH <= 0;

  @override
  String toString() => 'SurvivalState(h2o: ${hydrationH.toStringAsFixed(1)}h, '
      'kcal: ${energyH.toStringAsFixed(1)}h)';
}
