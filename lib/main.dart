import 'package:flutter/material.dart';

import 'ai/gemma_service.dart';
import 'app_state.dart';
import 'engine/models.dart';
import 'notifications/notification_service.dart';
import 'ui/home_screen.dart';
import 'ui/model_gate.dart';
import 'ui/onboarding.dart';
import 'ui/theme.dart';
import 'widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final app = await AppState.init();
  final gemma = GemmaService();
  final notifications = NotificationService.instance;

  // The AI is the product — _Shell gates every screen on model readiness.
  // Persona lines stream token-by-token so the model is visibly working;
  // canned lines only cover transient inference failures after that.
  app.aiLineStreamer = (ctx, stats, {food}) =>
      gemma.streamLine(ctx, stats, food: food);
  app.onStateChanged = () {
    _reschedule(app, notifications);
    WidgetService.sync(app);
  };
  notifications.onAction = (action) =>
      action == 'ate' ? app.logAte(source: EventSource.notification) : app.logDrank(source: EventSource.notification);

  // Model init in the background — the gate screen shows until it's ready.
  gemma.init();
  notifications.init().then((_) => _reschedule(app, notifications));
  WidgetService.init().then((_) => WidgetService.sync(app));

  runApp(MvpApp(app: app, gemma: gemma));
}

void _reschedule(AppState app, NotificationService notifications) {
  notifications.reschedule(
    app.state,
    waterRate: app.waterRate,
    enabled: app.notificationsEnabled,
    quietStart: app.quietStart,
    quietEnd: app.quietEnd,
  );
}

class MvpApp extends StatelessWidget {
  const MvpApp({super.key, required this.app, required this.gemma});

  final AppState app;
  final GemmaService gemma;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MVP — Minimum Viable Person',
      debugShowCheckedModeBanner: false,
      theme: MvpTheme.dark(),
      // builder overlays the Navigator → the credit floats on every screen
      // with a transparent bg, so it inherits whatever the screen paints
      // (flat bg, hungry glow) instead of reading as a separate strip.
      builder: (context, child) => Stack(
        children: [
          Positioned.fill(child: child ?? const SizedBox.shrink()),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(child: _CreditFooter()),
          ),
        ],
      ),
      home: _Shell(app: app, gemma: gemma),
    );
  }
}

/// Floats over the Navigator — lives outside any Scaffold, so it needs
/// Material (no Material ancestor down here) and its own SafeArea.
/// Transparent so the screen's own background shows through.
class _CreditFooter extends StatelessWidget {
  const _CreditFooter();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            'Built with ♥ by Musaddiq625',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontSize: 10),
          ),
        ),
      ),
    );
  }
}

/// Gates on a working model, then shows onboarding once, then home.
/// Recomputes + reschedules on resume.
class _Shell extends StatefulWidget {
  const _Shell({required this.app, required this.gemma});

  final AppState app;
  final GemmaService gemma;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  bool _onboardingPushed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Onboarding waits for the model gate to clear first.
    widget.gemma.addListener(_maybeOnboard);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOnboard());
  }

  void _maybeOnboard() {
    if (_onboardingPushed || widget.app.onboarded || !mounted) return;
    if (widget.gemma.status != GemmaStatus.ready) return;
    _onboardingPushed = true;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OnboardingScreen(app: widget.app)));
  }

  @override
  void dispose() {
    widget.gemma.removeListener(_maybeOnboard);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.app.refresh();
      _reschedule(widget.app, NotificationService.instance);
      WidgetService.sync(widget.app);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.gemma,
      builder: (context, _) =>
          widget.gemma.status == GemmaStatus.ready
              ? HomeScreen(app: widget.app, gemma: widget.gemma)
              : ModelGateScreen(gemma: widget.gemma),
    );
  }
}
