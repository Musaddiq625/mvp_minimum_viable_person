# MVP — Minimum Viable Person, the two-tap survival tracker

**Concept:** a joke app for lazy people that estimates how long you can survive without
food/water. Input is literally two buttons — `ATE` / `DRANK` — plus notification
quick-actions and a widget so you can log without ever opening the app. All the
"long thinking" (portion guessing, commentary, weekly report) is done behind the
scenes by an on-device open-weight model (Gemma 3n via `flutter_gemma`).

**Challenge:** Hacktoberfest Open-Source AI Challenge: Week 3 — "Slow and Steady"
(sloth theme: build something that rewards laziness). Tag `#hf26challenge`.
Natural prize track: **Best Use of Gemma** (featured, $200).

**Target device:** Pixel 6 Pro (Tensor G1, 12 GB) — Android first, iOS where free.

---

## 0. Design principles

| Principle | Consequence |
|---|---|
| **Minimum input** | Two buttons total. No free text, no forms on the main screen. Everything configurable is one-time setup, one screen deep. |
| **Minimum reading** | One number, one bar, ≤6-word status line. Details hidden behind long-press ("nerd view"). |
| **AI is invisible** | The user never "talks to AI." The model estimates, comments, and writes the shareable report silently. App fully works if the model is absent. |
| **Nudge, never shame** | Copy always pushes *toward* eating/drinking ("drink something. or don't. but do."). Never gamifies deprivation — badges reward *logging*, not fasting streaks. |
| **Estimates, not vitals** | Everything is a pop-science estimate ("rule of threes" inspired). Disclaimer in onboarding + settings. This is a toy, not a doctor. |

---

## 1. The core model — two reserve tanks

Not "time since last meal" — **two tanks**, because people skip meals and live
for months: the tank refills, the clock doesn't reset.

| Tank | Capacity | Drain | Refill |
|---|---|---|---|
| **Hydration** | 72 survival-hours (rule-of-3 days) | ~1.0 unit/h × modifiers | `DRANK` → `ml × (72 / 3000)` hours (glass 250 ml ≈ +6 h, bottle 500 ml ≈ +12 h) |
| **Energy** | 504 survival-hours (~3 weeks) | ~1.0 unit/h; × 0.8 below 25 % (metabolic slowdown — this is what makes "skips meals, survives months" emerge naturally) | `ATE` → `kcal / ~92` hours (small 400 kcal ≈ +4.3 h, normal 700 ≈ +7.6 h, large 1100 ≈ +12 h) |

- **Headline number** = `min(hydration_h, energy_h)` formatted smart (`41h`, `12d`).
- **Headline bar** = the limiting tank's fill %.
- Reserves are a **pure function of the event log + `now`** — no running timers,
  recomputed on every open/tap. App can be killed; nothing is lost.
- Numbers intentionally jitter (estimate framing), never shown as precision.

### 1.1 Time slots → portion presets

`ATE` needs a kcal value without asking. Solved by a one-time preset table:

```
How much do you eat often?

Morning    (05–11)  [ small | NORMAL | large ]   fav: ______
Afternoon  (11–16)  [ small | normal | LARGE ]   fav: ______
Evening    (16–21)  [ small | NORMAL | large ]   fav: ______
Night      (21–01)  [ small | normal | LARGE ]   fav: ______
Late night (01–05)  [ SMALL | normal | large ]   fav: ______

usual drink:  [ glass 250 ml | bottle 500 ml ]
```

- Pre-filled defaults → setup is skippable (laziest onboarding).
- `fav:` is an optional text per slot — pure joke fuel for the model
  ("biryani again? respect").
- Tap `ATE` → slot lookup by clock → kcal → refill. Double-tap within a slot =
  "seconds" (+50 %).

### 1.2 Entry points (all lead to the same two events)

| Entry | Mechanism |
|---|---|
| In-app buttons | `ATE` / `DRANK` on the single screen |
| Notification actions | Reminder notifications carry `[ATE]` `[DRANK]` action buttons → log without opening (`flutter_local_notifications` actions + background handler) |
| Home-screen widget | Same two buttons (`home_widget`) — Phase 2 |

### 1.3 Spam-tap handling

- Taps on the same button < 5 s apart are **ignored** and rotate a lazy line:
  - "logged it the first time."
  - "two taps ≠ two meals."
  - "chill. counted already."
  - "still digesting the first one."
  - "i heard you."
  - "relax, i got it."
  - "again? it's been 3 seconds."
  - "that's a double tap, not dinner."
- Absorbs accidental double-taps → no confirmation dialogs (dialogs = reading).
- Lone mis-tap = one phantom meal; acceptable at joke-app stakes, no undo in v1
  (escape hatch if ever needed: long-press button = remove last event — not shipped).

### 1.4 Tank states

| State | Hydration/Energy % | UI |
|---|---|---|
| Fine | > 50 % | normal bar + persona line |
| Low | 10–50 % | bar dims, gentle persona nudge |
| Hungry | ≤ 10 % | limiting button relabels `EAT TO SURVIVE` / `DRINK TO SURVIVE` and **pulses** — the nudge *is* the button |
| Zero | 0 % | bar empty, button stays in survive-mode; tapping refills = survive more. No death screen, no resurrection gag |

---

## 2. AI layer (invisible by design)

Model: **Gemma 3n E2B-it (int4)** via `flutter_gemma` (MediaPipe LLM Inference /
LiteRT, GPU-accelerated). ~2–3 GB, ~10–25 tok/s on Pixel-class hardware.
Fallback chain: Gemma 2 2B-it → canned line bank (always works offline-first).

| Job | Trigger | Output cap |
|---|---|---|
| **Persona one-liner** | every tap, tank-state change, daily open | ≤ 6 words, lazy-roommate voice: uninterested but slightly helpful |
| **Gap fill** | app opened after > 24 h absence | assume learned slot pattern ("assumed you ate like a normal human") |
| **Weekly survival report** | on demand from share card | ~4 lines of comedic recap: meals, peak dehydration hours, streak |
| **Rhythm learning** | background, weekly | adjusts per-slot portion priors from actual tap history |

**Persona voice** — examples:
- ATE: "ok. food. noted." / "ate again? ambitious." / "cool. you're basically thriving."
- DRANK: "water. groundbreaking." / "hydrated. look at you go." / "sip secured. carry on."
- Low: "drink something. or don't. but do." / "your tank's doing the thing. eat."
- Zero: "bar's empty. you know what to do." / "i'd say something motivating. nah — eat."
- Report: "7 days. 14 meals. zero effort. still kicking. honestly impressive."

**Model manager (settings):** Wi-Fi-only download-on-demand, progress bar,
size shown honestly (~3 GB), delete-model option, status indicator. Everything
works before/without the model — canned lines are the baseline, the model
enriches.

---

## 3. Screens (two)

### 3.1 Main — the whole app

```
┌────────────────────────┐
│                  ⚙     │
│        41h             │   headline: time until limiting tank is empty
│   ▓▓▓▓▓▓▓░░░ 62 %      │   limiting-tank bar
│                        │
│   "hydrate, hero."     │   ≤6-word persona line (model or canned)
│                        │
│   [ ATE ]  [ DRANK ]   │   entire input model
│                        │
│  how much do you eat   │   text button → preset screen
│       often?           │
└────────────────────────┘
```

- Long-press the bar → **nerd view**: both tanks, absolute numbers, event count.
  The only "details" surface, deliberately one gesture deep.
- ⚙ → settings (model manager, notifications, disclaimer, reset).

### 3.2 Portion presets — "how much do you eat often"

Per §1.1. Segmented control per slot + optional fav text + drink size +
"restore defaults". Persisted to settings; no save button (live).

---

## 4. Features by area

### 4.1 Survival engine (`lib/engine/`, pure Dart, zero dependencies)

- `SurvivalState { hydrationH, energyH, lastEvent }`
- `Event { type: ate|drank, timestampUtc, kcal?, ml?, portion }`
- `decay(state, elapsed, modifiers)` — heat/exercise/caffeine multipliers
  (context toggles in settings: "it's hot", "i moved today")
- `refill(state, event, slotPreset)`
- `limiting(state) → tank`, `headline(state) → String`
- Deterministic + unit-testable; the AI never touches the math.

### 4.2 Event log & persistence

- `drift`/sqlite table `events(type, ts_utc, kcal, ml, portion, source: app|notif|widget)`
- Settings in `shared_preferences` (portion table, drink size, model status, toggles)
- Recompute = fold events → apply decay between consecutive timestamps.

### 4.3 Notifications (`flutter_local_notifications`)

- Threshold pings at 50 / 25 / 10 / 0 % of limiting tank, persona-toned
- Daily gentle nudge if no taps by evening ("you exist. log something.")
- Quick actions `[ATE]` `[DRANK]` with background event handler
- Quiet hours (default 23–08) — sloth respects sleep

### 4.4 Widget (Phase 2, `home_widget`)

- Two-button widget; taps write to shared event store via App Group/
  SharedPreferences bridge

### 4.5 Gamification (safe by construction)

- **Days-alive counter**: `day N of being alive` — optionally seeded by birthday
  for a funny huge number; rewards existing, not fasting
- **Badges for logging**, never for deprivation: "7 days of barely trying",
  "Camel (logged 10 drinks)", "Houseplant (consistent hydrator)"
- **Share card** (weekly report): generated image + text → system share sheet;
  the AI's long writing lives here, never on the main screen

### 4.6 Safety & copy guardrails

- Onboarding one-pager: "a joke. not medical advice. drink water." + accept
- No deprivation streaks, no death imagery, zero-state always offers the fix
- Settings: disclaimer re-read, data wipe (all local anyway)

---

## 5. Tech stack

| Piece | Choice | Why |
|---|---|---|
| SDK | Flutter **3.47.7** via FVM (`.fvmrc` pinned) | latest stable |
| On-device LLM | `flutter_gemma` + Gemma 3n E2B-it int4 | purpose-built for phones; Best Use of Gemma track |
| Events store | `drift` (sqlite) | typed, reactive streams for UI |
| Settings | `shared_preferences` | primitives only |
| State | `riverpod` | engine as pure provider graph; trivially testable |
| Notifications | `flutter_local_notifications` | action buttons support |
| Widget | `home_widget` | Phase 2 |
| Share card | `screenshot`/`widgets_to_image` + `share_plus` | Phase 3 |
| Tests | `flutter_test` on engine only (per project rules — targeted, not suite) | math must be provably sane |

Estimated pubspec additions: `flutter_gemma`, `drift`, `drift_flutter`,
`riverpod`/`flutter_riverpod`, `shared_preferences`,
`flutter_local_notifications`, `home_widget`, `share_plus`, `intl`.

---

## 6. Edge cases (from design review)

- **Portion ambiguity** → slot presets + double-tap = seconds; model learns priors
- **Ambiguous intake** (soup, coffee, beer) → presets carry a per-slot
  "wetness" hint; caffeine/alcohol apply a small hydration penalty behind the scenes
- **App closed for days** → gap-fill: learned pattern assumes normal intake; no prompts
- **Timezone/clock change** → all timestamps UTC; reserves from `now − lastTs`
- **Spam/wrong taps** → 5 s debounce + lazy line bank; no undo v1
- **Zero tank** → hungry-state button (`EAT/DRINK TO SURVIVE`), never a death screen
- **Fasters/night-shift** → slot table is user-configurable; model adapts baseline
- **Model download too big / no Wi-Fi / low-end phone** → canned persona bank;
  app identical minus flavor
- **Over-reporting** → refills cap at tank capacity; diminishing returns per hour

## 7. Challenge rubric mapping

| Criterion | Our angle |
|---|---|
| Writing quality (top weight) | The joke writes itself; weekly report shows AI's long-form |
| Relevance to theme | Laziest possible health tracker — input cost ≈ 0 |
| Creativity | "Survival battery" framing + invisible AI persona |
| Technical execution | Real on-device LLM on a Pixel, deterministic engine, tests |
| Partner tech | **Gemma** (featured $200); possibly `.tech` landing page |
| "Why open" | Fully offline, private, $0 inference — eating data never leaves the phone |

## 8. Build phases

| Phase | Deliverable | Status |
|---|---|---|
| **0** | FVM-pinned Flutter 3.47.7 project scaffolded | ✅ |
| **1 Engine** | `lib/engine/` decay/refill/slots + unit tests proving the math | ✅ 15 tests |
| **2 Store** | event log + settings (shared_preferences JSON — simpler than drift, log is tiny) | ✅ |
| **3 UI** | single screen: headline, bar, persona line, 2 buttons, presets screen, nerd view, onboarding | ✅ |
| **4 Persona** | canned line bank wired in (model-free baseline) | ✅ |
| **5 Gemma** | `flutter_gemma` 0.13.6 service, model manager, download flow, generated lines | ✅ code; needs HF token + device to run |
| **6 Notifications** | thresholds + daily nudge + ATE/DRANK quick actions (background isolate writes events) | ✅ |
| **7 Polish** | nerd view, badges, share card + weekly report, **interactive widget** (background taps) | ✅ |
| **8 Ship** | demo gif + DEV post (`#hf26challenge`, Gemma category) | ⏳ |

## 9. Open questions

- Keep slot boundaries fixed (simpler) or user-editable (more correct for
  night-shift sloths)? — leaning fixed v1
- Fav-food field: free text per slot, or one comma-list for the whole day?
- iOS widget parity — Android first, iOS if trivial
- App icon: sleeping sloth on a battery? (generate later)
