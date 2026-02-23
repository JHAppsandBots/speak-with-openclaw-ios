# Speak with OpenClaw 🦞🎤

> Sprich mit deinen KI-Bots auf Telegram — freihändig, wie mit Siri.

Speak with OpenClaw ist eine iOS-App die als Sprach-Interface für Telegram-Bots funktioniert. Du sprichst, der Bot antwortet — Audio spielt automatisch ab. Mit Hotword-Erkennung ("Hey Bot") komplett hands-free.

---

## Was die App macht

- 🎤 **Push-to-talk** — Mikrofon-Button halten, sprechen, loslassen
- 👂 **Hotword** — "Hey Bot" sagen, App reagiert automatisch
- 🔊 **Auto-Play** — Bot-Antwort spielt sofort ab, kein Tippen
- 📱 **Hintergrund** — funktioniert auch bei gesperrtem Handy (VoIP-Modus)
- ⚙️ **Stille-Erkennung** — stoppt automatisch nach X Sekunden Stille (einstellbar 1–5s)
- 💬 **Konversations-Verlauf** — alle Nachrichten als Chat

---

## Was du brauchst

Speak with OpenClaw ist eine **App-Oberfläche**. Du brauchst einen laufenden KI-Bot im Hintergrund.

**Voraussetzungen:**
- iPhone (iOS 17+)
- Mac mit macOS 14+ (läuft im Hintergrund)
- [OpenClaw](https://openclaw.ai) — das Gateway zwischen App und KI
- [Tailscale](https://tailscale.com) — **empfohlen** für Zugriff außerhalb des Heimnetzwerks (kostenlos)
- Telegram-Account
- Claude API Key (von [Anthropic](https://console.anthropic.com))
- Google Cloud API Key — für STT (Spracherkennung) und TTS (Sprachausgabe)

---

## Setup-Anleitung

> **Hinweis zur Architektur:** Speak with OpenClaw kommuniziert direkt mit dem OpenClaw-Gateway auf dem Mac (Port 18800) — kein Relay-Bot mehr nötig. Die App sendet Audio direkt an den Mac-Server, der dann den KI-Bot aufruft und Audio zurückliefert. Ein früherer Ansatz mit einem Relay-Telegram-Bot ist **hinfällig** und wird nicht mehr benötigt.

> **Empfehlung: Tailscale** — Für Zugriff außerhalb des Heimnetzwerks (z.B. unterwegs) ist [Tailscale](https://tailscale.com) die beste Lösung. Einmalig auf Mac und iPhone installieren → der Mac bekommt einen festen Hostname (z.B. `mein-mac.tailnet.ts.net`) → in der App als Server-URL eintragen → funktioniert überall, kein Port-Forwarding nötig.

### Schritt 1: Telegram Bot erstellen

1. Öffne Telegram → schreib @BotFather
2. `/newbot` eingeben
3. Namen vergeben (z.B. "Mein KI-Assistent")
4. **Bot-Token kopieren** — sieht so aus: `1234567890:AABBccDDeeFFgg...`

### Schritt 2: OpenClaw installieren

```bash
# OpenClaw installieren (Node.js 18+ vorausgesetzt)
npm install -g openclaw

# Initialisieren
openclaw init
```

### Schritt 3: OpenClaw konfigurieren

Kopiere diese Beispiel-Config nach `~/.openclaw/openclaw.json` und passe sie an:

```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "DEIN-EIGENER-TOKEN"
    }
  },
  "agents": {
    "defaults": {
      "model": "anthropic/claude-sonnet-4-5",
      "thinking": "off"
    },
    "list": [
      {
        "id": "main",
        "name": "Mein Bot",
        "workspaceDir": "~/openclaw-workspace"
      }
    ]
  },
  "channels": {
    "telegram": {
      "streamMode": "off",
      "dmPolicy": "allowlist",
      "accounts": {
        "meinbot": {
          "botToken": "DEIN-BOT-TOKEN-VON-BOTFATHER",
          "dmPolicy": "allowlist",
          "allowFrom": ["DEINE-TELEGRAM-USER-ID"]
        }
      }
    }
  },
  "messages": {
    "tts": {
      "auto": "inbound",
      "edge": { "enabled": false }
    }
  },
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "language": "de"
      }
    }
  }
}
```

**Deine Telegram User-ID herausfinden:**
- Schreib @userinfobot auf Telegram → er antwortet mit deiner ID

### Schritt 4: TTS (Text-to-Speech) konfigurieren

**Empfehlung: Google Cloud TTS** (beste Qualität, natürliche Stimme)

```bash
# Google Cloud API Key holen: console.cloud.google.com
# Text-to-Speech API aktivieren

# In openclaw.json unter env.vars eintragen:
"env": {
  "vars": {
    "GOOGLE_API_KEY": "DEIN-GOOGLE-API-KEY"
  }
}
```

Verfügbare deutsche Stimmen:
- `de-DE-Chirp3-HD-Umbriel` — natürlich, warm (empfohlen)
- `de-DE-Chirp3-HD-Iapetus` — klar, präzise
- `de-DE-Standard-A` — einfach, kostenlos

**Alternative: ElevenLabs** (beste Qualität, kostenpflichtig)
```json
"tts": {
  "provider": "elevenlabs",
  "elevenlabs": {
    "apiKey": "DEIN-ELEVENLABS-KEY",
    "voiceId": "DEINE-VOICE-ID",
    "modelId": "eleven_multilingual_v2"
  }
}
```

### Schritt 5: OpenClaw starten

```bash
# Als Hintergrunddienst starten (macOS LaunchAgent)
openclaw gateway start

# Status prüfen
openclaw gateway status
# → sollte "running on port 18789" zeigen

# Test: Telegram Bot anschreiben
# → er sollte antworten
```

### Schritt 6: App konfigurieren

1. Speak with OpenClaw App öffnen
2. Einstellungen → Bot-Token eintragen (der von @BotFather)
3. Telegram User-ID eintragen
4. "Verbindung testen" → ✅ Verbunden
5. Fertig!

---

## Hotword anpassen

Standard-Hotword ist "Hey Bot". Du kannst es ändern:

- In der App: Einstellungen → Hotword-Feld
- **Empfehlung:** "hallo", "hey bot", "hey [Name]" — kurze, klare Wörter
- ⚠️ **"OpenClaw"** funktioniert möglicherweise **nicht** — die on-device Spracherkennung erkennt unbekannte Eigennamen oft falsch (z.B. als "open claw", "open clause" o.ä.)
- Hotword-Sprache einstellbar: Einstellungen → Erkennungs-Sprache (Default: Deutsch)
- Die Sprache sollte zur Sprache des Aktivierungsworts passen

**Stille-Erkennung:**
- Einstellungen → Stille-Schieberegler
- 1 Sek = sehr schnell (für kurze Befehle)
- 2 Sek = empfohlen (Johannes' Einstellung)
- 5 Sek = für längere Sätze

---

## Mehrere Bots

Du kannst mehrere Bots in OpenClaw konfigurieren und in der App wechseln:

```json
"accounts": {
  "assistent": {
    "botToken": "TOKEN-BOT-1",
    "allowFrom": ["DEINE-ID"]
  },
  "kreativ": {
    "botToken": "TOKEN-BOT-2", 
    "allowFrom": ["DEINE-ID"]
  }
}
```

In der App: oben links → Bot auswählen.

---

## Fehlerbehebung

**Bot antwortet nicht:**
- OpenClaw läuft? → `openclaw gateway status`
- Bot-Token korrekt? → Verbindungstest in der App
- Bot bei Telegram gestartet? → `/start` schicken

**Kein Audio:**
- TTS konfiguriert? → Google API Key gesetzt?
- `messages.tts.auto` auf `"inbound"` gesetzt?

**Hotword reagiert nicht:**
- Spracherkennung erlaubt? → iPhone Einstellungen → Datenschutz → Spracherkennung
- On-device Erkennung verfügbar? → iOS 16+ erforderlich

**App geht im Hintergrund aus:**
- VoIP-Modus benötigt echtes iPhone (kein Simulator)
- Einmal ein Telefonat simulieren reicht damit iOS die App als VoIP erkennt

---

## Datenschutz

- **Hotword-Erkennung:** 100% on-device, kein Cloud-Upload
- **Sprachaufnahmen:** gehen nur an deinen eigenen Telegram-Bot
- **KI-Antworten:** über deine eigene API (Anthropic/OpenAI) — du kontrollierst alles
- Keine Daten werden an den App-Entwickler gesendet

---

## Lizenz & Kosten

- **App:** 24 Stunden kostenlos testen — danach 6,99€ einmalig (App Store)
- **OpenClaw:** kostenlos (Open Source)
- **Claude API:** nach Verbrauch (~0.003€ pro Nachricht bei Sonnet)
- **Google TTS:** kostenlos bis 1 Mio Zeichen/Monat
- **Telegram:** kostenlos

---

## Entwickelt von

J.H. — built with OpenClaw

*Fragen, Bugs, Feature-Requests: GitHub Issues*

---

## App Store Beschreibung (Entwurf)

**Speak with OpenClaw — Voice Interface für KI-Bots**

Sprich mit deinen KI-Bots auf Telegram — freihändig, wie mit Siri.

Speak with OpenClaw verbindet dein iPhone mit deinem eigenen KI-Assistenten. Push-to-talk oder Hotword-Erkennung — du sprichst, die KI antwortet mit Audio. Komplett in deiner Kontrolle: deine API, dein Bot, deine Daten.

**Features:**
• Hotword-Erkennung ("Hey Bot") — hands-free
• Automatische Stille-Erkennung — kein Button nötig
• Audio-Antworten spielen sofort ab
• Hintergrund-Betrieb bei gesperrtem Handy
• Mehrere Bots wählbar
• On-device Spracherkennung — kein Cloud-Upload

**Voraussetzung:** OpenClaw auf dem Mac (kostenlos, Anleitung auf GitHub)

**24 Stunden kostenlos testen — danach 6,99€ einmalig.**

*Datenschutz: Keine Daten werden an den Entwickler gesendet. Alles läuft über deine eigene Infrastruktur.*
