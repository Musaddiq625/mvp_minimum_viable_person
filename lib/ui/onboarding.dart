import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';

/// One-shot disclaimer. Shown once, then never again.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Text('MVP',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w200)),
              const Text('minimum viable person',
                  style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 2,
                      color: MvpTheme.accent)),
              const SizedBox(height: 16),
              const Text(
                'two buttons. that\'s the whole app.\n\n'
                'tap ATE when you eat. tap DRANK when you drink. '
                'we estimate how long you\'d survive if you stopped — '
                'a joke powered by the "rule of threes", not medicine.\n\n'
                'this app will always tell you to eat and drink.\n'
                'it is not medical advice. drink some water.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: MvpTheme.accent,
                  foregroundColor: MvpTheme.bg,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                onPressed: () {
                  app.setOnboarded();
                  Navigator.of(context).pop();
                },
                child: const Text('got it. let me be lazy.',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
