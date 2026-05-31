# START HERE — Speak with Claw 🦞🎤

**Letztes Update:** 31.05.2026 · v1.0.2
**Status:** 🟢 v1.0.2 bereit (VAD-/Haptik-/Relay-Optimierungen) — Review + Push offen
**Projekt-Typ:** Native iOS-App (SwiftUI)
**🧭 Du bist eine LLM?** → lies zuerst **[docs/00_AI_ENTRY.md](docs/00_AI_ENTRY.md)** (Einstieg/Hub)

---

## 🎯 SOFORT-KONTEXT (30 Sekunden)

**Was:** Freihändige Sprach-Schnittstelle für deine KI-Bots auf Telegram. Du sprichst, die App erkennt
Sprech-Ende automatisch (VAD), schickt das Audio an deinen Mac (OpenClaw-Voice-Relay), der Bot antwortet mit Sprache.

**Tech:** Swift 5.10 · SwiftUI · iOS 17+ · XcodeGen (`project.yml`) · fastlane · **keine Fremd-Dependencies**
(nur Apple: AVFoundation, Speech, AVFAudio).

**Identität:**
- Bundle-ID: `de.johanneshahn.speakwithopenclaw` · Team: `9YMCY74WN3`
- GitHub (public): https://github.com/JHAppsandBots/speak-with-claw-ios
- Xcode-Target/Projekt: `BotVoice` / `BotVoice.xcodeproj` (wird aus `project.yml` generiert)

**Aktuelle Situation (31.05.2026 · v1.0.2):**
- **Zuletzt optimiert:** VAD-Sprechanfang (Pre-Roll 1,2 s, Onset 0,12 s), Haptik, dunkler Verlauf;
  Backend-Relay `/text`-Timeout 90 s→8 s (`/voice` 30 s); `thinkingDefault` off. Details: `CHANGELOG.md`, `docs/00_AI_ENTRY.md` §7.
- **Nächstes TODO:** `git diff` prüfen → committen/pushen → `fastlane release` (Upload, kein Auto-Submit).
- **Bekannte Issues:** Latenz ist host-last-bedingt (nicht die App) → `docs/LATENCY.md`.

---

## 🚀 Quick Start

```bash
cd "~/Library/Mobile Documents/com~apple~CloudDocs/_App Entwicklung/SpeakWithOpenClaw-Public"
xcodegen generate          # erzeugt BotVoice.xcodeproj aus project.yml (Single Source of Truth)
open BotVoice.xcodeproj     # iPhone wählen → ▶ Run  (oder Product ▸ Archive)
```

App Store / TestFlight (automatisiert):
```bash
fastlane release           # xcodegen generate → build → Upload zu App Store Connect (kein Auto-Submit)
```

---

## 📍 Wo finde ich was?

- **docs/00_AI_ENTRY.md** 🧭 — onboarding/hub (für LLMs und zum Überblick)
- **architecture.md** — Design-Entscheidungen & WHY (Audio-Session, VAD, Relay, XcodeGen)
- **docs/README.md** — Index der gesamten Doku
- **docs/01_PROJECT_STATUS.md** ⏰ — aktueller Stand
- **SETUP.md** / **docs/SETUP.md** — End-Nutzer-Setup (OpenClaw, Telegram-Bot, Tailscale)
- **XCODE_SETUP.md** — Build & Signing
- **CHANGELOG.md** — Versions-Historie
- **docs/archive/** — alte/historische Docs (z. B. Launch-Log vom 23.02.2026)
- **Quellcode:** `Sources/*.swift` — **NUR hier editieren** (Root-Dubletten wurden am 30.05.2026 entfernt)
- **fastlane/** — Release-Automation + App-Store-Metadaten

---

## ⚠️ Wichtig
- Swift-Dateien **ausschließlich in `Sources/`** ändern. Früher lagen Kopien im Repo-Root, die der Build
  ignorierte → neueste Edits „verschwanden". Diese Dubletten sind jetzt weg.
- **Keine Secrets im Repo:** `build/`, `.env`, `secrets.swift`, `xcuserdata/` sind gitignored.
  Server-URL/Bot-Token trägst du **in der App** (Einstellungen) ein, nicht im Code.

## 🧱 Von null reproduzieren
Komplette Aufbau-Anleitung (App **und** Mac-Relay/OpenClaw-Backend): **[docs/REPRODUCE_FROM_ZERO.md](docs/REPRODUCE_FROM_ZERO.md)**
