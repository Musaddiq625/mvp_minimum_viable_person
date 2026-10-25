import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:background_downloader/background_downloader.dart' as bd;
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/persona_bank.dart';

enum GemmaStatus { checking, notDownloaded, downloading, ready, failed }

/// Wraps flutter_gemma: model download, lifecycle, and inference.
///
/// The model is REQUIRED — the app gates on [status] == ready before any
/// screen unlocks (it's an open-source-AI challenge entry; the AI is the
/// point). Canned lines remain only as a runtime fallback for transient
/// inference failures once the model is verified working.
///
/// Model: Gemma 3n E2B-it (.task, LiteRT/MediaPipe-managed chat template).
/// Downloads need a HuggingFace token for the gated google/ repo — pass it
/// via --dart-define HF_TOKEN. If the gate 401s (license not accepted on
/// that account), sideload the .task file instead via [installFromFile].
class GemmaService extends ChangeNotifier {
  // Model: Gemma 3n E2B-it (.task, gated — requires a HuggingFace token +
  // license acceptance on the model page). Pass the token at build time:
  //   fvm flutter run --dart-define HF_TOKEN=hf_...
  static const modelUrl =
      'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task';
  static const hfToken = String.fromEnvironment('HF_TOKEN');

  // Resumable background download — background_downloader fetches
  // natively (WorkManager), so it survives backgrounding and process
  // death, and partial bytes resume instead of restarting from zero.
  static const _taskId = 'gemma_model';
  static const _modelFile = 'gemma-3n-E2B-it-int4.task';
  static const _minModelBytes = 2000000000; // real model is ~3 GB

  StreamSubscription<bd.TaskUpdate>? _dlSub;
  bool _downloaderReady = false;
  bool _resumable = false;

  GemmaStatus _status = GemmaStatus.notDownloaded;
  double _progress = 0;
  String? _error;
  InferenceModel? _model;
  Future<void>? _initFuture;

  GemmaStatus get status => _status;
  double get progress => _progress;
  String? get error => _error;

  /// True when an interrupted download left resumable state — the gate
  /// swaps "download" for "resume" so the user keeps their progress.
  bool get resumable => _resumable;

  /// True while any inference is running — drives the "thinking" dots
  /// next to the model name on the home screen.
  int _inFlight = 0;
  bool get thinking => _inFlight > 0;

  /// MediaPipe can't run concurrent sessions — a second addQueryChunk
  /// mid-prediction crashes natively (PredictDone RET_CHECK). Every
  /// inference call takes a turn on this chain.
  Future<void> _turn = Future.value();

  Future<T> _serialized<T>(Future<T> Function() job) {
    final prev = _turn;
    final c = Completer<void>();
    _turn = c.future;
    return prev.then((_) => job()).whenComplete(c.complete);
  }

  Stream<String> _serializedStream(Stream<String> Function() job) async* {
    final prev = _turn;
    final c = Completer<void>();
    _turn = c.future;
    try {
      // Inside try: a cancelled-while-queued stream must still release
      // the turn, or every later job deadlocks.
      await prev;
      yield* job();
    } finally {
      c.complete();
    }
  }

  void _beginWork() {
    _inFlight++;
    notifyListeners();
  }

  void _endWork() {
    _inFlight--;
    notifyListeners();
  }

  /// Idempotent — kicks off plugin init + installed check. Download and
  /// sideload both await this before touching the plugin.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    _setStatus(GemmaStatus.checking);
    try {
      await FlutterGemma.initialize(
        huggingFaceToken: hfToken.isEmpty ? null : hfToken,
      );
      await _ensureDownloader();
      // The plugin's active-model spec is in-memory only — an installed
      // model still needs re-activating after every cold start, or
      // getActiveModel throws "No active inference model set".
      if (await _reactivate()) {
        await _warmup();
      } else {
        await _refreshResumable();
        _setStatus(GemmaStatus.notDownloaded);
      }
    } catch (e) {
      debugPrint('gemma init failed: $e');
      _fail('init failed: $e');
    }
  }

  /// Find any installed .task file and re-activate it. install() is
  /// idempotent: an already-registered filename skips the file handler
  /// entirely and just re-sets the in-memory active spec.
  Future<bool> _reactivate() async {
    final installed = await FlutterGemma.listInstalledModels();
    final dir = await getApplicationDocumentsDirectory();
    for (final f in installed) {
      if (!f.endsWith('.task')) continue;
      final path = '${dir.path}/$f';
      // A killed download leaves a truncated .task behind — installing
      // it would crash warmup, so only accept a plausible-size file.
      if (await File(path).length() < _minModelBytes) continue;
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(path)
          .install();
      return true;
    }
    return false;
  }

  /// One-time wiring for the native downloader: persistent task records
  /// (resume across process death), the Android download notification
  /// the background service requires, and the update listener that
  /// drives the gate UI.
  Future<void> _ensureDownloader() async {
    if (_downloaderReady) return;
    _downloaderReady = true;
    await bd.FileDownloader().trackTasks();
    bd.FileDownloader().configureNotification(
      running:
          const bd.TaskNotification('Downloading the brain', '{filename}'),
      paused: const bd.TaskNotification(
          'Brain download paused', 'tap to resume'),
      error: const bd.TaskNotification(
          'Brain download failed', 'open the app to resume'),
      progressBar: true,
    );
    _dlSub ??= bd.FileDownloader().updates.listen(_onDownloadUpdate);
  }

  /// Detect an interrupted download so the gate can offer resume: a
  /// tracked task record with no finished file, or a truncated .task
  /// still sitting on disk.
  Future<void> _refreshResumable() async {
    var partial = false;
    var full = false;
    final dir = await getApplicationDocumentsDirectory();
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.task')) continue;
      if (await f.length() < _minModelBytes) {
        partial = true;
      } else {
        full = true;
      }
    }
    final task = await bd.FileDownloader().taskForId(_taskId);
    _resumable = partial || (task != null && !full);
    notifyListeners();
  }

  /// Route native download events into the same status/progress fields
  /// the gate already renders.
  void _onDownloadUpdate(bd.TaskUpdate update) {
    if (update.task.taskId != _taskId) return;
    switch (update) {
      case bd.TaskStatusUpdate u:
        switch (u.status) {
          case bd.TaskStatus.complete:
            unawaited(_finishInstall(u.task));
          case bd.TaskStatus.failed || bd.TaskStatus.notFound:
            _resumable = true;
            _fail(_explain(
                'http ${u.responseStatusCode ?? '?'}: ${u.exception ?? 'download failed'}'));
          case bd.TaskStatus.paused || bd.TaskStatus.canceled:
            _resumable = true;
            _setStatus(GemmaStatus.notDownloaded);
          case _:
            _setStatus(GemmaStatus.downloading);
        }
      case bd.TaskProgressUpdate u:
        if (u.progress >= 0 && u.progress < 1) {
          _setStatus(GemmaStatus.downloading);
          _setProgress(u.progress);
        }
    }
  }

  /// Download finished — register the file with flutter_gemma, then
  /// warm it up before the gate opens. The brief settle gives
  /// WorkManager time to tear down its foreground service before we
  /// mmap ~3 GB and spin up the GPU engine (the heaviest moment of
  /// the whole flow — a crash here was reported once).
  Future<void> _finishInstall(bd.Task task) async {
    try {
      _resumable = false;
      debugPrint('gemma: download complete, settling before install…');
      await Future.delayed(const Duration(milliseconds: 750));
      final path = await (task as bd.DownloadTask).filePath();
      debugPrint('gemma: installing model file…');
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(path)
          .install();
      debugPrint('gemma: installed, warming up…');
      await _warmup();
      debugPrint('gemma: warmup done');
    } catch (e) {
      debugPrint('gemma install failed: $e');
      _fail(_explain(e));
    }
  }

  /// Remove truncated .task files so a fresh enqueue can't hand a
  /// corrupt partial to the model installer.
  Future<void> _deletePartials() async {
    final dir = await getApplicationDocumentsDirectory();
    await for (final f in dir.list()) {
      if (f is File &&
          f.path.endsWith('.task') &&
          await f.length() < _minModelBytes) {
        await f.delete();
      }
    }
  }

  /// Download — or resume — the model via the native downloader. Keeps
  /// running in the background, and a killed/failed download resumes
  /// from its partial bytes instead of starting over from zero.
  Future<void> download() async {
    if (_status == GemmaStatus.downloading) return;
    _setStatus(GemmaStatus.downloading);
    _error = null;
    try {
      await init();
      await _ensureDownloader();

      // A complete-but-unregistered file skips the network entirely —
      // covers "download finished, install never ran".
      final dir = await getApplicationDocumentsDirectory();
      final finished = File('${dir.path}/$_modelFile');
      if (await finished.exists() &&
          await finished.length() >= _minModelBytes) {
        await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
            .fromFile(finished.path)
            .install();
        await _warmup();
        return;
      }

      // Resume beats restart: a paused/failed/killed task keeps its
      // partial bytes. resume() returns false when no native resume
      // data exists — then fall through to a fresh enqueue.
      final existing = await bd.FileDownloader().taskForId(_taskId);
      if (existing is bd.DownloadTask &&
          await bd.FileDownloader().resume(existing)) {
        return; // status + progress flow back through _onDownloadUpdate
      }

      await _deletePartials();
      _setProgress(0);
      final task = bd.DownloadTask(
        taskId: _taskId,
        url: modelUrl,
        filename: _modelFile,
        headers: {
          if (hfToken.isNotEmpty) 'Authorization': 'Bearer $hfToken',
        },
        allowPause: true,
        retries: 3,
        updates: bd.Updates.statusAndProgress,
      );
      if (!await bd.FileDownloader().enqueue(task)) {
        throw StateError('download task rejected by the platform');
      }
    } catch (e) {
      debugPrint('gemma download failed: $e');
      _fail(_explain(e));
    }
  }

  /// Sideload escape hatch: install a .task file picked off device storage.
  /// Used when the gated HF repo 401s (license pending) — download it in a
  /// browser while logged in, then pick it here.
  Future<void> installFromFile(String path) async {
    if (_status == GemmaStatus.downloading) return;
    _setStatus(GemmaStatus.downloading);
    _setProgress(0);
    _error = null;
    try {
      await init();
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(path)
          .withProgress((p) => _setProgress(p / 100))
          .install();
      await _warmup();
    } catch (e) {
      debugPrint('gemma sideload failed: $e');
      _fail(_explain(e));
    }
  }

  /// Actually load the model and prove it generates — the gate only opens
  /// for a model that works, not just one that downloaded.
  Future<void> _warmup() async {
    _model ??= await FlutterGemma.getActiveModel(
      preferredBackend: PreferredBackend.gpu,
      maxTokens: 512,
    );
    final session = await _model!.createSession(
      temperature: 0.9,
      topK: 40,
      topP: 0.95,
      systemInstruction: _system,
    );
    try {
      await session.addQueryChunk(
          Message.text(text: 'say ok', isUser: true));
      await session.getResponse();
    } finally {
      try {
        await session.close();
      } catch (_) {}
    }
    _resumable = false;
    _setStatus(GemmaStatus.ready);
  }

  void _fail(String message) {
    _error = message;
    _setStatus(GemmaStatus.failed);
  }

  /// Turn plugin exceptions into something a lazy user can act on.
  String _explain(Object e) {
    final msg = e.toString();
    if (msg.contains('401') || msg.contains('Authentication required')) {
      return 'huggingface said 401 — token not sent or invalid. rebuild '
          'with --dart-define HF_TOKEN=hf_... and retry. or load the '
          'model file below.';
    }
    if (msg.contains('403') || msg.contains('forbidden') ||
        msg.contains('does not have access')) {
      return 'huggingface said 403 — your token works, but that account '
          'hasn\'t been granted gemma 3n e2b-it litert preview yet. open the model page '
          '(huggingface.co/google/gemma-3n-E2B-it-litert-preview) → '
          '"agree and access repository" with the token\'s account '
          '(approval can take a while), or load the model file below.';
    }
    return 'download failed. check wi-fi and retry.\n$msg';
  }

  /// Generate one persona line for a context. Returns null if the model
  /// isn't ready — caller falls back to the canned bank.
  Future<String?> generateLine(
      PersonaContext ctx, Map<String, Object> stats) async {
    final prompt = _promptFor(ctx, stats);
    if (prompt == null) return null;
    final raw = await _generate(prompt, maxWords: 8);
    return _sanitize(raw);
  }

  /// Stream a persona line token-by-token — the visible "AI is typing"
  /// moment. [food] makes ATE lines react to the actual fav food.
  Stream<String> streamLine(
      PersonaContext ctx, Map<String, Object> stats,
      {String? food}) {
    final prompt = _promptFor(ctx, stats, food: food);
    if (prompt == null) return const Stream.empty();
    return _streamGenerate(prompt);
  }

  /// Stream the weekly report — the long text types itself into the
  /// shareable card. Even better demo than a finished wall of text.
  Stream<String> streamReport(Map<String, Object> stats) {
    return _streamGenerate(
        'Write a funny 3-line weekly survival report for a lazy '
        'person tracking app. Stats: '
        '${stats.entries.map((e) => '${e.key}=${e.value}').join(', ')}. '
        'Tone: unimpressed but secretly proud. Mention zero effort.');
  }

  /// Estimate calories for one serving of a named food. This is the job
  /// that puts the model inside the survival loop — fav-food kcal feeds
  /// the tanks directly. Returns null when unsure; callers keep defaults.
  Future<int?> estimateKcal(String food) async {
    final trimmed = food.trim();
    if (trimmed.length < 3 || _status != GemmaStatus.ready) return null;
    final raw = await _generate(
      'Estimate the total calories in one typical serving of "$trimmed". '
      'Reply with ONLY a whole number. No units, no text.',
      maxWords: 5,
    );
    final digits = RegExp(r'\d+').firstMatch(raw ?? '');
    final kcal = int.tryParse(digits?.group(0) ?? '');
    if (kcal == null || kcal < 50 || kcal > 3000) return null;
    return kcal;
  }

  /// Weekly report — the one place the AI writes long text.
  Future<String?> generateReport(Map<String, Object> stats) async {
    final prompt = 'Write a funny 3-line weekly survival report for a lazy '
        'person tracking app. Stats: ${stats.entries.map((e) => '${e.key}=${e.value}').join(', ')}. '
        'Tone: unimpressed but secretly proud. Mention zero effort.';
    return _generate(prompt, maxWords: 60);
  }

  String? _promptFor(PersonaContext ctx, Map<String, Object> stats,
      {String? food}) {
    final situation = switch (ctx) {
      PersonaContext.ate => food != null && food.isNotEmpty
          ? 'The user just logged a meal — probably their usual "$food" — '
              'and survival got extended. Say one flat, relieved line: we '
              'survived a bit longer. You may name the food. Never mention '
              'tanks, levels, or numbers. Never tell them to do anything. '
              'Vibes (do not copy): "${_ackVibes()}"'
          : 'The user just logged a meal and survival got extended. Say '
              'one flat, relieved line: we survived a bit longer. Never '
              'mention tanks, levels, or numbers. Never tell them to do '
              'anything. Vibes (do not copy): "${_ackVibes()}"',
      PersonaContext.drank =>
        'The user just logged a drink and survival got extended. Say one '
            'flat, relieved line: we survived a bit longer. Never mention '
            'tanks, levels, or numbers. Never tell them to do anything. '
            'Vibes (do not copy): "${_ackVibes()}"',
      PersonaContext.lowHydration => 'The water tank is running low.',
      PersonaContext.lowEnergy => 'The food tank is running low.',
      PersonaContext.zeroHydration => 'The water tank hit zero.',
      PersonaContext.zeroEnergy => 'The food tank hit zero.',
      PersonaContext.spam => 'The user spam-tapped a button twice in 5 seconds.',
      PersonaContext.daily => 'The user opened the app today.',
    };
    return '$situation Say one lazy, unimpressed but slightly helpful line.';
  }

  /// Ack vibes — two are sampled into each log-ack prompt so the wording
  /// varies (same prompt → same output otherwise). They also anchor the
  /// desired tone: flat relief that survival got extended.
  static const _ackBank = [
    'alive a bit longer. nice.',
    'we survive. barely tried.',
    'ok. survival extended.',
    'still going. impressive-ish.',
    'survival secured. for now.',
    'points for existing.',
    'we live another hour.',
    'not dead. as planned.',
  ];

  static final _rng = math.Random();

  static String _ackVibes() {
    final a = _ackBank[_rng.nextInt(_ackBank.length)];
    var b = a;
    while (b == a) {
      b = _ackBank[_rng.nextInt(_ackBank.length)];
    }
    return '$a" / "$b';
  }

  static const _system =
      'You are a lazy roommate in a joke survival app. You cannot be bothered, '
      'but you do not want the user to actually die. Reply with ONE short '
      'line, max 8 words, lowercase, dry humor. '
      'When the user logs food or water, acknowledge it with flat relief '
      'that you both survived a bit longer — never mention tanks or '
      'levels, never tell them to do more work; they already did the '
      'thing. Nudging toward eating/drinking is only for the low-tank '
      'contexts, never after a successful log. '
      'Never mention death, streaks, or willpower.';

  Future<String?> _generate(String prompt, {required int maxWords}) =>
      _serialized(() => _generateImpl(prompt));

  Future<String?> _generateImpl(String prompt) async {
    if (_status != GemmaStatus.ready) return null;
    _beginWork();
    InferenceModelSession? session;
    try {
      _model ??= await FlutterGemma.getActiveModel(
        preferredBackend: PreferredBackend.gpu,
        maxTokens: 512,
      );
      session = await _model!.createSession(
        temperature: 0.9,
        topK: 40,
        topP: 0.95,
        systemInstruction: _system,
      );
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      return await session.getResponse();
    } catch (e) {
      debugPrint('gemma generate failed: $e');
      return null;
    } finally {
      try {
        await session?.close();
      } catch (_) {}
      _endWork();
    }
  }

  /// Token-by-token generation — yields raw chunks as they arrive.
  /// Callers buffer/tidy; this stream ends when the model finishes.
  /// Serialized: holds the turn until the stream closes or is cancelled.
  Stream<String> _streamGenerate(String prompt) =>
      _serializedStream(() => _streamGenerateImpl(prompt));

  Stream<String> _streamGenerateImpl(String prompt) async* {
    if (_status != GemmaStatus.ready) return;
    _beginWork();
    InferenceModelSession? session;
    try {
      _model ??= await FlutterGemma.getActiveModel(
        preferredBackend: PreferredBackend.gpu,
        maxTokens: 512,
      );
      session = await _model!.createSession(
        temperature: 0.9,
        topK: 40,
        topP: 0.95,
        systemInstruction: _system,
      );
      await session.addQueryChunk(
          Message.text(text: prompt, isUser: true));

      // Manual pump instead of yield*: when the consumer cancels early
      // (superseded tap), native keeps generating — close() then throws
      // "Previous invocation still processing" and the next createSession
      // hits the still-busy session too. Always drain to done first.
      final it = StreamIterator(session.getResponseAsync());
      try {
        while (await it.moveNext()) {
          yield it.current;
        }
      } finally {
        try {
          while (await it
              .moveNext()
              .timeout(const Duration(seconds: 15))) {}
        } catch (_) {}
        await it.cancel();
      }
    } catch (e) {
      debugPrint('gemma stream failed: $e');
    } finally {
      try {
        await session?.close();
      } catch (_) {}
      _endWork();
    }
  }

  /// Keep the model honest: single line, ≤8 words, lowercase vibe.
  String? _sanitize(String? raw) {
    if (raw == null) return null;
    var line = raw.trim().split('\n').first.trim();
    // Strip quotes/emoji the model sometimes adds.
    line = line.replaceAll(RegExp('^["\']+|["\']+\$'), '');
    final words = line.split(RegExp(r'\s+'));
    if (words.isEmpty || line.length < 3) return null;
    if (words.length > 10) line = words.take(10).join(' ');
    return line;
  }

  void _setStatus(GemmaStatus s) {
    _status = s;
    notifyListeners();
  }

  void _setProgress(double p) {
    _progress = p;
    notifyListeners();
  }

  @override
  void dispose() {
    _dlSub?.cancel();
    _model?.close();
    super.dispose();
  }
}
