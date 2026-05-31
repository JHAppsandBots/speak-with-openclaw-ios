# Projekt-Status — Speak with Claw

**Letztes Update:** 31.05.2026 · **Version:** 1.1.0
**Status:** 🟢 Läuft · zuverlässiger Dauerbetrieb · Sicherheit aktiv

## ✅ Funktioniert
- Gesprächsmodus (VAD), Hotword, Push-to-Talk
- Auto-Play der Bot-Audio-Antwort + **Steuerung: Pause / Weiter / Stopp**
- **Chat-Export** als Markdown/Text (Teilen → in Dateien sichern) · **kopierbare Sprechblasen**
- **Hinweis-Ton vor der Antwort** (Settings-Toggle, Default aus, keine Latenz wenn aus)
- Hintergrund-Betrieb (audio+voip), Bluetooth/AirPods, mehrere Bots, lokaler Verlauf, DE/EN-UI
- **Verbindungs-Umschalter** (Einstellungen): direkt übers Gateway (schnell, `/talk`) ⇄ Telegram
- **Heavy/Normal-Schieber** (Hauptseite): max. Tiefe ⇄ adaptiv/schnell
- **Ziel-Toggle** (Hauptseite): OpenClaw ⇄ optionale Terminal-Bridge (lokal, ohne Claude-API)
- **Relay-Auth** (Bearer-Token), Verbindungs- & Terminal-Status-Test in den Einstellungen
- Erkennungs- & App-Sprache **Default Deutsch**

## 🔧 Zuletzt (v1.1.0, 31.05.2026)
- **Zuverlässiger Dauerbetrieb**: Audio-Session wird beim Foreground reaktiviert (`scenePhase`),
  Hör-Modus startet neu; **Playback-Watchdog** gegen hängenden Zustand; robuste Kopfhörer-Route.
- **TTS jetzt MP3** → zuverlässige Wiedergabe auf iOS (AVAudioPlayer spielt MP3 nativ).
- **Doppelte Antworten** endgültig kollabiert (auch kurze); interne Backend-Fehlertexte werden nicht mehr vorgelesen.
- **Deep-Mode-Timeout** erhöht (lange Antworten laufen durch).
- **Aufräumen/KISS**: toter Code entfernt, Crash-Härtung (VAD), Health-Check prüft HTTP 200, Temp-Aufräumung.

## ⏳ Offen / nächste Schritte
1. App-Store-Release (zurückgestellt). Vor Review: ATS von `NSAllowsArbitraryLoads` auf
   `NSAllowsLocalNetworking`/HTTPS einschränken.
2. Optionale Terminal-Bridge: braucht eine laufende Terminal-Session auf dem Mac (lokal, ohne API).

## ⚠️ Bekannte Punkte
- Antwortlatenz hängt von Host/LLM ab (kein Echtzeit); Direkt-Pfad deutlich schneller als Telegram
- VoIP-Hintergrund nur auf echtem iPhone (nicht Simulator)
