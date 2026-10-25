# MVP — Minimum Viable Person

*knows how long you'll survive.*

Built for [Hacktoberfest 2026 — Week 3: Slow and Steady](https://dev.to/challenges/hacktoberfest-week3-2026-10-19).

<img alt="mvp — minimum viable person" src="assets/brand/hero.png?v=2" />

Two buttons. That's the whole app.

- Tap **ATE** when you eat, tap **DRANK** when you drink
- The app tells you how long you'd survive if you stopped caring entirely
- Powered by the pop-science "rule of threes" (≈3 days without water,
  ≈3 weeks without food)
- Backed by a **local, on-device, open-weights AI model** — no cloud,
  no account, no effort

> Built for **Hacktoberfest — DEV Open-Source AI Challenge, Week 3:
> "slow and steady."** Nothing is slower or steadier than a person who
> barely moves.

## The joke, taken seriously

Every health app assumes you want to try. This one assumes you don't —
and that's the whole product.

- Two tanks: `food` and `water`, measured in **survival hours**
- Tanks decay in real time — watch the countdown tick every second
- A glass of water buys ~6h. A normal meal buys ~8h. Eat at your own pace.
- Skip logging for a whole day? **Gap-fill** assumes you self-maintained.
  The app forgives lazy people.
- When a tank runs low it turns red, the buttons pulse, and the AI
  roommate starts worrying (sarcastically)

## The AI is load-bearing, not decoration

The app **does not open** without a working model. The gate verifies the
model by actually loading it and generating tokens — a corrupt file can't
fake its way in.

| what the model does | why it's real AI |
|---|---|
| writes every persona line, streamed token-by-token | watch it type — signed `— Gemma, on-device` |
| writes the weekly report | a shareable card that generates live in front of you |
| gates the entire app | remove it and you have a spreadsheet that won't open |

Model: **Gemma 3n E2B-it LiteRT Preview** (~3 GB int4, MediaPipe/LiteRT,
GPU/OpenCL). After the one-time download it's 100% offline — flip on
airplane mode and everything still works. Nothing you log ever leaves
the phone.

## Lazy engineering details

- **Deterministic guardrails** — the survival math is pure Dart and
  test-covered; the model's output is parsed, clamped (50–3000 kcal),
  word-capped, and validated before it touches state
- **Serialized inference** — MediaPipe can't run concurrent sessions;
  every generation takes a turn on a mutex, and cancelled streams drain
  to completion before the session closes
- **5s debounce** — spam-tapping gets a canned clapback instantly,
  no inference wasted
- **Chunky 3D buttons** — press down like an arcade machine. Haptics
  would be nice. Maybe later. (It's in the spirit of the app to
  postpone features)
- **Notifications with quick actions** — log a meal or a glass without
  opening the app. The laziest possible UX
- **Wipe** — settings → wipe everything → tanks hit zero, you're
  starving, start over. Logically consistent. (It only knows what
  you log.)

## Stack

- Flutter + Dart
- [`flutter_gemma`](https://pub.dev/packages/flutter_gemma) →
  MediaPipe LLM Inference / LiteRT (GPU delegate)
- shared_preferences (event log + settings — tiny by design)
- flutter_local_notifications + workmanager
- Method channel for real airplane/wifi/cellular detection

## Run it

```bash
# needs a Hugging Face token with access to the gated Gemma repo
# (accept the license on the model page first — it's a Kaggle redirect)
fvm flutter run --dart-define HF_TOKEN=hf_... -d <device>
```

First launch downloads ~3 GB over Wi-Fi, then boots the model's GPU
delegate (~10–15 s on a Pixel 6 Pro — the app shows a proper "waking
the brain" sequence while it does).

Already have the `.task` file? The gate screen has a sideload option —
skip HF auth entirely.

## Disclaimer

This app will **always** tell you to eat and drink. It is a joke built
on the "rule of threes", not medicine. Drink some water.

---

<p align="center">Built with ❤️ by Musaddiq625</p>
