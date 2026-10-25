import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../ai/gemma_service.dart';
import '../app_state.dart';
import 'theme.dart';

/// The weekly survival report — the AI writes it live, token-by-token,
/// inside the shareable card. Watching the card fill in IS the demo.
/// Share button unlocks when the stream finishes.
Future<void> showWeeklyReport(
  BuildContext context,
  AppState app,
  GemmaService? gemma,
) async {
  final stats = app.weeklyStats();
  final boundaryKey = GlobalKey();
  final text = ValueNotifier<String>('');
  final done = ValueNotifier<bool>(false);
  final isAi = ValueNotifier<bool>(false);
  var disposed = false;

  () async {
    try {
      final stream = gemma?.streamReport(stats);
      if (stream != null) {
        await for (final chunk in stream) {
          if (disposed) return;
          text.value += chunk;
          isAi.value = text.value.trim().isNotEmpty;
        }
      }
    } catch (_) {
      /* canned below */
    }
    if (disposed) return;
    if (text.value.trim().isEmpty) {
      text.value =
          '${stats['days']} days. ${stats['meals']} meals. '
          '${stats['drinks']} drinks. zero effort. minimum viable. '
          'honestly impressive.';
      isAi.value = false;
    }
    done.value = true;
  }();

  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        32 + MediaQuery.viewPaddingOf(ctx).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: text,
              builder: (_, report, c) => ValueListenableBuilder<bool>(
                valueListenable: done,
                builder: (_, isDone, c2) => RepaintBoundary(
                  key: boundaryKey,
                  child: _ReportCard(
                    report: report,
                    stats: stats,
                    streaming: !isDone,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: isAi,
              builder: (_, ai, c) => Text(
                ai ? '— written live by Gemma, on-device' : '— canned wisdom',
                style: const TextStyle(
                  color: MvpTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: done,
              builder: (_, isDone, c) => FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MvpTheme.accent,
                  foregroundColor: MvpTheme.bg,
                ),
                icon: const Icon(Icons.share, size: 18),
                label: Text(isDone ? 'share' : 'Gemma is typing…'),
                onPressed: isDone ? () => _share(boundaryKey) : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  disposed = true;
  text.dispose();
  done.dispose();
  isAi.dispose();
}

Future<void> _share(GlobalKey key) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return;
  final image = await boundary.toImage(pixelRatio: 3);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: 'mvp.png',
          mimeType: 'image/png',
        ),
      ],
      text: 'MVP — minimum viable person. the two-tap survival tracker',
    ),
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.stats,
    this.streaming = false,
  });

  final String report;
  final Map<String, Object> stats;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MvpTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MvpTheme.accentDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MVP — Weekly report',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: MvpTheme.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            report.isEmpty ? '…' : '$report${streaming ? '▌' : ''}',
            style: const TextStyle(
              fontSize: 18,
              height: 1.4,
              color: MvpTheme.text,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _mini('${stats['meals']}', 'meals'),
              _mini('${stats['drinks']}', 'drinks'),
              _mini('${stats['survivalEstimate']}', 'left'),
              _mini('${stats['daysAlive']}d', 'alive'),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'tracked with two taps. peak laziness.',
            style: TextStyle(fontSize: 11, color: MvpTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _mini(String v, String l) => Column(
    children: [
      Text(
        v,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w300,
          color: MvpTheme.accent,
        ),
      ),
      Text(
        l,
        style: const TextStyle(fontSize: 10, color: MvpTheme.textMuted),
      ),
    ],
  );
}
