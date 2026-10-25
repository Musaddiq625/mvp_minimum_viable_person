import 'package:flutter/material.dart';

import '../ai/gemma_service.dart';
import '../app_state.dart';
import '../engine/models.dart';
import 'nerd_view.dart';
import 'net_chips.dart';
import 'presets_screen.dart';
import 'settings_screen.dart';
import 'share_card.dart';
import 'theme.dart';

/// Quiet underlined links under the buttons — shrink-wrapped, no fat
/// TextButton tap-target padding inflating the gaps.
final _linkStyle = TextButton.styleFrom(
  minimumSize: Size.zero,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// The whole app, basically: one number, one bar, one line, two buttons.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.app, this.gemma});

  final AppState app;
  final GemmaService? gemma;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Stack(
        children: [
          Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final hungry = app.hungryTank;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status strip: connectivity chips + settings gear.
                  SizedBox(
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const NetChips(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: const Icon(Icons.settings_outlined,
                                color: MvpTheme.textMuted),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => SettingsScreen(
                                      app: app, gemma: gemma)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Model name + thinking dots — lights whenever inference
                  // is actually running (lines, reports, kcal estimates).
                  if (gemma != null)
                    ListenableBuilder(
                      listenable: gemma!,
                      builder: (context, _) {
                        final busy =
                            gemma!.thinking || app.lineStreaming;
                        return SizedBox(
                          height: 16,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'gemma 3n e2b-it litert preview',
                                style: TextStyle(
                                    color: MvpTheme.textMuted,
                                    fontSize: 10),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 24,
                                child:
                                    busy ? const ThinkingDots() : null,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const Spacer(),
                  // Headline: time until the limiting tank is empty.
                  GestureDetector(
                    onLongPress: () => showNerdView(context, app, gemma),
                    child: Column(
                      children: [
                        _Breathing(
                          child: Text(app.headline,
                              style:
                                  Theme.of(context).textTheme.displayLarge),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          hungry == null
                              ? 'OF SURVIVAL LEFT'
                              : 'FEED THE TANK',
                          style: TextStyle(
                            fontSize: 15,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w500,
                            color: hungry == null
                                ? MvpTheme.accent
                                : MvpTheme.warn,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // The live countdown — ticks every second, proves
                        // the decay isn't a static number.
                        Text(
                          app.countdown,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            letterSpacing: 1.5,
                            color: MvpTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Two tanks, both visible — food and water
                        // don't share a bar anymore.
                        _TankRow(
                          label: 'Food 🍔',
                          fraction: app.energyFraction,
                          time: app.energyTime,
                          gain: app.gainFor(TankKind.energy),
                          hungry: hungry == TankKind.energy,
                        ),
                        const SizedBox(height: 8),
                        _TankRow(
                          label: 'Water 💧',
                          fraction: app.hydrationFraction,
                          time: app.hydrationTime,
                          gain: app.gainFor(TankKind.hydration),
                          hungry: hungry == TankKind.hydration,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Persona line — streams in token-by-token (cursor shows
                  // while the model types), signed when AI-written.
                  Column(
                    children: [
                      Text(
                        app.lineStreaming ? '${app.line}▌' : app.line,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 14,
                        child: app.lineIsAi
                            ? const Text('— Gemma, on-device',
                                style: TextStyle(
                                    color: MvpTheme.textMuted,
                                    fontSize: 10))
                            : null,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: _ChunkyButton(
                          label: 'ATE 🍔',
                          hungry: hungry == TankKind.energy,
                          onTap: () => app.logAte(),
                          // Slightly lopsided corners — cartoon button.
                          radius: const BorderRadius.only(
                            topLeft: Radius.circular(28),
                            topRight: Radius.circular(14),
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ChunkyButton(
                          label: 'DRANK 💧',
                          hungry: hungry == TankKind.hydration,
                          onTap: () => app.logDrank(),
                          radius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(28),
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  for (final (label, onPressed) in [
                    (
                      'How much do you eat often?',
                      () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PresetsScreen(app: app))),
                    ),
                    (
                      'How did I do this week? — AI',
                      () => showWeeklyReport(context, app, gemma),
                    ),
                    // The nerd view exists — long-pressing the headline is
                    // too secret a door. Lazy people need a sign.
                    (
                      'The numbers — nerd',
                      () => showNerdView(context, app, gemma),
                    ),
                  ])
                    Center(
                      child: TextButton(
                        style: _linkStyle,
                        onPressed: onPressed,
                        child: Text(label,
                            style: const TextStyle(
                                color: MvpTheme.textMuted,
                                decoration: TextDecoration.underline,
                                decorationColor: MvpTheme.textMuted)),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
          ),
          // Edge glow — ambient "you're starving" vignette bleeding in
          // from the screen edges (outside SafeArea on purpose).
          if (app.hungryTank != null)
            const Positioned.fill(
              child: IgnorePointer(child: _StarveGlow()),
            ),
        ],
      ),
    );
  }
}

/// One labeled tank row: "food  ▓▓▓▓░  13d +7h". The bar fills for the
/// next 24h of coverage; the number shows total remaining time, and a
/// "+Nh" chip flashes for ~3s after a refill.
class _TankRow extends StatelessWidget {
  const _TankRow({
    required this.label,
    required this.fraction,
    required this.time,
    required this.hungry,
    this.gain,
  });

  final String label;
  final double fraction;
  final String time;
  final bool hungry;
  final String? gain;

  @override
  Widget build(BuildContext context) {
    final color = hungry ? MvpTheme.warn : MvpTheme.accent;
    const labelStyle =
        TextStyle(color: MvpTheme.textMuted, fontSize: 11);
    return Row(
      children: [
        SizedBox(width: 42, child: Text(label, style: labelStyle)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Stack(
                children: [
                  Container(color: MvpTheme.surface),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: fraction.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (_, v, c) => FractionallySizedBox(
                      widthFactor: v,
                      alignment: Alignment.centerLeft,
                      child: Container(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: gain != null
                    ? Text('$gain ',
                        key: const ValueKey('gain'),
                        style: const TextStyle(
                            color: MvpTheme.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))
                    : const SizedBox.shrink(key: ValueKey('none')),
              ),
              Text(time,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: MvpTheme.text,
                      fontSize: 11,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ambient "you're starving" vignette — a warn-colored radial glow that
/// pulses in from the screen edges while any tank is ≤10%. No words,
/// just dread.
class _StarveGlow extends StatefulWidget {
  const _StarveGlow();

  @override
  State<_StarveGlow> createState() => _StarveGlowState();
}

class _StarveGlowState extends State<_StarveGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.35,
            colors: [
              Colors.transparent,
              MvpTheme.warn
                  .withValues(alpha: 0.10 + 0.16 * _c.value),
            ],
            stops: const [0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

/// The headline breathes — a ±1.5% scale over ~4s so the screen feels
/// alive even when the user does nothing. Which is most of the time.
class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});

  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 4))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.scale(
        scale: 1.0 + 0.015 * _c.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Big chunky 3D button: a dark base slab + a face slab floating 7px above.
/// Pressing drops the face into the base — arcade button feel.
class _ChunkyButton extends StatefulWidget {
  const _ChunkyButton({
    required this.label,
    required this.hungry,
    required this.onTap,
    required this.radius,
  });

  final String label;
  final bool hungry;
  final VoidCallback onTap;
  final BorderRadius radius;

  static const depth = 7.0;
  static const faceHeight = 104.0;

  @override
  State<_ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<_ChunkyButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..addListener(() => setState(() {}));

  @override
  void didUpdateWidget(_ChunkyButton old) {
    super.didUpdateWidget(old);
    if (widget.hungry && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.hungry && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.hungry) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.hungry ? MvpTheme.warn : MvpTheme.accent;
    final base = Color.lerp(color, Colors.black, 0.38)!;
    final scale = widget.hungry ? 1.0 + _pulse.value * 0.03 : 1.0;
    return Transform.scale(
      scale: scale,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: SizedBox(
          height: _ChunkyButton.faceHeight + _ChunkyButton.depth,
          child: Stack(
            children: [
              // Base slab — stays put; the face drops into it.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _ChunkyButton.faceHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: base, borderRadius: widget.radius),
                ),
              ),
              // Face slab — floats above the base, sinks on press.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _ChunkyButton.faceHeight,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 70),
                  curve: Curves.easeOut,
                  transform: Matrix4.translationValues(
                      0, _pressed ? _ChunkyButton.depth : 0, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: color, borderRadius: widget.radius),
                    child: Center(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: MvpTheme.bg),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
