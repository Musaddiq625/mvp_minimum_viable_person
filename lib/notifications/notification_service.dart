import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../data/event_store.dart';
import '../data/settings_store.dart';
import '../engine/models.dart';
import '../engine/survival_engine.dart';

/// Laziest logging there is: notifications carry [ATE]/[DRANK] action
/// buttons, so the user can log without ever opening the app.
class NotificationService {
  NotificationService._();

  static const _channelId = 'mvp_nudges';
  static const _ateActionId = 'ate';
  static const _drankActionId = 'drank';

  // Notification ids: thresholds 100..107, daily nudge 200.
  static const _thresholdBase = 100;
  static const _dailyId = 200;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Foreground tap on a notification action → forward to the app.
  void Function(String action)? onAction;

  static final instance = NotificationService._();

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  void _onForegroundResponse(NotificationResponse r) {
    if (r.actionId == _ateActionId || r.actionId == _drankActionId) {
      onAction?.call(r.actionId!);
    }
  }

  /// Reschedule threshold + daily nudges from the current state.
  /// Called after every meaningful change (tap, open, context toggle).
  Future<void> reschedule(
    SurvivalState s, {
    required double waterRate,
    required bool enabled,
    required int quietStart,
    required int quietEnd,
  }) async {
    if (!_initialized) return;
    // Cancel old threshold nudges.
    for (var i = 0; i < 8; i++) {
      await _plugin.cancel(id: _thresholdBase + i);
    }
    if (!enabled) return;

    var id = _thresholdBase;

    // Empty tanks → ONE ping, edge-triggered: only when *what's empty*
    // changes. Persisted — a swiped-away ping stays gone across reschedules
    // and restarts until the tanks actually change state.
    final sig = (s.hydrationH <= 0 ? 1 : 0) | (s.energyH <= 0 ? 2 : 0);
    final prefs = await SharedPreferences.getInstance();
    if (sig != (prefs.getInt('empty_sig_v1') ?? -1)) {
      await prefs.setInt('empty_sig_v1', sig);
      if (sig != 0) {
        await _notifyNow(id++, 'MVP', switch (sig) {
          3 => "💀 everything's empty. eat, drink, exist.",
          1 => "💧 bar's empty. water. now.",
          _ => "🍔 bar's empty. food. now.",
        });
      }
    }

    // Water thresholds.
    for (final (frac, text) in [
      (0.5, "💧 water tank's half. hydrate eventually."),
      (0.25, '💧 getting dry. drink something.'),
      (0.10, '💧 DRINK TO SURVIVE. seriously-ish.'),
    ]) {
      final threshold = frac * SurvivalEngine.waterCapH;
      if (s.hydrationH <= threshold) continue; // empty handled above
      final hoursUntil = (s.hydrationH - threshold) / waterRate;
      final at = _shiftFromQuiet(
        DateTime.now().add(Duration(minutes: (hoursUntil * 60).round())),
        quietStart,
        quietEnd,
      );
      await _schedule(id++, 'MVP', text, at);
    }

    // Food thresholds.
    for (final (frac, text) in [
      (0.5, '🍔 food tank\'s half. snack eventually.'),
      (0.25, '🍔 running on fumes. eat something.'),
      (0.10, '🍔 EAT TO SURVIVE. fridge is right there.'),
    ]) {
      final threshold = frac * SurvivalEngine.energyCapH;
      if (s.energyH <= threshold) continue; // empty handled above
      // Energy drains 1.0/h above 25%, 0.8/h below — approximate at 1.0/h.
      final hoursUntil = (s.energyH - threshold);
      final at = _shiftFromQuiet(
        DateTime.now().add(Duration(minutes: (hoursUntil * 60).round())),
        quietStart,
        quietEnd,
      );
      await _schedule(id++, 'MVP', text, at);
    }

    // Daily 20:00 nudge — neutral, works whether or not they logged.
    await _schedule(
      _dailyId,
      'MVP',
      '🫠 you exist. log something if you ate. or don\'t.',
      _nextDaily(20, quietStart, quietEnd),
    );
  }

  static const _actions = [
    AndroidNotificationAction(_ateActionId, 'ATE'),
    AndroidNotificationAction(_drankActionId, 'DRANK'),
  ];

  Future<void> _notifyNow(int id, String title, String body) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'nudges',
        importance: Importance.high,
        actions: _actions,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );

  Future<void> _schedule(int id, String title, String body, DateTime at) {
    if (at.isBefore(DateTime.now())) return Future.value();
    return _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'nudges',
          importance: Importance.defaultImportance,
          actions: _actions,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// If [at] lands inside quiet hours, push it to the end of quiet hours.
  DateTime _shiftFromQuiet(DateTime at, int start, int end) {
    final h = at.hour;
    final inQuiet = start > end
        ? (h >= start || h < end) // wraps midnight
        : (h >= start && h < end);
    if (!inQuiet) return at;
    var t = DateTime(at.year, at.month, at.day, end);
    if (t.isBefore(at)) t = t.add(const Duration(days: 1));
    return t;
  }

  DateTime _nextDaily(int hour, int quietStart, int quietEnd) {
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, hour);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    return _shiftFromQuiet(at, quietStart, quietEnd);
  }
}

/// Background isolate entry point: notification action fired while the app
/// is dead → write the event straight to the store. The app picks it up on
/// next open via the normal fold.
@pragma('vm:entry-point')
void _onBackgroundResponse(NotificationResponse response) {
  if (response.actionId != 'ate' && response.actionId != 'drank') return;
  _logFromNotification(response.actionId!).ignore();
}

Future<void> _logFromNotification(String actionId) async {
  try {
    final store = await EventStore.open();
    final settings = await SettingsStore.open();
    final now = DateTime.now();
    const engine = SurvivalEngine();
    if (actionId == 'ate') {
      // Same portion lookup the app does — presets live in the same prefs.
      final slot = MealSlot.fromHour(now.hour);
      final kcal =
          SurvivalEngine.portionKcal[settings.presets().portionFor(slot)]!;
      await store.append(
        engine.ateEvent(now, kcal, source: EventSource.notification),
      );
    } else {
      await store.append(
        engine.drankEvent(
          now,
          settings.presets().drinkSize.ml,
          source: EventSource.notification,
        ),
      );
    }
  } catch (e) {
    debugPrint('background log failed: $e');
  }
}
