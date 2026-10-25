import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

enum NetKind { airplane, wifi, data, offline, unknown }

/// Three connectivity chips (airplane / wifi / data) — the active one
/// lights up. Polls a tiny MethodChannel every 2s because connectivity_plus
/// can't distinguish airplane mode from "no signal".
class NetChips extends StatefulWidget {
  const NetChips({super.key});

  @override
  State<NetChips> createState() => _NetChipsState();
}

class _NetChipsState extends State<NetChips> {
  static const _channel = MethodChannel('mvp/net');
  NetKind _kind = NetKind.unknown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer =
        Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  Future<void> _tick() async {
    try {
      final s = await _channel.invokeMethod<String>('status');
      if (mounted) {
        setState(() => _kind = switch (s) {
              'airplane' => NetKind.airplane,
              'wifi' => NetKind.wifi,
              'data' => NetKind.data,
              'offline' => NetKind.offline,
              _ => NetKind.unknown,
            });
      }
    } catch (_) {
      if (mounted) setState(() => _kind = NetKind.unknown);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chip(
          icon: Icons.airplanemode_active,
          label: 'air',
          active: _kind == NetKind.airplane,
        ),
        const SizedBox(width: 6),
        _Chip(
          icon: Icons.wifi,
          label: 'wifi',
          active: _kind == NetKind.wifi,
        ),
        const SizedBox(width: 6),
        _Chip(
          icon: Icons.signal_cellular_alt,
          label: 'data',
          active: _kind == NetKind.data,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.icon, required this.label, required this.active});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? MvpTheme.accent : MvpTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MvpTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: active ? MvpTheme.accent : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, color: color)),
        ],
      ),
    );
  }
}

/// Three dots doing a traveling wave — the "gemma is thinking" tell.
/// Parent decides when to mount it.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, this.color = MvpTheme.accent});

  final Color color;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final wave =
              0.5 + 0.5 * math.sin(_c.value * 2 * math.pi + i * 1.05);
          return Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color
                  .withValues(alpha: 0.25 + 0.75 * wave),
            ),
          );
        }),
      ),
    );
  }
}
