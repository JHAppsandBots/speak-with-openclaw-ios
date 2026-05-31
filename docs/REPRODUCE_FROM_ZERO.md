# Speak with Claw — Reproduce From Zero (app + backend)

**Updated: 2026-05-31 · v1.1.0.** Build the *entire* system from scratch: the iOS app **and** the Mac
backend (voice relay + OpenClaw bots), including the pitfalls worth avoiding. New here? Start with
**[00_AI_ENTRY.md](00_AI_ENTRY.md)**.

> Since v1.1.0: relay TTS uses **MP3** (reliable iOS playback); the app has playback controls + chat
> export; recognition/app language default to German; optional, fully isolated **"Terminal" target**
> (local file mailbox, **no Claude API**, default off). See `CHANGELOG.md`.

> This is the public repo — all hosts/bots below are **placeholders**. Use your own values.

---

## 0. Architecture in one sentence

The iPhone app (SwiftUI) records speech → sends audio to a **voice relay** on your Mac (port 18800) →
the relay forwards it via Telethon (as your own Telegram account) to your chosen **OpenClaw bot** →
the bot (LLM) replies on Telegram → the relay catches the reply and returns text + voice to the app.

```
[iPhone app] --HTTP--> [voice-relay :18800] --Telethon/Telegram--> [OpenClaw bot @ gateway :18789] --LLM--> back
```

---

## PART A — iOS app from zero

### A1. Prerequisites (Mac)
- macOS + **Xcode 16+** (tested with 26.x)
- **XcodeGen** (`brew install xcodegen`) — the `.xcodeproj` is generated; `project.yml` is the source of truth
- **fastlane** (`brew install fastlane`) — for App Store upload
- An Apple Developer account / Team (set yours in `project.yml`)
- App Store Connect API key at `~/.appstoreconnect/private_keys/AuthKey_*.p8` (for fastlane)

### A2. Build & run on iPhone
```bash
cd SpeakWithOpenClaw-Public
xcodegen generate            # generates BotVoice.xcodeproj from project.yml
open BotVoice.xcodeproj        # pick your iPhone → ▶ Run   (or Product ▸ Archive)
```
- Bundle-ID: **`de.johanneshahn.speakwithopenclaw`** · target/scheme: **BotVoice** · app name: "Speak with Claw"
- Signing: **Automatic** (set your own Development Team). On first device run:
  *Settings → General → VPN & Device Management → trust the developer*.

### A3. ⚠️ Pitfalls (do not reintroduce)
1. **Bundle-ID** must match your App Store Connect record (here `de.johanneshahn.speakwithopenclaw`).
2. **Edit only `Sources/`** — `project.yml` builds `sources: [Sources]` only. Files placed in the repo
   root are ignored by the build (this once caused "latest edits vanished").
3. **Never build inside an iCloud-synced folder.** iCloud stamps `xattr`/FinderInfo on the `.app` →
   `codesign` fails with "resource fork, Finder information, or similar detritus not allowed".
   **Fix — build from a local `/tmp` copy** (no team override; automatic signing):
   ```bash
   rsync -a --exclude '.git' --exclude '*.xcodeproj' --exclude 'build' ./ /tmp/swc-build/
   cd /tmp/swc-build && xcodegen generate
   xcodebuild -project BotVoice.xcodeproj -scheme BotVoice -configuration Debug \
     -destination 'id=<DEVICE_UDID>' -derivedDataPath /tmp/swc-dd -allowProvisioningUpdates clean build
   xcrun devicectl device install app --device <DEVICE_UDID> \
     /tmp/swc-dd/Build/Products/Debug-iphoneos/BotVoice.app
   ```
   (Device UDID via `xcrun xctrace list devices`. Do **not** override `DEVELOPMENT_TEAM` → "No Account for Team".)
4. **Build stamp:** `MainView.swift` shows "Build DD.MM.YYYY, HH:MM · vX (Y)" on screen 1 → you instantly
   see which build is running.
5. **No secrets in the repo:** `build/`, `.env`, `secrets.swift`, `xcuserdata/` are gitignored.
   Server URL / bot selection are entered **in the app** (Settings), never in code.

### A4. App Store release
```bash
fastlane release        # xcodegen generate → gym (build) → deliver (upload, NO auto-submit)
```

### A5. Source layout (`Sources/`)
See **[00_AI_ENTRY.md](00_AI_ENTRY.md) §3** for the full file map. Heart of the flow:
`MainView.swift` (`MainViewModel`) → `VADService.swift` → `RelayService.swift`; audio via
`AudioSessionManager.swift` (single source of truth) + `AudioService.swift`.

---

## PART B — Mac backend (voice relay + OpenClaw bots) from zero

### B1. Prerequisites
- **Node ≥ 22.19** (for the OpenClaw gateway)
- **OpenClaw** (`npm i -g openclaw`) → gateway on port **18789**
- **Python 3.11** with Flask + Telethon (for the relay) + **ffmpeg** (audio → OGG Opus)
- **Telegram:** one bot token per bot from @BotFather; one user-account login for Telethon (the relay
  sends as *you*, because a bot cannot read its own messages)
- **Google Cloud API key** (STT/TTS) → env `GOOGLE_API_KEY`
- **Tailscale** (recommended) for access away from home

### B2. Voice relay
- A Flask server on **:18800** with a Telethon user session. Endpoints:
  `GET /health` (no auth) · **`POST /talk`** (v1.0.3: STT → `openclaw agent` directly via the gateway →
  Google TTS; gateway retry + Telegram fallback; ~8–12 s) · `POST /voice` · `POST /text` (classic) ·
  `GET /bots` · `POST /restart-bots` · `POST /restart-relay`.
- **Security:** all endpoints except `/health` require `Authorization: Bearer $RELAY_AUTH_TOKEN`
  (set in the relay `.env` and in the app's Settings → Connection). `/talk` runs the agent via a
  `subprocess` list (no shell). Paths overridable via `OPENCLAW_NODE_BIN` / `OPENCLAW_DIST`.
- **Bot map:** maps each bot's Telegram **@username** to its id — fill in **your own** bots
  (e.g. `@yourbot1`, `@yourbot2`). The app's `/bots` call lists them for selection.
- STT via Google Speech `:recognize` (`GOOGLE_API_KEY`).
- Keep secrets in a `.env` loaded by a wrapper script; run it via a LaunchAgent (KeepAlive).
  Restart: `launchctl kickstart -k gui/$(id -u)/<relay-launchagent-label>`.
- **Reply-wait timeouts (v1.0.2):** after the text reply settles, the relay waits only a short grace
  for an optional voice reply — **`/text` = 8 s**, **`/voice` = 30 s** (previously 90 s, which turned
  text-only replies into multi-minute timeouts).

### B3. OpenClaw gateway + bots
- Config: `~/.openclaw/openclaw.json` — your Telegram bot accounts (tokens via env refs), `agents`
  defaults (`model.primary`, e.g. a fast model), and `auth.profiles`.
- **`thinkingDefault: "off"`** for snappy voice replies (reversible; applies to all bots).
- Gateway runs via a LaunchAgent. **Restart (heals flapping bots + latency):**
  `launchctl kickstart -k gui/$(id -u)/<gateway-launchagent-label>`.

### B4. ⚠️ Backend pitfalls
- **Relay 500 "NameError: abort"** → ensure `abort` is imported from `flask`.
- **Bots flap** ("health-monitor: restarting reason stopped") → tokens are usually fine; a **clean
  gateway restart** fixes it (the per-provider health monitor alone may not).
- **High latency** → see **[LATENCY.md](LATENCY.md)**. Root cause is almost always **host machine load**
  (iCloud/Spotlight/Dropbox starving the gateway event loop), not the app. `thinkingDefault: off`
  removes LLM overhead; a dead/secondary provider in the failover chain can also surface "provider errors".

---

## PART C — Full setup checklist
1. Mac: Node ≥ 22.19, OpenClaw, Python+Flask+Telethon, ffmpeg, Tailscale, Google API key.
2. Fill your `.env` files with tokens/keys.
3. Start the gateway → `/health` (18789) green; start your bots.
4. Log in the Telethon user session once (interactive).
5. Start the relay → `curl localhost:18800/health` → 200; `/bots` lists your bots.
6. App: `xcodegen generate` → build → iPhone; in Settings set server URL
   (`http://<your-Mac-or-Tailscale-IP>:18800`) + pick a bot.
7. Speak.

---

## What was optimized last (v1.0.2 · 2026-05-31)
| Area | Change |
|---|---|
| VAD | pre-roll 0.6→1.2 s, onset 0.30→0.12 s — captures the start of speech |
| App | haptics (`Haptics.swift`); subtle dark gradient; onboarding name "Speak with Claw" |
| Relay | audio-wait 90 s → **8 s** (`/text`) / **30 s** (`/voice`) — `/text` returns reliably |
| LLM | `thinkingDefault` medium → **off** (lower latency; reversible) |
| Diagnosis | latency root cause = host load → **[LATENCY.md](LATENCY.md)** |

*Source of the pitfalls: debug/optimization sessions 30–31 May 2026 — see also START_HERE.md, architecture.md, CHANGELOG.md.*
