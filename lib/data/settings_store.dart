import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/presets.dart';

/// App settings in shared_preferences. Everything has a default so the app
/// works before the user ever opens settings.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _presetsKey = 'portion_presets_v1';
  static const _gapFillKey = 'gap_fill_v1';
  static const _hotKey = 'ctx_hot_v1';
  static const _movedDateKey = 'ctx_moved_date_v1';
  static const _notifKey = 'notifications_v1';
  static const _quietStartKey = 'quiet_start_v1';
  static const _quietEndKey = 'quiet_end_v1';
  static const _onboardedKey = 'onboarded_v1';
  static const _modelReadyKey = 'model_ready_v1';

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  PortionPresets presets() {
    final raw = _prefs.getString(_presetsKey);
    if (raw == null) return PortionPresets();
    try {
      return PortionPresets.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return PortionPresets();
    }
  }

  Future<void> savePresets(PortionPresets p) =>
      _prefs.setString(_presetsKey, jsonEncode(p.toJson()));

  /// "Assume I survived while away" — default on.
  bool gapFill() => _prefs.getBool(_gapFillKey) ?? true;
  Future<void> setGapFill(bool v) => _prefs.setBool(_gapFillKey, v);

  /// Context modifiers.
  bool itsHot() => _prefs.getBool(_hotKey) ?? false;
  Future<void> setHot(bool v) => _prefs.setBool(_hotKey, v);

  /// "I moved today" auto-resets each day — stored as the date it was set.
  bool movedToday() {
    final raw = _prefs.getString(_movedDateKey);
    if (raw == null) return false;
    return raw == _today();
  }

  Future<void> setMovedToday(bool v) =>
      _prefs.setString(_movedDateKey, v ? _today() : '');

  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// Combined water drain rate from context toggles.
  double waterRate() {
    var rate = 1.0;
    if (itsHot()) rate *= 1.5;
    if (movedToday()) rate *= 1.3;
    return rate;
  }

  bool notificationsEnabled() => _prefs.getBool(_notifKey) ?? true;
  Future<void> setNotificationsEnabled(bool v) =>
      _prefs.setBool(_notifKey, v);

  /// Quiet hours as [startHour, endHour); default 23:00 → 08:00.
  int quietStart() => _prefs.getInt(_quietStartKey) ?? 23;
  int quietEnd() => _prefs.getInt(_quietEndKey) ?? 8;
  Future<void> setQuietHours(int start, int end) async {
    await _prefs.setInt(_quietStartKey, start);
    await _prefs.setInt(_quietEndKey, end);
  }

  bool onboarded() => _prefs.getBool(_onboardedKey) ?? false;
  Future<void> setOnboarded() => _prefs.setBool(_onboardedKey, true);

  bool modelReady() => _prefs.getBool(_modelReadyKey) ?? false;
  Future<void> setModelReady(bool v) => _prefs.setBool(_modelReadyKey, v);

  /// How many times the user out-lazied the debounce — feeds the
  /// 'spam certified' badge.
  int spamCount() => _prefs.getInt('spam_count_v1') ?? 0;
  Future<void> bumpSpam() =>
      _prefs.setInt('spam_count_v1', spamCount() + 1);

  /// Lines the on-device model actually produced — feeds the
  /// 'heard the brain' badge.
  int aiLines() => _prefs.getInt('ai_lines_v1') ?? 0;
  Future<void> bumpAiLines() =>
      _prefs.setInt('ai_lines_v1', aiLines() + 1);
}
