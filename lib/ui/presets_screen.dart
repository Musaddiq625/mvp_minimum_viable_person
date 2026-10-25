import 'package:flutter/material.dart';

import '../app_state.dart';
import '../engine/models.dart';
import '../engine/presets.dart';
import 'theme.dart';

/// "How much do you eat often" — one-time portion setup, one screen deep.
/// Live-saves; no save button.
class PresetsScreen extends StatefulWidget {
  const PresetsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<PresetsScreen> createState() => _PresetsScreenState();
}

class _PresetsScreenState extends State<PresetsScreen> {
  late PortionPresets _p;

  @override
  void initState() {
    super.initState();
    _p = widget.app.presets.copy();
  }

  void _save() => widget.app.savePresets(_p);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('How much do you eat often?'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _p = PortionPresets();
                _save();
              });
            },
            child: const Text('Defaults',
                style: TextStyle(color: MvpTheme.textMuted)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          for (final slot in MealSlot.values) ...[
            _SlotRow(
              slot: slot,
              portion: _p.portionFor(slot),
              onPortion: (v) => setState(() {
                _p.portions[slot] = v;
                _save();
              }),
            ),
            const SizedBox(height: 14),
          ],
          const Divider(color: MvpTheme.surface, height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Usual drink',
                  style: TextStyle(color: MvpTheme.textMuted)),
              SegmentedButton<DrinkSize>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: DrinkSize.glass, label: Text('Glass')),
                  ButtonSegment(
                      value: DrinkSize.bottle, label: Text('Bottle')),
                ],
                selected: {_p.drinkSize},
                onSelectionChanged: (s) => setState(() {
                  _p.drinkSize = s.first;
                  _save();
                }),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'set once, forget forever. we do the math.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MvpTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.portion,
    required this.onPortion,
  });

  final MealSlot slot;
  final Portion portion;
  final ValueChanged<Portion> onPortion;

  String get _range => switch (slot) {
        MealSlot.morning => '5am–11am',
        MealSlot.afternoon => '11am–4pm',
        MealSlot.evening => '4pm–9pm',
        MealSlot.night => '9pm–1am',
        MealSlot.lateNight => '1am–5am',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(slot.label,
                style:
                    const TextStyle(fontSize: 16, color: MvpTheme.text)),
            Text(_range,
                style: const TextStyle(
                    fontSize: 12, color: MvpTheme.textMuted)),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<Portion>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: Portion.small, label: Text('Small')),
            ButtonSegment(
                value: Portion.normal, label: Text('Normal')),
            ButtonSegment(
                value: Portion.large, label: Text('Large')),
          ],
          selected: {portion},
          onSelectionChanged: (s) => onPortion(s.first),
        ),
      ],
    );
  }
}
