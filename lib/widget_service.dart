import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import 'app_state.dart';
import 'data/event_store.dart';
import 'data/settings_store.dart';
import 'engine/models.dart';
import 'engine/persona_bank.dart';
import 'engine/survival_engine.dart';

/// Home-screen widget sync + interactivity.
///
/// The widget shows the same three things the app does — one number, one
/// bar, one line — plus ATE/DRANK buttons whose taps run a Dart callback in
/// the background. The laziest possible logging: you never open the app.
class WidgetService {
  static const providerName = 'MvpWidgetProvider';
  static const appGroupId = 'group.com.musaddiq625.mvp';

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await HomeWidget.registerInteractivityCallback(
          _widgetBackgroundCallback);
    } catch (e) {
      debugPrint('widget init failed: $e');
    }
  }

  /// Push current app state to the widget (called on every state change).
  static Future<void> sync(AppState app) => _push(
        headline: app.headline,
        fractionPct: (app.headlineFraction * 100).round(),
        line: app.line.isEmpty ? 'alive-ish.' : app.line,
      );

  /// Recompute from stores and push — usable from a background isolate.
  static Future<void> pushNow() async {
    final events = await EventStore.open();
    final settings = await SettingsStore.open();
    const engine = SurvivalEngine();
    final s = engine.fold(
      events.events(),
      startTs: events.installTs(),
      now: DateTime.now().toUtc(),
      waterRate: settings.waterRate(),
      gapFillEnabled: settings.gapFill(),
    );
    // Deterministic daily line — background isolate keeps it simple.
    final bank = PersonaBank(DateTime.now().day);
    await _push(
      headline: engine.formatHeadline(s),
      fractionPct: (engine.headlineFraction(s) * 100).round(),
      line: bank.at(
          s.hydrationH <= 0.1 * SurvivalEngine.waterCapH
              ? PersonaContext.lowHydration
              : PersonaContext.daily,
          DateTime.now().day),
    );
  }

  static Future<void> _push({
    required String headline,
    required int fractionPct,
    required String line,
  }) async {
    try {
      await HomeWidget.saveWidgetData('headline', headline);
      await HomeWidget.saveWidgetData('fractionPct', fractionPct);
      await HomeWidget.saveWidgetData('line', line);
      await HomeWidget.updateWidget(
        name: providerName,
        qualifiedAndroidName: 'com.musaddiq625.mvp.$providerName',
      );
    } catch (e) {
      debugPrint('widget sync failed: $e');
    }
  }
}

/// Widget button taps land here in a background isolate.
/// Write the event, recompute, refresh the widget — app never opens.
@pragma('vm:entry-point')
Future<void> _widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (uri.host == 'ate' || uri.host == 'drank') {
      final store = await EventStore.open();
      final settings = await SettingsStore.open();
      final now = DateTime.now();
      const engine = SurvivalEngine();
      if (uri.host == 'ate') {
        final slot = MealSlot.fromHour(now.hour);
        final kcal = SurvivalEngine
            .portionKcal[settings.presets().portionFor(slot)]!;
        await store.append(engine.ateEvent(now, kcal,
            source: EventSource.widget));
      } else {
        await store.append(engine.drankEvent(
            now, settings.presets().drinkSize.ml,
            source: EventSource.widget));
      }
    }
    await WidgetService.pushNow();
  } catch (e) {
    debugPrint('widget callback failed: $e');
  }
}
