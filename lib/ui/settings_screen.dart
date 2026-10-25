import 'package:flutter/material.dart';

import '../ai/gemma_service.dart';
import '../app_state.dart';
import 'theme.dart';

/// Settings: model manager, context toggles, notifications, disclaimer, wipe.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.app, this.gemma});

  final AppState app;
  final GemmaService? gemma;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _Header('the lazy brain'),
            _ModelManager(app: app, gemma: gemma),
            const SizedBox(height: 24),
            const _Header('today\'s context'),
            SwitchListTile(
              title: const Text("It's hot"),
              subtitle:
                  const Text('water drains 1.5× faster'),
              value: app.itsHot,
              onChanged: app.setHot,
            ),
            SwitchListTile(
              title: const Text('I moved today'),
              subtitle: const Text(
                  'exercise counts too. resets daily. water drains 1.3× faster'),
              value: app.movedToday,
              onChanged: app.setMovedToday,
            ),
            const SizedBox(height: 24),
            const _Header('behavior'),
            SwitchListTile(
              title: const Text('Assume I survived while away'),
              subtitle: const Text(
                  "gaps ≥24h don't drain you — we assume you ate like a normal human"),
              value: app.gapFillEnabled,
              onChanged: app.setGapFill,
            ),
            SwitchListTile(
              title: const Text('Nudge me'),
              subtitle: const Text(
                  'notifications when tanks run low. quiet 23–08.'),
              value: app.notificationsEnabled,
              onChanged: app.setNotificationsEnabled,
            ),
            const SizedBox(height: 24),
            const _Header('the fine print'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'this is a joke app. estimates are pop-science (the "rule of '
                'threes"), not medical advice. it will always tell you to eat '
                'and drink. your data never leaves this phone — the AI runs '
                'on-device, offline, free.',
                style:
                    TextStyle(color: MvpTheme.textMuted, fontSize: 13),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: () => _confirmWipe(context),
                child: const Text('🗑️ Wipe everything',
                    style: TextStyle(color: MvpTheme.warn)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmWipe(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MvpTheme.surface,
        title: const Text('Wipe all data?'),
        content: const Text(
            'deletes your event log. your survival clock restarts. sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('nah')),
          TextButton(
            onPressed: () async {
              await app.wipe();
              if (ctx.mounted) Navigator.pop(ctx); // close the dialog
              if (context.mounted) {
                Navigator.pop(context); // back to home — bars are full
              }
            },
            child:
                const Text('Wipe it', style: TextStyle(color: MvpTheme.warn)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                color: MvpTheme.accent)),
      );
}

/// Model manager tile — download status, size honesty, actions.
/// The model is required (the app gates on it); this tile shows its health.
class _ModelManager extends StatelessWidget {
  const _ModelManager({required this.app, required this.gemma});

  final AppState app;
  final GemmaService? gemma;

  @override
  Widget build(BuildContext context) {
    final g = gemma;
    if (g == null) {
      return const ListTile(
        title: Text('on-device AI'),
        subtitle: Text('using built-in lazy wisdom'),
        trailing: Icon(Icons.check_circle_outline,
            color: MvpTheme.textMuted),
      );
    }
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) {
        final (title, subtitle, action) = switch (g.status) {
          GemmaStatus.checking => (
              'Checking the brain…',
              'verifying the model on-device',
              null,
            ),
          GemmaStatus.ready => (
              'Gemma 3n E2B-it LiteRT Preview · on-device',
              'local model active. offline, private, free.',
              null,
            ),
          GemmaStatus.downloading => (
              'Downloading Gemma…',
              '${(g.progress * 100).toStringAsFixed(0)}% — keep the app open',
              null,
            ),
          GemmaStatus.failed => (
              'Download failed',
              g.error ?? 'tap to retry.',
              () => g.download(),
            ),
          GemmaStatus.notDownloaded => (
              'Get the local brain (~3 GB)',
              'required — the whole app runs on it. wi-fi recommended.',
              () => g.download(),
            ),
        };
        return ListTile(
          title: Text(title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              if (g.status == GemmaStatus.downloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                    value: g.progress,
                    color: MvpTheme.accent,
                    backgroundColor: MvpTheme.surface),
              ],
            ],
          ),
          trailing: action == null
              ? (g.status == GemmaStatus.ready
                  ? const Icon(Icons.check_circle, color: MvpTheme.accent)
                  : null)
              : IconButton(
                  icon: const Icon(Icons.download_outlined,
                      color: MvpTheme.accent),
                  onPressed: action,
                ),
        );
      },
    );
  }
}
