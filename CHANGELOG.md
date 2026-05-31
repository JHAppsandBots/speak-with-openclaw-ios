# Changelog

All notable changes to this project will be documented here.

## [1.1.0] — 2026-05-31

### Added
- **Playback controls** for the bot's voice reply: pause / resume / stop (auto-play stays).
  Robust playback watchdog so a stuck playback can never freeze the app.
- **Chat export**: share the whole conversation as **Markdown (.md)** or **plain text (.txt)** →
  save to Files (discreet share menu in the history view; file is written only on share).
- **Selectable & copyable bubbles**: text selection + long-press “Copy”.
- **Cue sound before the reply** (Settings toggle, off by default): a short tone right before the
  bot's voice starts — no added latency when off.
- **Target toggle on the main screen: 🦞 OpenClaw ⇄ 💻 Terminal** (off by default). Optional, fully
  isolated voice bridge to a running interactive Claude Code terminal session (persona or neutral).
  Uses **no Claude API** — local file mailbox only; completely removable.

### Changed
- **Recognition + app language now default to German.**
- **TTS is now MP3** instead of OGG/Opus → reliable playback on iOS (AVAudioPlayer plays MP3 natively).
- **Deep ("heavy") mode timeout raised to 240 s** so long deep replies complete instead of timing out.

### Fixed
- **Duplicated replies finally fixed** (incl. short ones): collapse via true string-period detection.
- **Internal backend error strings are no longer spoken aloud** (e.g. “Request timed out …”).
- **Reliable continuous operation / foreground**: audio session is re-activated on `scenePhase`
  return and the listen mode restarts — fixes “had to restart the app too often”.
- **Headphones** (Bluetooth/AirPods/wired): robust route re-evaluation on foreground & after interruptions.
- Hardened: VAD empty-buffer crash, health check now verifies HTTP 200, history playback stops cleanly,
  bot-switch race, temp audio cleaned up on launch.

### Removed (cleanup / KISS)
- Dead code removed (unused service + sound players), deprecation warning fixed, permission strings corrected.

## [1.0.4] — 2026-05-31

### Added
- **Heavy/Normal mode slider on the main screen** (Apple-style switch, round white knob; oval track
  **silver when off, orange when on** — no red/green):
  - **Normal** (default, fast): the agent applies depth adaptively / context-aware per request.
  - **Heavy** (max brain power): forces full depth for every request (`--thinking high` + the agent's
    deep reasoning stack). Applies to the direct (`/talk`) and Telegram-text paths via a `mode` field.

### Fixed
- **Gateway-mode "server error"** for bots without a gateway agent: `/talk` returned a hard HTTP 400.
  Now it **falls back transparently to the Telegram path** → you always get a reply. Bot lookup is
  case-insensitive.
- **Cleaner error messages:** localized, user-friendly errors (e.g. "wrong relay token", "no reply from bot")
  instead of raw server text; centralized `decodeReply` helper in RelayService.
- **Reply appeared 2–3× in a row** (direct/gateway path): OpenClaw's `agent --json` concatenates multiple
  stream snapshots (`streamMode: partial`) → the full text repeated in one field. The relay now detects
  contiguous identical repeats and collapses them to a single copy (`_collapse_repeats`, unit-tested;
  normal text is left untouched).

## [1.0.3] — 2026-05-31

### Added
- **Connection toggle** (Settings → Connection): "Direct via gateway (fast)" vs. "Via Telegram (classic)" —
  switch freely; both paths tested and working.
  - **Direct path** (new relay endpoint `/talk`): STT → agent **directly via the gateway** (no Telegram)
    → Google TTS. **~5–12 s**, full rich agent (persona + memory). Per-bot voices preserved.
  - **Automatic Telegram fallback:** if a bot replies out-of-band (e.g. via its own TTS tool), `/talk`
    falls back to the classic path → you always get a reply.
- **Relay token field** + a real connection test (checks reachability AND token; detects 401).

### Security
- **Relay auth enforced** (`RELAY_AUTH_TOKEN`, Bearer): every endpoint except `/health` returns 401 without
  the token. Protects `/talk` (agent) and `/restart-*` (shell) from unauthorized access; the app sends the token.
- `/talk` invokes the agent via a `subprocess` **list** (no shell) → no command injection; only the
  token holder can reach the agent → no external prompt injection.

### Changed
- Relay paths overridable via env (`OPENCLAW_NODE_BIN`, `OPENCLAW_DIST`) → migration-friendly.

## [1.0.2] — 2026-05-31

### Added
- Subtle haptic feedback at the key moments (recording start, send, speech/hotword detected,
  reply arrived) — a more responsive, premium feel.

### Changed
- VAD conversation mode now reliably captures the start of speech: pre-roll 0.6 s → 1.2 s,
  onset confirmation 0.30 s → 0.12 s. Recording starts earlier; the beginning of what you say
  is no longer clipped (“like Hey Siri”).
- Visuals: flat black background → subtle dark gradient.

### Performance
- Backend relay: the 90 s wait for a voice reply after the text reply has been capped
  (/text 8 s, /voice 30 s) — `/text` now returns reliably and much faster (previously timed out/500).
- LLM `thinkingDefault` medium → off for lower latency (reversible).
- Latency root cause documented: host machine load (file-sync/indexing daemons) starving the
  gateway event loop. See `docs/LATENCY.md`.

## [1.0.1] — 2026-05-30

### Fixed
- **Publish-Blocker:** Bundle-ID korrigiert (`de.johanneshahn.heyopenclaw` → `de.johanneshahn.speakwithopenclaw`),
  passend zu App Store Connect & `fastlane/Appfile`.
- **Build-Zuverlässigkeit:** doppelte Quelldateien (Repo-Root vs `Sources/`) zu einer Quelle in `Sources/`
  zusammengeführt; neueste Versionen übernommen, Root-Dubletten entfernt (XcodeGen baut nur `Sources/`).

### Changed
- Anzeigename (`CFBundleDisplayName`) „Speak with OpenClaw" → „Speak with Claw".
- Dokumentation auf den Best-Practices-DOCUMENTATION_STANDARD gebracht (START_HERE.md, architecture.md, docs/, Archiv).

## [1.0.0] — 2026-02-23

### Initial Release 🎉
- VAD Conversation Mode (fully hands-free, auto speech detection)
- Multi-bot support with bot selection screen
- Chat history persisted per bot (up to 200 messages)
- Bilingual UI (German + English)
- Relay server connection via local network or Tailscale
- Connection test in Settings
- AirPods support (experimental, disabled by default)
