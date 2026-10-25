import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/models.dart';

/// Event log persisted in shared_preferences as JSON.
///
/// The log is tiny by design (2–6 events/day ≈ a few KB/year), so JSON-in-prefs
/// beats standing up a database. A background notification isolate can open
/// its own instance of this and write safely.
class EventStore {
  EventStore(this._prefs);

  static const _key = 'events_v1';
  static const _installKey = 'install_ts_v1';

  final SharedPreferences _prefs;

  static Future<EventStore> open() async =>
      EventStore(await SharedPreferences.getInstance());

  /// When the app was first opened — the fold starts counting from here.
  /// Tanks start EMPTY; only logged events refill them.
  DateTime installTs() {
    final raw = _prefs.getString(_installKey);
    if (raw != null) return DateTime.parse(raw);
    final now = DateTime.now().toUtc();
    _prefs.setString(_installKey, now.toIso8601String());
    return now;
  }

  List<SurvivalEvent> events() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => SurvivalEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> append(SurvivalEvent e) async {
    final list = events()..add(e);
    await _prefs.setString(
        _key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_installKey);
  }
}
