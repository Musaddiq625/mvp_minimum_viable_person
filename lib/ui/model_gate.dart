import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ai/gemma_service.dart';
import 'theme.dart';

/// Blocking gate: the app does not exist until the local model works.
/// No skip button — the AI is the product (open-source AI challenge).
class ModelGateScreen extends StatelessWidget {
  const ModelGateScreen({super.key, required this.gemma});

  final GemmaService gemma;

  Future<void> _pickModelFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Pick the model file',
      type: FileType.any,
    );
    final path = file?.path;
    if (path != null) await gemma.installFromFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ListenableBuilder(
            listenable: gemma,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Text('MVP', style: t.displayLarge),
                  const Text(
                    'Minimum Viable Person',
                    style: TextStyle(
                        color: MvpTheme.accent,
                        fontSize: 15,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'runs on a local open-weights brain.\nno brain, no app.',
                    style: t.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Gemma 3n E2B-it LiteRT Preview · ~3 GB',
                    style: TextStyle(color: MvpTheme.accent, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  switch (gemma.status) {
                    GemmaStatus.checking => const _Checking(),
                    GemmaStatus.downloading => _Downloading(gemma: gemma),
                    GemmaStatus.failed => _Failed(gemma: gemma),
                    _ => _DownloadPrompt(gemma: gemma),
                  },
                  const SizedBox(height: 12),
                  if (gemma.status == GemmaStatus.notDownloaded ||
                      gemma.status == GemmaStatus.failed)
                    Center(
                      child: TextButton(
                        onPressed: _pickModelFile,
                        child: const Text(
                          'Already have the model file? load it',
                          style: TextStyle(
                            color: MvpTheme.textMuted,
                            decoration: TextDecoration.underline,
                            decorationColor: MvpTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  const Center(
                    child: Text(
                      'on-device · offline · nothing leaves this phone',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: MvpTheme.textMuted, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Warmup is ~10-15s on-device (3gb mmap + OpenCL shader compile).
/// No real progress callback exists, so: pulsing orb, creeping bar
/// (eases to ~92% over 16s — matches observed load time), and rotating
/// lazy status messages. Deliberate, not frozen.
class _Checking extends StatefulWidget {
  const _Checking();

  @override
  State<_Checking> createState() => _CheckingState();
}

class _CheckingState extends State<_Checking>
    with SingleTickerProviderStateMixin {
  static const _msgs = [
    'waking the brain…',
    'loading 3 gb of lazy…',
    'compiling shaders on your gpu…',
    'teaching it to care (barely)…',
    'asking it to be nice to you…',
    'almost there. probably.',
  ];

  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 16))
    ..forward();
  Timer? _timer;
  int _msg = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (mounted) setState(() => _msg = (_msg + 1) % _msgs.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Orb breathes ~8 cycles over the load; bar creeps to ~92%.
        final pulse = 0.5 + 0.5 * math.sin(_c.value * 2 * math.pi * 8);
        final pct = (0.92 * Curves.easeOut.transform(_c.value))
            .clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MvpTheme.accent
                      .withValues(alpha: 0.15 + 0.2 * pulse),
                  border: Border.all(
                      color: MvpTheme.accent
                          .withValues(alpha: 0.4 + 0.6 * pulse),
                      width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: MvpTheme.accent
                          .withValues(alpha: 0.10 + 0.25 * pulse),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _msgs[_msg],
                key: ValueKey(_msg),
                textAlign: TextAlign.center,
                style: t.bodyLarge,
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: LinearProgressIndicator(
                  value: pct,
                  color: MvpTheme.accent,
                  backgroundColor: MvpTheme.surface,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(pct * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: MvpTheme.textMuted, fontSize: 11),
            ),
          ],
        );
      },
    );
  }
}

class _DownloadPrompt extends StatelessWidget {
  const _DownloadPrompt({required this.gemma});

  final GemmaService gemma;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: MvpTheme.accent,
        foregroundColor: MvpTheme.bg,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: gemma.download,
      child: Text(gemma.resumable
          ? '🧠 Resume the brain download'
          : '🧠 Download the brain (~3 GB, Wi-Fi)'),
    );
  }
}

class _Downloading extends StatelessWidget {
  const _Downloading({required this.gemma});

  final GemmaService gemma;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Downloading the brain…', style: t.bodyLarge),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: LinearProgressIndicator(
              value: gemma.progress > 0 ? gemma.progress : null,
              color: MvpTheme.accent,
              backgroundColor: MvpTheme.surface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(gemma.progress * 100).clamp(0, 100).toStringAsFixed(0)}% — fine to wander off, it keeps going',
          style: t.bodyMedium,
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.gemma});

  final GemmaService gemma;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          gemma.error ?? 'something broke.',
          style: t.bodyMedium?.copyWith(color: MvpTheme.warn),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: MvpTheme.warn,
            foregroundColor: MvpTheme.bg,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: gemma.download,
          child: Text(
              gemma.resumable ? 'resume where it left off' : 'retry'),
        ),
      ],
    );
  }
}
