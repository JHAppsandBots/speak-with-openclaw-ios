# Setup Guide — Speak with Claw

> **Letztes Update:** 30.05.2026 · neu hier? → [START_HERE.md](START_HERE.md)

This guide walks you through everything you need to use the app.

---

## What you need

- iPhone with iOS 17+
- A Mac (always-on, or at least running when you want to talk)
- [OpenClaw](https://openclaw.ai) installed on your Mac
- A Telegram bot set up in OpenClaw

---

## Step 1: Install OpenClaw on your Mac

Download and install OpenClaw from [openclaw.ai](https://openclaw.ai).  
Follow the setup guide to create your first AI bot connected to Telegram.

---

## Step 2: Start the Voice Relay Server

The app communicates with your Mac via a small relay server included with OpenClaw.

On your Mac, run:
```bash
python3 voice-relay-server.py
```

The server listens on port **18800** by default.

---

## Step 3: Find your Mac's IP address

**On your local network:**  
Go to System Settings → Network → your connection → note the IP address (e.g. `192.168.0.10`)

**From anywhere (recommended):**  
Install [Tailscale](https://tailscale.com) on both your Mac and iPhone — you'll get a stable IP that works everywhere.

---

## Step 4: Configure the app

Open **Speak with Claw** on your iPhone:

1. Tap the **Settings** icon
2. Enter your Server URL: `http://YOUR_MAC_IP:18800`
3. Enter your bot's Telegram username (e.g. `@mybotname`)
4. Tap **Test Connection** — you should see a green checkmark

---

## Step 5: Start talking

- Tap **Conversation Mode** for fully hands-free back-and-forth
- The app detects when you start and stop speaking automatically
- Your bot responds with voice

---

## Troubleshooting

**"Connection failed"**  
→ Make sure the relay server is running on your Mac  
→ Check that your IP address is correct  
→ If using local network: make sure both devices are on the same WiFi

**No audio response**  
→ Check that your bot is configured with a voice/TTS in OpenClaw

**Questions?**  
→ Open an issue on [GitHub](https://github.com/JHAppsandBots/speak-with-claw-ios/issues)
