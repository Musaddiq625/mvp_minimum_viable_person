// Widget-level tests live in engine_test.dart for now — app boot needs
// platform channels (shared_preferences, notifications), so a pure widget
// smoke test would need fakes. Engine math is the part that must be provably
// sane anyway.
import 'package:flutter_test/flutter_test.dart';
import 'package:mvp_minimum_viable_person/engine/persona_bank.dart';

void main() {
  test('persona bank rotates through lines without repeating early', () {
    final bank = PersonaBank();
    final lines = {
      for (var i = 0; i < 5; i++) bank.pick(PersonaContext.spam),
    };
    expect(lines.length, 5); // 5 distinct spam lines in a row
  });
}
