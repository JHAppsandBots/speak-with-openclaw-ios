# Projekt-Status — Speak with Claw

**Letztes Update:** 31.05.2026 · **Version:** 1.0.4
**Status:** 🟢 Läuft · Latenz ~4× schneller · Sicherheit aktiv · bereit zum Re-Publish

## ✅ Funktioniert
- Gesprächsmodus (VAD), Hotword („Hey Bot"), Push-to-Talk
- Auto-Play der Bot-Audio-Antwort, Hintergrund-Betrieb (audio+voip), AirPods/Bluetooth
- Mehrere Bots, Chat-Verlauf lokal, DE/EN-UI
- **Verbindungs-Umschalter** (Einstellungen → Verbindung): direkt übers Gateway (schnell, `/talk`) ⇄ Telegram
- **Heavy/Normal-Schieber** (Hauptseite, orange/silber): max. Tiefe ⇄ adaptiv/schnell
- **Relay-Auth** (Bearer-Token), Verbindungstest in den Einstellungen

## 🔧 Zuletzt (v1.0.2–1.0.4, 31.05.2026)
- **Latenz** ~60 s → ~8–12 s: OpenClaw-Gateway-Update + Direkt-Pfad `/talk` (Ursache war der Agent-/Transport-Pfad, nicht Host-Last). Siehe `docs/LATENCY.md`.
- VAD-Sprechanfang, Haptik, dunkler Verlauf, Build-Stempel
- **Sicherheit**: Bearer-Token-Auth, keine Befehls-/Prompt-Injection (subprocess-Liste)
- **Fixes**: Bots ohne Gateway-Agent → Telegram-Fallback (kein 400 mehr), klare Fehlermeldungen, doppelte Antworten kollabiert
- Bundle-ID/Quelldateien/Anzeigename (1.0.1) bereits gefixt

## ⏳ Offen / nächste Schritte
1. `git diff` prüfen → committen + pushen (Working Tree aktuell **nicht** committet)
2. `fastlane release` → Upload; in App Store Connect zur Prüfung einreichen
3. Optional: History-Secret-Scan vor Push

## ⚠️ Bekannte Punkte
- Antwortlatenz hängt von Host/LLM ab (kein Echtzeit); Direkt-Pfad deutlich schneller als Telegram
- VoIP-Hintergrund nur auf echtem iPhone (nicht Simulator)
