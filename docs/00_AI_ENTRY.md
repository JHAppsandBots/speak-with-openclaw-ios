# 00 · AI ENTRY — Speak with Claw (onboarding for a new LLM instance)

> **Are you an LLM about to work on "Speak with Claw"? Read THIS file first.**
> It introduces you in ~5 minutes and points, in order, to every other source and file.
> Status: **2026-05-31 · v1.1.0**. This is the **public** repo (no credentials, no real IPs).
> New in v1.1.0: playback controls, chat export (MD/TXT), copyable bubbles, cue tone, German default,
> foreground/headphone reliability, MP3 TTS, optional local "Terminal" target (no Claude API). See `CHANGELOG.md`.

---

## 1 · What is it? (30 seconds)

A native **iOS SwiftUI app** (iOS 17+, Swift 5.10, **no third-party dependencies** — Apple frameworks
only). Purpose: **talk hands-free to your own Telegram AI bots**, "like Hey Siri". You speak, the bot
replies by voice. No typing, no button needed (in VAD mode).

Three listen modes: `off` (push-to-talk button) · `hotword` ("hey bot", on-device) · **`vad`**
(default, continuous listening with automatic speech detection).

---

## 2 · Architecture & data flow

```
 iPhone app  ──HTTP──▶  Voice relay (your Mac)  ──Telethon(as user)──▶  Telegram bot
 (SwiftUI)   ◀──────    :18800 Flask/Python                                 │
     ▲                       │  Google STT (audio→text)                     ▼
     │                       │                                     OpenClaw gateway :18789
     └───── audio/text ◀──────┘ ◀────────────  LLM reply  ◀──────  (your configured model)
```

**Why a relay?** A Telegram bot cannot receive its own messages. The relay sends to the bot as a
**user account** (Telethon) and reads the reply — and keeps bot tokens/secrets out of the app.
Full backend walkthrough: `docs/SETUP.md` and `docs/REPRODUCE_FROM_ZERO.md`.

---

## 3 · File map (iOS app — `Sources/` is the only source)

> XcodeGen generates `BotVoice.xcodeproj` from `project.yml` and builds **only `Sources/`**.
> Always edit files under `Sources/`.

| File | Role |
|---|---|
| `Sources/BotVoiceApp.swift` | `@main`; one-time AudioSession/KeepAlive init; routes Onboarding ↔ MainView |
| `Sources/MainView.swift` | **Main screen** + `MainViewModel` (all flow logic); status, mic button, build stamp, haptics |
| `Sources/VADService.swift` | **VAD** (conversation mode): continuous engine, pre-roll 1.2 s, onset 0.12 s, 2 s calibration |
| `Sources/HotwordService.swift` | On-device hotword (SFSpeechRecognizer) + watchdog |
| `Sources/SilenceDetector.swift` | Silence/pause detection (energy threshold) for end-of-utterance |
| `Sources/AudioSessionManager.swift` | **Single source of truth** for AVAudioSession (configured once) |
| `Sources/AudioService.swift` | Recording (M4A) + playback (OGG bot reply) |
| `Sources/RelayService.swift` | HTTP client to relay: `POST /voice`, `POST /text`, `GET /health` |
| `Sources/Haptics.swift` | **(new in 1.0.2)** subtle feedback: record start, send, detected, reply arrived |
| `Sources/Models.swift` | `Bot`, `Message`, `ChatHistory` (UserDefaults persistence) |
| `Sources/ConversationView.swift` | Per-bot chat history |
| `Sources/OnboardingView.swift` | First run (permissions, concept) |
| `Sources/BotSelectView.swift` | Bot selection |
| `Sources/VoIPService.swift` | CallKit/VoIP background mode (audio while screen locked) |
| `Sources/BackgroundKeepAlive.swift` | Background task to avoid suspension during audio |
| `Sources/TelegramService.swift` | Legacy (superseded by RelayService) |
| `project.yml` | XcodeGen source: target, bundle-ID, team, iOS target, `sources: [Sources]` |
| `Sources/Info.plist` | Display name "Speak with Claw", permissions, background modes (audio, voip) |

---

## 4 · Backend map (runs on your Mac — not in this repo)

| Component | Role |
|---|---|
| Voice relay (Python/Flask + Telethon) | Port **18800**. Endpoints: `/health` (open) · **`/talk`** (NEW: STT → `openclaw agent` directly via the gateway → Google TTS, ~5–12 s, Telegram fallback) · `/voice` `/text` (classic, Telegram) · `/bots` `/restart-*`. **Auth:** Bearer `RELAY_AUTH_TOKEN` (all but `/health` → 401 without). |
| App switch | Settings → **Connection**: "Direct via gateway" (=/talk) ⇄ "Via Telegram" (=/voice) + relay-token field. `@AppStorage` `useGateway`/`relayToken`. |
| Main-screen slider | **Heavy/Normal** (`@AppStorage("heavyMode")`, orange=on / silver=off): on = max depth (relay sends `mode=heavy` → marker + `--thinking high`). off = adaptive/fast. |
| OpenClaw gateway (Node) | Port **18789**. Model + `thinkingDefault` config; routes to your LLM. |
| LaunchAgents | Keep gateway + relay alive across reboots. |

Set up the backend from scratch with **`docs/REPRODUCE_FROM_ZERO.md`** (part B) and **`docs/SETUP.md`**.
Configure your own Telegram bot via **@BotFather**; enter the server URL (`http://<your-Mac-IP>:18800`,
or your Tailscale IP) in the app's Settings.

---

## 5 · Doc map (which document for what — in this order)

1. **`docs/00_AI_ENTRY.md`** ← *you are here* — the hub/onboarding.
2. `START_HERE.md` — 30-second human entry point.
3. `architecture.md` — the **WHY** decisions (native, relay, single AudioSession, XcodeGen).
4. `docs/REPRODUCE_FROM_ZERO.md` — full **from-scratch reproduction** (app + backend).
5. `docs/SETUP.md` — end-to-end setup (bot, OpenClaw, relay, Tailscale).
6. `docs/LATENCY.md` — **performance/latency** (root cause = host load) + fixes.
7. `CHANGELOG.md` — versions (currently **1.0.2**).
8. `docs/01_PROJECT_STATUS.md` — current build/release status.
9. `XCODE_SETUP.md` · `CONTRIBUTING.md` · `PRIVACY_POLICY.md` · `fastlane/README.md`.

---

## 6 · Build, test, ship

> 🔴 **Golden rule: never build in-place inside an iCloud-synced folder.** It triggers file-provider
> thrash and codesign "resource fork / Finder information" failures. Build from a local copy (`/tmp`).

- **Tools:** macOS 14+, Xcode 15+, `brew install xcodegen`, `fastlane`.
- **Generate + run:** `xcodegen generate` → open `BotVoice.xcodeproj` → set your Development Team → run **on a real device** (VoIP background mode needs hardware, not the simulator).
- **Simulator smoke test:** build with `-sdk iphonesimulator … CODE_SIGNING_ALLOWED=NO`, then `simctl install/launch`.
- **Release:** `fastlane release` (build + upload to App Store Connect; no auto-submit). See `fastlane/README.md`.
- Bundle-ID `de.johanneshahn.speakwithopenclaw`; signing **Automatic**. The **build stamp** on screen 1 shows date/version.

---

## 7 · Latest optimizations (v1.0.2 · 2026-05-31)

- **VAD captures the start of speech:** pre-roll 0.6→1.2 s, onset 0.30→0.12 s (no clipped beginning).
- **Haptics** (`Haptics.swift`) at 4 key moments → more responsive, premium feel.
- **Visuals:** flat black → subtle dark gradient.
- **Relay fix:** `/text` used to wait 90 s for a voice reply that never comes → capped to **8 s** (`/text`) / **30 s** (`/voice`); `/text` now returns reliably.
- **LLM:** `thinkingDefault` medium→**off** for lower latency (reversible).
- **Backend latency:** updating the OpenClaw gateway (here 2026.5.22 → 2026.5.28) cut voice round-trip **~4×** (≈65 s → 15–22 s), rich agent intact. Root cause was the agent/transport path, **not** host load. See `docs/LATENCY.md`.
- Both repos compile; private build installed + simulator-tested (no crash).

---

## 8 · Golden rules

1. **This public repo must NEVER contain** real IPs/tokens/API keys — placeholders only (`192.168.0.X`, `YOUR-BOT-TOKEN`). grep before every change.
2. **Build from `/tmp`**, never in iCloud (see §6).
2a. **Security:** relay endpoints are Bearer-token protected (`RELAY_AUTH_TOKEN`, must match the app's token); only `/health` is open. `/talk` runs the agent via a `subprocess` list (no shell → no command/prompt injection). Token is rotatable (change in `.env.voice-relay` AND the app).
3. **Latency was the OpenClaw agent/transport path (v2026.5.22), fixed ~4× by updating to 2026.5.28** (NOT host load — that was a measurement artefact). The rich agent stays intact. See `docs/LATENCY.md` before "optimizing" the app/config.
4. Keep it simple — no third-party dependencies (Apple frameworks only).

---

## 9 · First steps for you (LLM)

1. This file → then `architecture.md` (WHY) + `docs/LATENCY.md` (performance reality).
2. Code entry: `Sources/MainView.swift` (`MainViewModel` = the flow) → `VADService.swift` → `RelayService.swift`.
3. Full system: `docs/REPRODUCE_FROM_ZERO.md`.
