import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/event_store.dart';
import 'data/settings_store.dart';
import 'engine/models.dart';
import 'engine/persona_bank.dart';
import 'engine/presets.dart';
import 'engine/survival_engine.dart';

/// App-wide state: owns the event log, settings, current survival state,
/// persona line, and the 5s spam debounce. One object, everything flows
/// through here.
class AppState extends ChangeNotifier {
  AppState._(this._events, this._settings);

  final EventStore _events;
  final SettingsStore _settings;
  final _engine = const SurvivalEngine();
  final _persona = PersonaBank();

  Timer? _ticker;
  SurvivalState? _state;
  String _line = '';
  bool _spamming = false;
  bool _lineStreaming = false;
  bool _lineIsAi = false;
  int _speakSeq = 0;
  TankKind? _lastHungry;
  TankKind? _gainTank;
  String _gainText = '';
  Timer? _gainTimer;

  /// Streaming generator hook — the Gemma service plugs in here.
  /// Yields line chunks; an empty stream means "use the canned bank".
  Stream<String> Function(PersonaContext ctx, Map<String, Object> stats,
      {String? food})? aiLineStreamer;

  /// Called after every meaningful state change (Phase 6 hooks notifications).
  void Function()? onStateChanged;

  static Future<AppState> init() async {
    final events = await EventStore.open();
    final settings = await SettingsStore.open();
    final app = AppState._(events, settings).._recompute();
    app._line = app._persona.pick(PersonaContext.daily);
    app._ticker = Timer.periodic(
        const Duration(seconds: 1), (_) => app._recompute());
    return app;
  }

  // ---- Read API ----

  SurvivalState get state => _state!;
  String get line => _line;
  bool get spamming => _spamming;

  /// True while the model is typing the current line (cursor shows).
  bool get lineStreaming => _lineStreaming;

  /// True when the current line came from the model (vs canned bank).
  bool get lineIsAi => _lineIsAi;
  PortionPresets get presets => _settings.presets();
  int get daysAlive =>
      DateTime.now().toUtc().difference(_events.installTs()).inDays + 1;
  List<SurvivalEvent> get eventLog => _events.events();

  /// Bar fill = coverage of the next 24h (barHorizonH), not fraction of
  /// the full tank capacity — a single meal/glass visibly moves it.
  double get hydrationFraction =>
      state.hydrationH / SurvivalEngine.barHorizonH;
  double get energyFraction =>
      state.energyH / SurvivalEngine.barHorizonH;
  TankKind get limitingTank => _engine.limiting(state);
  String get headline => _engine.formatHeadline(state);
  double get headlineFraction => _engine.headlineFraction(state);

  /// Live countdown of the limiting tank — "1d 17h 33m 08s". Ticks every
  /// second because the ticker recomputes that often.
  String get countdown =>
      _engine.formatCountdown(_engine.headlineHours(state));

  /// Per-tank remaining time for the bar rows — "41h" / "13d".
  String get hydrationTime => _engine.formatRemaining(state.hydrationH);
  String get energyTime => _engine.formatRemaining(state.energyH);

  /// "+7h" shown briefly next to a tank after it was refilled.
  String? gainFor(TankKind t) => _gainTank == t ? _gainText : null;

  /// Which tank is currently in "survive" mode (≤10%).
  TankKind? get hungryTank {
    if (state.hydrationH <= 0.10 * SurvivalEngine.waterCapH) {
      return TankKind.hydration;
    }
    if (state.energyH <= 0.10 * SurvivalEngine.energyCapH) {
      return TankKind.energy;
    }
    return null;
  }

  /// Total debounced taps so far — the 'spam certified' badge counter.
  int get spamCount => _settings.spamCount();

  /// Lifetime count of lines the model actually generated — feeds the
  /// 'heard the brain' badge.
  int get aiLines => _settings.aiLines();

  Map<String, int> get stats {
    final evs = eventLog;
    return {
      'meals': evs.where((e) => e.type == EventType.ate).length,
      'drinks': evs.where((e) => e.type == EventType.drank).length,
      'days': daysAlive,
    };
  }

  // ---- Write API ----

  static const _debounce = Duration(seconds: 5);
  DateTime? _lastAte;
  DateTime? _lastDrank;

  /// Tap ATE: look up the slot → preset portion → log → persona line.
  /// Returns the line to display (spam line if debounced).
  Future<String> logAte({EventSource source = EventSource.app}) async {
    final now = DateTime.now();
    if (source == EventSource.app && _spam(_lastAte, now)) {
      _lastAte = now;
      return _spamLine();
    }
    _lastAte = now;
    _spamming = false;

    final slot = MealSlot.fromHour(now.hour);
    final kcal = presets.kcalFor(slot);
    final before = state.energyH;
    await _events
        .append(_engine.ateEvent(now, kcal, source: source));
    _recompute();
    _showGain(TankKind.energy, state.energyH - before);
    await _speak(PersonaContext.ate, food: presets.favFor(slot));
    onStateChanged?.call();
    return _line;
  }

  Future<String> logDrank({EventSource source = EventSource.app}) async {
    final now = DateTime.now();
    if (source == EventSource.app && _spam(_lastDrank, now)) {
      _lastDrank = now;
      return _spamLine();
    }
    _lastDrank = now;
    _spamming = false;

    final before = state.hydrationH;
    await _events.append(
        _engine.drankEvent(now, presets.drinkSize.ml, source: source));
    _recompute();
    _showGain(TankKind.hydration, state.hydrationH - before);
    await _speak(PersonaContext.drank);
    onStateChanged?.call();
    return _line;
  }

  /// Flash "+Nh" next to a tank for a few seconds — makes the refill
  /// mechanism visible right where it happened.
  void _showGain(TankKind tank, double gainedH) {
    _gainTank = tank;
    _gainText = '+${gainedH.round()}h';
    _gainTimer?.cancel();
    _gainTimer = Timer(const Duration(seconds: 3), () {
      _gainTank = null;
      notifyListeners();
    });
    notifyListeners();
  }

  bool _spam(DateTime? last, DateTime now) =>
      last != null && now.difference(last) < _debounce;

  String _spamLine() {
    _speakSeq++; // kill any in-flight stream — spam lines are instant
    _settings.bumpSpam(); // feeds the 'spam certified' badge
    _spamming = true;
    _lineStreaming = false;
    _lineIsAi = false;
    _line = _persona.pick(PersonaContext.spam);
    notifyListeners();
    return _line;
  }

  /// Stream the persona line into [_line] chunk-by-chunk so the home
  /// screen shows the model typing. A newer _speak call supersedes an
  /// in-flight stream via the seq counter.
  Future<void> _speak(PersonaContext ctx, {String? food}) async {
    final seq = ++_speakSeq;
    _line = '';
    _lineStreaming = true;
    _lineIsAi = false;
    notifyListeners();

    final buf = StringBuffer();
    final streamer = aiLineStreamer;
    if (streamer != null) {
      try {
        await for (final chunk
            in streamer(ctx, stats, food: food ?? '')) {
          if (seq != _speakSeq) return; // superseded mid-stream
          buf.write(chunk);
          _line = _tidy(buf.toString());
          _lineIsAi = _line.isNotEmpty;
          notifyListeners();
        }
      } catch (_) {
        buf.clear();
      }
    }
    if (seq != _speakSeq) return;
    _lineStreaming = false;
    _line = _capWords(buf.toString().trim(), 12);
    _lineIsAi = _line.isNotEmpty;
    if (_line.isEmpty) {
      _line = _persona.pick(ctx); // canned fallback
      _lineIsAi = false;
    } else {
      _settings.bumpAiLines();
    }
    notifyListeners();
  }

  /// Light tidy per chunk — strip quotes/newlines while it types.
  static String _tidy(String s) => s
      .replaceAll('\n', ' ')
      .replaceAll(RegExp('^["\']+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trimLeft();

  static String _capWords(String s, int max) {
    final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.length <= max ? s.trim() : '${words.take(max).join(' ')}…';
  }

  /// Public recompute — call on app resume (time passed, or events were
  /// logged via notification actions while the app was dead).
  void refresh() => _recompute();

  /// Refresh persona line to match the current tank state (called on
  /// state changes that aren't taps — e.g., crossing into hungry).
  void _recompute() {
    _state = _engine.fold(
      _events.events(),
      startTs: _events.installTs(),
      now: DateTime.now().toUtc(),
      waterRate: _settings.waterRate(),
      gapFillEnabled: _settings.gapFill(),
    );
    // Nudge the line when the tank crosses into hungry while idle —
    // but only on the transition, or the 1s ticker re-picks every second.
    final hungry = hungryTank;
    if (hungry != _lastHungry) {
      _lastHungry = hungry;
      if (hungry != null && !_spamming && !_lineStreaming) {
        _line = _persona.pick(hungry == TankKind.hydration
            ? PersonaContext.lowHydration
            : PersonaContext.lowEnergy);
        _lineIsAi = false;
      }
    }
    notifyListeners();
  }

  // ---- Settings passthrough ----

  Future<void> savePresets(PortionPresets p) => _settings.savePresets(p);
  bool get gapFillEnabled => _settings.gapFill();
  Future<void> setGapFill(bool v) async {
    await _settings.setGapFill(v);
    _recompute();
  }

  bool get itsHot => _settings.itsHot();
  Future<void> setHot(bool v) async {
    await _settings.setHot(v);
    _recompute();
    onStateChanged?.call();
  }

  bool get movedToday => _settings.movedToday();
  Future<void> setMovedToday(bool v) async {
    await _settings.setMovedToday(v);
    _recompute();
    onStateChanged?.call();
  }

  double get waterRate => _settings.waterRate();

  bool get notificationsEnabled => _settings.notificationsEnabled();
  Future<void> setNotificationsEnabled(bool v) =>
      _settings.setNotificationsEnabled(v);
  int get quietStart => _settings.quietStart();
  int get quietEnd => _settings.quietEnd();
  bool get onboarded => _settings.onboarded();
  Future<void> setOnboarded() => _settings.setOnboarded();
  bool get modelReady => _settings.modelReady();
  Future<void> setModelReady(bool v) => _settings.setModelReady(v);

  /// Weekly report stats for the share card (Phase 7).
  Map<String, Object> weeklyStats() {
    final evs = eventLog;
    final week = DateTime.now().subtract(const Duration(days: 7)).toUtc();
    final meals = evs.where((e) => e.type == EventType.ate && e.tsUtc.isAfter(week)).length;
    final drinks = evs.where((e) => e.type == EventType.drank && e.tsUtc.isAfter(week)).length;
    return {
      'days': 7,
      'meals': meals,
      'drinks': drinks,
      'daysAlive': daysAlive,
      'survivalEstimate': headline,
    };
  }

  /// Full reset — clears the log AND install timestamp (tanks refill),
  /// kills any in-flight persona stream, resets the line and debounce,
  /// and syncs notifications + widget via onStateChanged.
  Future<void> wipe() async {
    await _events.clear();
    _speakSeq++; // kill in-flight stream writes
    _lineStreaming = false;
    _spamming = false;
    _lastAte = null;
    _lastDrank = null;
    _lineIsAi = false;
    _lastHungry = null;
    _gainTank = null;
    _gainTimer?.cancel();
    _recompute(); // starving now — picks the right hungry line itself
    onStateChanged?.call();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _gainTimer?.cancel();
    super.dispose();
  }
}
