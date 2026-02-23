# Speak with OpenClaw — Setup-Anleitung (Allgemein)

**Version:** 1.0  
**Erstellt:** 2026-02-20  
**Aktualisiert:** 2026-02-20  
**Zweck:** Allgemeiner Setup-Leitfaden für die "Speak with OpenClaw" iOS App (ohne persönliche Credentials)  
**Owner:** Tony 🔧

---

## ⚠️ Was ist das?

Diese Anleitung beschreibt das **generische Setup** für die "Speak with OpenClaw" iOS App. Sie enthält:
- Systemvoraussetzungen
- Installationsschritte ohne persönliche Werte
- Platzhalter für API-Keys, Tokens, IPs
- Konzepte und Architektur

**Für Johannes' spezifisches Setup (mit konkreten Credentials):** Siehe [SETUP.md](SETUP.md)

---

## 📋 Inhaltsverzeichnis

1. [Systemvoraussetzungen](#1-systemvoraussetzungen)
2. [Python Dependencies](#2-python-dependencies)
3. [Telegram Setup](#3-telegram-setup)
4. [Voice Relay Server](#4-voice-relay-server)
5. [Tailscale Setup](#5-tailscale-setup)
6. [iOS App — Xcode Setup](#6-ios-app--xcode-setup)
7. [App-Konfiguration](#7-app-konfiguration)
8. [Architektur & Kommunikation](#8-architektur--kommunikation)
9. [Wartung & Troubleshooting](#9-wartung--troubleshooting)

---

## 1. Systemvoraussetzungen

### Mac (Server-Seite)

| Komponente | Mindestversion | Empfohlen | Details |
|------------|----------------|-----------|---------|
| **macOS** | 14.0+ (Sonoma) | 15.0+ | Server läuft als User-LaunchAgent |
| **Xcode** | 15.0+ | 16.0+ | Für iOS-App-Entwicklung |
| **Python** | 3.11+ | 3.11.x | Via [python.org](https://www.python.org) |
| **Homebrew** | Latest | Latest | [brew.sh](https://brew.sh) |
| **xcodegen** | 2.40+ | 2.44+ | `brew install xcodegen` |
| **Tailscale** | 1.90+ | 1.94+ | `brew install tailscale` |

### iPhone

| Komponente | Version |
|------------|---------|
| **iOS** | 17.0+ |
| **Berechtigungen** | Mikrofon, Spracherkennung |

### Prüfung der Voraussetzungen

```bash
# macOS Version
sw_vers

# Xcode Version
xcodebuild -version

# Python Version
python3 --version

# Homebrew
brew --version

# xcodegen
xcodegen version

# Tailscale
/usr/local/bin/tailscale version
```

---

## 2. Python Dependencies

### Installation

```bash
# Flask und Telethon installieren
pip3 install flask telethon
```

### Empfohlene Versionen

- **Flask:** 3.0+
- **Telethon:** 1.40+

**Prüfung:**
```bash
pip3 list | grep -E "(flask|telethon)"
```

> ⚠️ **Kompatibilität:** Telethon-API kann sich ändern. Getestet mit Flask 3.1.0 + Telethon 1.42.0.

---

## 3. Telegram Setup

### 3.1 Telegram Account

Du brauchst einen **Telegram User-Account** (nicht nur Bot-Account).

**Warum?** Der Relay-Server sendet Nachrichten als **User** (nicht als Bot) → Bots können eigene Nachrichten nicht sehen, aber User-Nachrichten empfangen.

### 3.2 Telegram API Credentials

1. Gehe zu [https://my.telegram.org](https://my.telegram.org)
2. Logge dich mit deiner Telegram-Nummer ein
3. **API development tools** → Create new application
4. Notiere:
   - **API_ID** (z.B. `12345678`)
   - **API_HASH** (z.B. `abcdef1234567890abcdef1234567890`)

> ⚠️ Diese Werte sind **nicht** dein Bot-Token! Sie sind für Telethon User-API.

### 3.3 Telethon Session erstellen

Die Telethon-Session ist eine Authentifizierungs-Datei die nach dem ersten Login gespeichert wird.

**Einmalige Erstellung:**

```bash
cd <dein-projekt-ordner>

# Temporäres Python-Script zum Session-Init
cat > init_session.py << 'EOF'
from telethon import TelegramClient

API_ID   = <deine-api-id>
API_HASH = "<dein-api-hash>"
SESSION  = ".botchat-relay-session"

client = TelegramClient(SESSION, API_ID, API_HASH)
client.start()
print("✅ Session erstellt!")
client.disconnect()
EOF

python3 init_session.py
```

**Ablauf:**
1. Script startet → Telegram sendet einen Login-Code an deine Nummer
2. Code eingeben → Session wird erstellt
3. `.botchat-relay-session` Datei erscheint im Verzeichnis

> ⚠️ **Einmalig:** Session muss nur 1x erstellt werden. Danach ist die Authentifizierung persistent. **NIEMALS** in Git committen!

### 3.4 Bot-Tokens erstellen

**Du brauchst mindestens einen Telegram Bot.**

1. Öffne Telegram → Suche `@BotFather`
2. `/newbot` → Folge den Anweisungen
3. Notiere den **Bot-Token** (z.B. `1234567890:ABCdefGHIjklMNOpqrsTUVwxyz`)
4. Notiere den **Bot-Username** (z.B. `@mein_bot`)

**Für OpenClaw:** Idealerweise mehrere Bots für verschiedene Charaktere/Rollen (z.B. "Friedrich", "Arthur", "Tony").

### 3.5 Bot-User-IDs herausfinden

Die User-ID eines Bots ist der erste Teil des Tokens (vor dem `:`).

**Beispiel:**
- Token: `8244960902:AAF6qfXjPxgDMvSnMAPyhfdxNZLsRBSJRE4`
- User-ID: `8244960902`

Diese User-ID wird im `voice-relay-server.py` gebraucht (siehe 4.2).

---

## 4. Voice Relay Server

### 4.1 Was ist der Voice Relay Server?

**Zweck:** HTTP-Server der als Middleware zwischen iPhone-App und Telegram-Bots fungiert.

**Architektur:**
```
iPhone App → HTTP POST /voice → Relay-Server → Telethon (als User) → Bot → Antwort
```

**Warum nicht direkt Bot-Token verwenden?**  
Telegram-Bots sehen ihre **eigenen Nachrichten nicht**. Wenn die App direkt mit Bot-Token sendet, kann der Bot die Nachricht nicht empfangen. Lösung: App sendet als User → Bot empfängt Nachricht vom User → antwortet an User.

### 4.2 Script erstellen

**Pfad:** `~/OpenClaw/shared/scripts/voice-relay-server.py` (oder ein anderer Pfad deiner Wahl)

**Minimal-Version des Scripts:**

```python
#!/usr/local/bin/python3
"""
Voice Relay Server — Speak with OpenClaw iOS App Backend
"""

import os
import asyncio
import tempfile
import threading
from flask import Flask, request, jsonify, send_file
from telethon import TelegramClient, events
from telethon.tl.types import InputPeerUser

# === CONFIG ===
API_ID   = <deine-api-id>
API_HASH = "<dein-api-hash>"
SESSION  = "<pfad-zur-session-datei>"  # z.B. "/Users/dein-name/.botchat-relay-session"
PORT     = 18800
TIMEOUT  = 45  # Sekunden auf Bot-Antwort warten

# Bot-Username → Bot-User-ID (für sendMessage)
BOT_MAP = {
    "<bot-username>": <bot-user-id>,  # z.B. "mein_bot": 1234567890
}

# === FLASK APP ===
app = Flask(__name__)

# Telethon Client (läuft in eigenem Event-Loop in separatem Thread)
client: TelegramClient = None
loop: asyncio.AbstractEventLoop = None

def start_telethon():
    """Telethon in eigenem Thread + Event-Loop starten."""
    global client, loop

    async def _start():
        global client
        client = TelegramClient(SESSION, API_ID, API_HASH)
        await client.start()
        me = await client.get_me()
        print(f"[voice-relay] Telethon verbunden als {me.username}")
        await client.run_until_disconnected()

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(_start())

def run_async(coro):
    """Coroutine im Telethon-Loop ausführen (thread-safe)."""
    future = asyncio.run_coroutine_threadsafe(coro, loop)
    return future.result(timeout=TIMEOUT + 5)

# === ROUTES ===

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True, "service": "voice-relay"})

@app.route("/bots", methods=["GET"])
def list_bots():
    """Verfügbare Bots auflisten."""
    bots = [
        {"name": "Bot1", "username": "<bot-username>", "emoji": "🤖"},
    ]
    return jsonify({"ok": True, "bots": bots})

@app.route("/voice", methods=["POST"])
def receive_voice():
    """
    POST /voice
    Form-Data:
      - voice: Audio-Datei
      - bot:   Bot-Username
    """
    bot_username = request.form.get("bot", list(BOT_MAP.keys())[0])
    voice_file   = request.files.get("voice")

    if not voice_file:
        return jsonify({"ok": False, "error": "Keine Audio-Datei"}), 400

    # Audio speichern
    temp_path = tempfile.NamedTemporaryFile(delete=False, suffix=".m4a").name
    voice_file.save(temp_path)

    # An Bot senden + auf Antwort warten
    try:
        reply = run_async(send_and_wait(bot_username, voice_path=temp_path))
        os.unlink(temp_path)

        if reply["type"] == "voice":
            return send_file(reply["path"], mimetype="audio/ogg")
        else:
            return jsonify({"ok": True, "text": reply["text"]})

    except Exception as e:
        os.unlink(temp_path)
        return jsonify({"ok": False, "error": str(e)}), 500

async def send_and_wait(bot_username, voice_path=None, text=None):
    """Audio/Text an Bot senden, auf Antwort warten."""
    bot_id = BOT_MAP.get(bot_username)
    if not bot_id:
        raise ValueError(f"Unbekannter Bot: {bot_username}")

    peer = InputPeerUser(bot_id, 0)

    # Nachricht senden
    if voice_path:
        await client.send_file(peer, voice_path, voice_note=True)
    elif text:
        await client.send_message(peer, text)

    # Auf Antwort warten (Polling)
    reply = await wait_for_reply(bot_id)
    return reply

async def wait_for_reply(bot_id):
    """Wartet auf Antwort vom Bot."""
    start_time = asyncio.get_event_loop().time()
    while True:
        messages = await client.get_messages(bot_id, limit=1)
        if messages and not messages[0].out:
            msg = messages[0]
            if msg.voice:
                # Audio-Antwort
                temp_path = tempfile.NamedTemporaryFile(delete=False, suffix=".ogg").name
                await client.download_media(msg.voice, temp_path)
                return {"type": "voice", "path": temp_path}
            elif msg.text:
                # Text-Antwort
                return {"type": "text", "text": msg.text}

        if asyncio.get_event_loop().time() - start_time > TIMEOUT:
            raise TimeoutError("Bot hat nicht rechtzeitig geantwortet")

        await asyncio.sleep(1)

# === MAIN ===
if __name__ == "__main__":
    # Telethon in separatem Thread starten
    telethon_thread = threading.Thread(target=start_telethon, daemon=True)
    telethon_thread.start()

    # Flask starten
    import time
    time.sleep(2)  # Telethon Zeit geben zu connecten
    app.run(host="0.0.0.0", port=PORT)
```

> ⚠️ **Vereinfacht:** Das ist eine Minimal-Version. Das vollständige Script hat zusätzlich `/text` Endpoint, besseres Error-Handling, und Logging.

### 4.3 Script ausführbar machen

```bash
chmod +x voice-relay-server.py
```

### 4.4 LaunchAgent erstellen (Auto-Start bei Mac-Neustart)

**Pfad:** `~/Library/LaunchAgents/com.<dein-name>.voice-relay-server.plist`

**Inhalt:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.<dein-name>.voice-relay-server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string><pfad-zum-script>/voice-relay-server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/voice-relay-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/voice-relay-stderr.log</string>
    <key>WorkingDirectory</key>
    <string><pfad-zum-script-ordner></string>
</dict>
</plist>
```

**Laden:**
```bash
launchctl load ~/Library/LaunchAgents/com.<dein-name>.voice-relay-server.plist
```

### 4.5 LaunchAgent verwalten

```bash
# Starten
launchctl start com.<dein-name>.voice-relay-server

# Stoppen
launchctl stop com.<dein-name>.voice-relay-server

# Neu starten
launchctl kickstart -k gui/$(id -u)/com.<dein-name>.voice-relay-server

# Status prüfen
launchctl list | grep voice-relay

# Logs
tail -f /tmp/voice-relay-stdout.log
tail -f /tmp/voice-relay-stderr.log
```

### 4.6 Health-Check

```bash
# Lokal testen
curl http://127.0.0.1:18800/health

# Erwartete Antwort:
# {"ok":true,"service":"voice-relay"}
```

---

## 5. Tailscale Setup

### 5.1 Warum Tailscale?

**Problem mit lokalem WLAN:**
- iPhone und Mac müssen im **selben WLAN** sein
- Server-URL (Mac-IP) ändert sich bei IP-Wechsel
- Funktioniert nur zu Hause

**Lösung: Tailscale VPN**
- iPhone kann **überall auf der Welt** auf den Mac zugreifen
- Feste Tailscale-IP (z.B. `100.x.x.x`)
- Ende-zu-Ende-verschlüsselt
- Keine Port-Forwards nötig

### 5.2 Installation

```bash
brew install tailscale
```

> ⚠️ **Problem:** Homebrew installiert Tailscale im `userspace-networking` Modus → eingehende Verbindungen funktionieren **nicht**!

**Lösung:** LaunchDaemon als root (ohne userspace-networking) statt Homebrew-LaunchAgent.

### 5.3 Erste Einrichtung

```bash
# Tailscale starten (einmalig für Auth)
/usr/local/bin/tailscale up
```

**Ablauf:**
1. Befehl gibt Auth-URL aus
2. URL im Browser öffnen
3. Mit Tailscale-Account einloggen (oder neuen Account erstellen)
4. Mac wird dem Tailscale-Netzwerk hinzugefügt

### 5.4 LaunchDaemon (root, ohne userspace-networking)

**Warum LaunchDaemon?**
- Läuft als root → kann echtes Netzwerk-Interface (`utun`) erstellen
- Eingehende Verbindungen funktionieren
- `--tun=userspace-networking` wird NICHT verwendet

**Pfad:** `/Library/LaunchDaemons/com.<dein-name>.tailscaled.plist`

**Inhalt:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.<dein-name>.tailscaled</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/tailscaled</string>
        <string>--state</string>
        <string>/Users/<dein-username>/.tailscale/tailscaled.state</string>
        <string>--socket</string>
        <string>/var/run/tailscaled.socket</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/tailscaled.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/tailscaled-error.log</string>
</dict>
</plist>
```

**Installation:**
```bash
# plist-Datei erstellen
sudo nano /Library/LaunchDaemons/com.<dein-name>.tailscaled.plist

# Inhalt einfügen (siehe oben), dann speichern (Ctrl+O, Ctrl+X)

# Berechtigungen setzen
sudo chown root:wheel /Library/LaunchDaemons/com.<dein-name>.tailscaled.plist
sudo chmod 644 /Library/LaunchDaemons/com.<dein-name>.tailscaled.plist

# LaunchDaemon laden
sudo launchctl load /Library/LaunchDaemons/com.<dein-name>.tailscaled.plist
```

### 5.5 Tailscale verbinden

```bash
# Tailscale verbinden
/usr/local/bin/tailscale up
```

**Keine Auth-URL diesmal** — Account ist bereits verbunden (aus 5.3).

### 5.6 macOS Firewall konfigurieren

**Tailscaled zur Firewall hinzufügen:**
1. Warnung erscheint: "tailscaled möchte sich verbinden"
2. **"Alle Verbindungen"** auswählen
3. **"Erlauben"** klicken
4. **"Für immer"** wählen

**Python zur Firewall hinzufügen:**
```bash
# Python explizit erlauben (für voice-relay-server.py)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "/Library/Frameworks/Python.framework/Versions/3.11/Resources/Python.app/Contents/MacOS/Python"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "/Library/Frameworks/Python.framework/Versions/3.11/Resources/Python.app/Contents/MacOS/Python"
```

> ⚠️ Pfad zu Python kann je nach Installation variieren. Prüfen mit `which python3`.

### 5.7 Tailscale-IP herausfinden

```bash
/usr/local/bin/tailscale status
```

**Deine Tailscale-IP:** Die IP in der ersten Zeile (z.B. `100.x.x.x`)

**Notiere diese IP** — du brauchst sie für die App-Konfiguration.

### 5.8 Verbindung testen

**Von jedem Gerät im Tailscale-Netzwerk:**
```bash
curl http://<deine-tailscale-ip>:18800/health
```

**Erwartete Antwort:**
```json
{"ok":true,"service":"voice-relay"}
```

### 5.9 LaunchDaemon verwalten

```bash
# Status prüfen
sudo launchctl list | grep tailscaled

# Neu starten
sudo launchctl kickstart -k system/com.<dein-name>.tailscaled

# Logs prüfen
tail -f /tmp/tailscaled.log
tail -f /tmp/tailscaled-error.log
```

---

## 6. iOS App — Xcode Setup

### 6.1 Projektordner

**Repository:** [https://github.com/<dein-repo>/speak-with-openclaw-ios](https://github.com/<dein-repo>/speak-with-openclaw-ios) (oder lokaler Pfad)

```bash
# Projekt clonen
git clone <dein-repo-url>
cd speak-with-openclaw-ios
```

### 6.2 Swift-Dateien Struktur

**Wichtig:** Es gibt **zwei** Orte für Swift-Dateien:

1. **`Sources/`** — Source of Truth, wird in Git eingecheckt
2. **Root** — Was Xcode kompiliert (wird von XcodeGen generiert)

**Nach Änderungen in `Sources/`:**
```bash
# Swift-Dateien ins Root kopieren
cp Sources/*.swift .

# Xcode-Projekt regenerieren
xcodegen generate
```

### 6.3 XcodeGen Workflow

**Was ist XcodeGen?**  
Tool zum Generieren von `.xcodeproj` aus einer `project.yml` Datei. Verhindert Merge-Konflikte in Git.

**project.yml anpassen:**
```yaml
name: BotVoice
options:
  bundleIdPrefix: <deine-domain-reversed>  # z.B. com.example
  deploymentTarget:
    iOS: "17.0"

settings:
  base:
    DEVELOPMENT_TEAM: "<dein-team-id>"  # Aus Xcode → Signing & Capabilities

targets:
  BotVoice:
    type: application
    platform: iOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: <deine-domain-reversed>.heyopenclaw
        INFOPLIST_FILE: Sources/Info.plist
```

**Projekt generieren:**
```bash
xcodegen generate
```

### 6.4 Xcode öffnen und konfigurieren

```bash
# Xcode öffnen
open BotVoice.xcodeproj
```

**In Xcode:**
1. **Signing & Capabilities** → Development Team: Dein Apple Developer Team
2. **Info** → Bundle Identifier: `<deine-domain>.heyopenclaw`
3. **Deployment Target:** iOS 17.0

**iPhone verbinden:**
1. iPhone per USB verbinden
2. In Xcode: Gerät auswählen (oben links)
3. **Play-Button** → App wird auf iPhone installiert

### 6.5 Berechtigungen (Info.plist)

**Bereits konfiguriert in `Sources/Info.plist`:**

```xml
<key>NSMicrophoneUsageDescription</key>
<string>BotVoice braucht das Mikrofon um deine Sprachnachrichten aufzunehmen.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>BotVoice nutzt Spracherkennung um auf dein Hotword zu reagieren.</string>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>fetch</string>
</array>
```

**Beim ersten App-Start:**
- iOS fragt nach Mikrofon-Berechtigung → **Erlauben**
- iOS fragt nach Spracherkennung → **Erlauben**

---

## 7. App-Konfiguration

### 7.1 Server-URL eintragen

**In der App → Einstellungen:**

**Tailscale (empfohlen):**
```
http://<deine-tailscale-ip>:18800
```

**Nur Heimnetz (WLAN):**
```
http://<deine-lokale-ip>:18800
```

> ⚠️ Lokale IP kann sich ändern! Tailscale-IP ist stabil.

**Lokale IP herausfinden:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

### 7.2 Bot auswählen

**In der App:**
- Toolbar → Bot-Symbol → Bot auswählen

**Verfügbare Bots:** Werden in `Models.swift` konfiguriert. Standard: Friedrich, Arthur, Pucky, Waulter, Tony, JoDigital.

**Eigene Bots hinzufügen:**
1. `Sources/Models.swift` öffnen
2. In `Bot.presets` neuen Bot hinzufügen:
```swift
Bot(name: "MeinBot", token: "1234567890:ABC...", username: "meinbot", emoji: "🤖")
```
3. `cp Sources/Models.swift Models.swift`
4. `xcodegen generate`
5. In Xcode neu builden

### 7.3 Hotword (optional)

**Was ist Hotword?**  
Aktivierungswort (wie "Hey Siri") → App hört im Hintergrund → bei Erkennung startet Aufnahme automatisch.

**In der App → Einstellungen:**
- **Hotword aktivieren:** An/Aus
- **Aktivierungswort:** Standard: "Hey"
- **Hotword-Sprache:** `de-DE`, `en-US`, `fr-FR`, etc.
- **Stille-Schwelle:** 1–5 Sekunden (Zeit bis Aufnahme automatisch stoppt)

**Empfohlene Einstellung:**
- Aktivierungswort: "Hey" oder "Okay"
- Sprache: Deine Hauptsprache
- Stille-Schwelle: 2 Sekunden

### 7.4 Verbindungstest

**In der App → Einstellungen:**
- **"Verbindung testen"** → sollte "✅ Server erreichbar" zeigen

**Falls Fehler:**
- Server läuft? → `launchctl list | grep voice-relay`
- Firewall blockiert? → Siehe 5.6
- Tailscale verbunden? → `/usr/local/bin/tailscale status`
- Richtige URL? → `http://<deine-tailscale-ip>:18800`
- Health-Check: `curl http://<deine-tailscale-ip>:18800/health`

---

## 8. Architektur & Kommunikation

### 8.1 Finale Architektur

```
┌─────────────────────────────────────────────────────────────┐
│ iPhone App (Speak with OpenClaw)                                   │
│ - Push-to-talk ODER Hotword-Aktivierung                     │
│ - Aufnahme als M4A                                           │
│ - HTTP POST /voice                                           │
└────────────┬────────────────────────────────────────────────┘
             │
             │ HTTP (Tailscale VPN oder WLAN)
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Mac (voice-relay-server.py, Port 18800)                     │
│ - Flask HTTP-Server                                          │
│ - Telethon (als User-Account)                               │
│ - Schickt Audio an gewählten Bot                            │
│ - Wartet auf Antwort (Polling, 45s Timeout)                 │
└────────────┬────────────────────────────────────────────────┘
             │
             │ Telegram User-API
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Telegram Bot (@dein_bot)                                    │
│ - Empfängt Audio vom User                                   │
│ - OpenClaw Gateway verarbeitet (oder anderer Bot-Backend)   │
│ - LLM antwortet (Claude, GPT, etc.)                         │
│ - TTS erstellt Audio (Google, ElevenLabs, etc.)            │
│ - Schickt Audio zurück an User                              │
└────────────┬────────────────────────────────────────────────┘
             │
             │ Telegram User-API (Antwort)
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Mac (voice-relay-server.py)                                 │
│ - Empfängt Bot-Antwort                                       │
│ - Lädt Audio herunter                                        │
│ - HTTP Response zurück an App                               │
└────────────┬────────────────────────────────────────────────┘
             │
             │ HTTP Response (audio/ogg)
             ▼
┌─────────────────────────────────────────────────────────────┐
│ iPhone App                                                   │
│ - Empfängt Audio                                             │
│ - Spielt Antwort automatisch ab                             │
│ - Zeigt Transkript (falls vorhanden)                        │
│ - Startet Hotword wieder (falls aktiviert)                  │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 Warum diese Architektur?

**Warum nicht direkt Bot-Token in der App?**

**Problem:** Telegram Bots sehen ihre **eigenen Nachrichten nicht**.

```
[❌ Funktioniert NICHT]
iPhone → Telegram API (mit Bot-Token) → Bot sendet Nachricht als sich selbst
→ Bot empfängt Nachricht NICHT (Bots sehen eigene Nachrichten nicht)
```

**Lösung:** App sendet als **User** via Relay-Server:

```
[✅ Funktioniert]
iPhone → Relay → Telethon (als User) → Bot empfängt Nachricht vom User
→ Bot antwortet an User → Relay empfängt Antwort → App empfängt Antwort
```

**Warum Relay-Server statt direkt Telethon in der App?**
- Telethon ist Python → nicht nativ auf iOS
- Session-Management kompliziert
- HTTP-Interface einfacher + testbar
- Server kann weitere Logik handhaben (z.B. STT, Logging)

---

## 9. Wartung & Troubleshooting

### 9.1 Dienste neu starten

**Voice Relay Server:**
```bash
launchctl kickstart -k gui/$(id -u)/com.<dein-name>.voice-relay-server
```

**Tailscale:**
```bash
sudo launchctl kickstart -k system/com.<dein-name>.tailscaled
```

### 9.2 Logs prüfen

**Voice Relay Server:**
```bash
tail -f /tmp/voice-relay-stdout.log
tail -f /tmp/voice-relay-stderr.log
```

**Tailscale:**
```bash
tail -f /tmp/tailscaled.log
tail -f /tmp/tailscaled-error.log
```

### 9.3 Häufige Fehler

#### Fehler: "database is locked" (Telethon)

**Symptom:** Relay-Server startet nicht, Log zeigt `sqlite3.OperationalError: database is locked`

**Ursache:** Ein anderer Prozess hält die Telethon-Session-Datei offen.

**Lösung:**
```bash
# Prozess finden
lsof <pfad-zur-session-datei>

# Prozess killen
kill <PID>

# Relay-Server neu starten
launchctl kickstart -k gui/$(id -u)/com.<dein-name>.voice-relay-server
```

#### Fehler: "Bad file descriptor" (Flask)

**Symptom:** Flask-Server stürzt ab mit `OSError: [Errno 9] Bad file descriptor`

**Ursache:** Tailscale wurde neu gestartet → Netzwerk-Interface ändert sich → Flask-Server verliert Socket.

**Lösung:**
```bash
# Relay-Server neu starten
launchctl kickstart -k gui/$(id -u)/com.<dein-name>.voice-relay-server
```

#### Fehler: App kann Server nicht erreichen

**Symptom:** "Server nicht erreichbar" in App-Einstellungen

**Checkliste:**
1. Server läuft? → `launchctl list | grep voice-relay`
2. Tailscale verbunden? → `/usr/local/bin/tailscale status`
3. Firewall blockiert? → Siehe 5.6
4. Richtige URL? → `http://<deine-tailscale-ip>:18800`
5. Health-Check: `curl http://<deine-tailscale-ip>:18800/health`

### 9.4 Status-Checks (Komplett)

```bash
# Voice Relay Server
curl http://127.0.0.1:18800/health

# Tailscale
/usr/local/bin/tailscale status

# LaunchAgents
launchctl list | grep voice-relay

# LaunchDaemon
sudo launchctl list | grep tailscaled

# Python Dependencies
pip3 list | grep -E "(flask|telethon)"
```

---

## 📝 Checkliste: Von Null bis zur laufenden App

- [ ] macOS 14+, Xcode 15+, Python 3.11+ installiert
- [ ] Homebrew installiert
- [ ] `brew install tailscale xcodegen`
- [ ] `pip3 install flask telethon`
- [ ] Telegram API Credentials von [my.telegram.org](https://my.telegram.org)
- [ ] Telethon Session erstellt
- [ ] Mindestens einen Bot via @BotFather erstellt
- [ ] `voice-relay-server.py` mit Credentials konfiguriert
- [ ] LaunchAgent für `voice-relay-server` erstellt und geladen
- [ ] Tailscale installiert, LaunchDaemon erstellt, `tailscale up` ausgeführt
- [ ] macOS Firewall: Tailscale + Python erlaubt
- [ ] Tailscale-IP notiert
- [ ] Health-Check erfolgreich: `curl http://<tailscale-ip>:18800/health`
- [ ] Xcode-Projekt via `xcodegen generate` erstellt
- [ ] Development Team in Xcode eingetragen
- [ ] App auf iPhone deployed
- [ ] Mikrofon + Spracherkennung Berechtigungen in iOS erteilt
- [ ] Server-URL in App eingetragen
- [ ] Bot ausgewählt
- [ ] Verbindungstest in App erfolgreich
- [ ] Erste Sprachnachricht an Bot gesendet → Antwort empfangen ✅

---

## 🎯 Nächste Schritte

Nach erfolgreicher Installation kannst du:
- **Mehrere Bots erstellen** → verschiedene Charaktere/Rollen
- **Hotword anpassen** → eigenes Aktivierungswort
- **UI customizen** → Swift-Dateien in `Sources/` anpassen
- **TTS/STT Backend wählen** → Google Cloud, ElevenLabs, OpenAI, etc.
- **OpenClaw Gateway integrieren** → Multi-Agent-System mit eigenem Context

---

**Owner:** Tony 🔧  
**Letztes Update:** 2026-02-20
