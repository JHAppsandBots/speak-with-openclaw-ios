# Speak with Claw — Setup Guide

**Version:** 1.1
**Updated:** 2026-02-26

---

## What is this?

Speak with Claw is an iOS app that gives you a voice interface for your Telegram bots running on [OpenClaw](https://openclaw.ai). You speak — your bot listens and responds with audio.

> ⚠️ **Latency:** Responses are not instant. Expect 3–10 seconds per reply depending on your LLM and network. This is not a Siri replacement — it's a real conversation with your own self-hosted AI bot.

---

## System Requirements

### Mac (server side)

| Component | Minimum | Notes |
|-----------|---------|-------|
| macOS | 14.0+ (Sonoma) | Server runs as user LaunchAgent |
| Xcode | 15.0+ | For building the iOS app |
| Python | 3.11+ | For the relay server |
| xcodegen | 2.40+ | `brew install xcodegen` |
| Tailscale | 1.90+ | Recommended for remote access |

### iPhone

| Component | Version |
|-----------|---------|
| iOS | 17.0+ |
| Permissions | Microphone, Speech Recognition |

---

## Architecture

```
iPhone App (Speak with Claw)
        │
        │ HTTP (Tailscale or local network)
        ▼
Mac — voice-relay-server.py (port 18800)
  - Flask HTTP server
  - Telethon (acts as your Telegram user account)
  - Sends audio to your bot, waits for reply
        │
        │ Telegram User API
        ▼
Your Telegram Bot
  - Receives audio from the relay user
  - OpenClaw processes it via LLM
  - TTS creates audio response
  - Sends audio back
        │
        │ Telegram User API (response)
        ▼
Mac — relay server receives the reply
        │
        │ HTTP response (audio)
        ▼
iPhone App — plays audio response
```

**Why a relay server?**
Telegram bots cannot receive their own messages. The relay server sends your audio *as a Telegram user* (via Telethon), so the bot sees it and responds.

---

## Step 1: Telegram API Credentials

You need a **Telegram user account** (not just a bot).

1. Go to [https://my.telegram.org](https://my.telegram.org)
2. Log in with your phone number
3. **API development tools** → Create new application
4. Note your **API_ID** and **API_HASH**

---

## Step 2: Create a Telegram Bot

1. Open Telegram → message [@BotFather](https://t.me/BotFather)
2. `/newbot` → follow the steps
3. Copy the **Bot Token** (e.g. `1234567890:ABCdef...`)

---

## Step 3: Install OpenClaw

```bash
npm install -g openclaw
openclaw init
openclaw gateway start
```

Full OpenClaw docs: [https://docs.openclaw.ai](https://docs.openclaw.ai)

---

## Step 4: Install the Relay Server

```bash
pip3 install flask telethon
```

Create a Telethon session (one time only):

```python
from telethon import TelegramClient

client = TelegramClient(".relay-session", YOUR_API_ID, "YOUR_API_HASH")
client.start()
print("Session created.")
client.disconnect()
```

Run this once — it will ask for your phone number and a Telegram login code. The session file is saved and reused automatically.

> ⚠️ Never commit the session file to Git.

---

## Step 5: Tailscale (recommended)

Tailscale gives your iPhone a stable connection to your Mac from anywhere — no port forwarding needed.

```bash
brew install tailscale
tailscale up
```

Find your Mac's Tailscale IP:
```bash
tailscale status
```

Test from your iPhone or any device:
```bash
curl http://<your-tailscale-ip>:18800/health
```

---

## Step 6: Configure the App

1. Open Speak with Claw
2. Settings → Server URL: `http://<your-tailscale-ip>:18800`
3. Add your bot(s)
4. Test connection → ✅

---

## Troubleshooting

**Bot doesn't respond:**
- Is OpenClaw running? → `openclaw gateway status`
- Is the relay server running? → `curl http://127.0.0.1:18800/health`
- Is the bot token correct?

**No audio in response:**
- Is TTS configured in OpenClaw? → Google API key set?
- Is `messages.tts.auto` set to `"inbound"` in your OpenClaw config?

**App can't reach server:**
- Is Tailscale connected on both devices?
- Firewall blocking Python? → Allow in macOS System Settings → Firewall

**Responses are slow:**
- This is expected. LLM processing + TTS takes 3–10 seconds.
- Faster models (e.g. GPT-4o-mini) reduce latency.

---

## Full Setup Guide

For the complete step-by-step guide including LaunchAgent setup, Xcode configuration, and advanced options, see the main [README.md](../README.md).
