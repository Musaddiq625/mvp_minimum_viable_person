/// Canned persona lines — the baseline voice of the app.
///
/// Voice: a lazy roommate who can't be bothered but doesn't want you dead.
/// Max ~6 words in-app. The on-device model replaces these when downloaded;
/// this bank is the always-works fallback and the tone reference.
enum PersonaContext {
  ate,
  drank,
  lowHydration,
  lowEnergy,
  zeroHydration,
  zeroEnergy,
  spam,
  daily,
}

class PersonaBank {
  PersonaBank([int? seed]) : _counter = seed ?? 0;

  int _counter;

  static const Map<PersonaContext, List<String>> _lines = {
    PersonaContext.ate: [
      "ok. food. noted.",
      "ate again? ambitious.",
      "cool. you're basically thriving.",
      "logged. go rest now.",
      "mm. sustenance.",
    ],
    PersonaContext.drank: [
      "water. groundbreaking.",
      "hydrated. look at you go.",
      "sip secured. carry on.",
      "ah yes, the wet one.",
      "nice. your cells sent regards.",
    ],
    PersonaContext.lowHydration: [
      "drink something. or don't. but do.",
      "you're drying out. mildly concerned.",
      "water exists. just saying.",
      "your tank's doing the thing. drink.",
    ],
    PersonaContext.lowEnergy: [
      "food soon-ish. trust me.",
      "running on fumes and vibes.",
      "eat something. i'll wait.",
      "tank's low. fridge is right there.",
    ],
    PersonaContext.zeroHydration: [
      "bar's empty. you know what to do.",
      "i'd say something motivating. nah — drink.",
      "desert mode: achieved. hydrate.",
    ],
    PersonaContext.zeroEnergy: [
      "empty tank. fridge. now-ish.",
      "you're a skeleton with wifi. eat.",
      "i'd say something motivating. nah — eat.",
    ],
    PersonaContext.spam: [
      "logged it the first time.",
      "two taps ≠ two meals.",
      "chill. counted already.",
      "still digesting the first one.",
      "i heard you.",
      "relax, i got it.",
      "again? it's been 3 seconds.",
      "that's a double tap, not dinner.",
    ],
    PersonaContext.daily: [
      "still here. good enough.",
      "another day, survived-ish.",
      "status: horizontal. ideal.",
      "you exist. that's the whole job.",
    ],
  };

  /// Rotating pick — no repeats until the bank wraps.
  String pick(PersonaContext ctx) {
    final bank = _lines[ctx]!;
    final line = bank[_counter % bank.length];
    _counter++;
    return line;
  }

  /// Deterministic pick for a given index (e.g., spam-tap escalation).
  String at(PersonaContext ctx, int index) {
    final bank = _lines[ctx]!;
    return bank[index % bank.length];
  }

  int spamCount(PersonaContext ctx) => _lines[ctx]!.length;
}
