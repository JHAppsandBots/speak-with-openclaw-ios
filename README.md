# Speak with Claw 🦞🎤

> A real hands-free conversation with your AI bot — like a phone call, not a form.

Speak with Claw is an iOS app that acts as a voice interface for Telegram bots running on [OpenClaw](https://openclaw.ai). You talk, the app automatically detects when you're done, your bot responds — audio plays instantly. No typing, no button holding, no hotword required.

---

> ⚠️ **Early Release** — This app works well enough for me to share, but it's not perfect. Expect rough edges, occasional bugs, and missing polish. If you find issues or want to improve it — PRs and feedback are very welcome.

---

## 🎯 The Most Practical Mode: Real Conversation (VAD)

**Conversation mode** is the recommended way to use the app — fully hands-free, no hotword, no button:

1. Activate conversation mode → app calibrates background noise for 2 seconds
2. Just talk — the app automatically distinguishes your voice from ambient noise
3. After a short pause: message is sent, bot responds with audio
4. Bot audio plays → you reply → real back-and-forth dialog

The app reliably separates speech from background noise (music, TV, street sounds). No button, no keyword, no friction.

---

## What the app does

- 🗣️ **Conversation mode (VAD)** — just talk, app detects start and end automatically ← **recommended**
- 🎤 **Push-to-talk** — hold button for full manual control
- 👂 **Hotword** — say "Hey Bot" as optional activation
- 🔊 **Auto-Play** — bot audio response plays immediately
- 📱 **Background mode** — works with screen locked (VoIP mode)
- ⚙️ **Adaptive silence detection** — intelligently detects pauses (adjustable 1–5s)
- 💬 **Conversation history** — all messages as chat

---

## What you need

Speak with Claw is a **voice interface**. You need a running AI bot in the background.

**Requirements:**
- iPhone (iOS 17+)
- Mac with macOS 14+
- [OpenClaw](https://openclaw.ai) — the AI bot gateway (free, open source)
- Telegram bot token — create one via [@BotFather](https://t.me/BotFather)
- LLM API Key — e.g. from [Anthropic](https://console.anthropic.com) or [OpenAI](https://platform.openai.com)
- Google Cloud API Key — for STT (speech-to-text) + TTS (text-to-speech), enable *Cloud Speech-to-Text* and *Text-to-Speech* APIs at [console.cloud.google.com](https://console.cloud.google.com)
- [Tailscale](https://tailscale.com) — **recommended** for access outside your home network (free)

---

## Setup

> **Architecture note:** Speak with Claw communicates directly with the OpenClaw gateway on your Mac (port 18800). The app sends audio to a local relay server, which calls the AI bot and streams back text + audio.

> **Recommendation: Tailscale** — for access outside your home network, [Tailscale](https://tailscale.com) is the easiest solution. Install on both Mac and iPhone → your Mac gets a fixed hostname → enter it in the app → works everywhere, no port forwarding needed.

### Step 1: Create a Telegram bot

1. Open Telegram → message @BotFather
2. Type `/newbot`
3. Give it a name
4. **Copy the bot token** — looks like: `1234567890:AABBccDDeeFFgg...`

### Step 2: Install OpenClaw

```bash
# Install OpenClaw (requires Node.js 18+)
npm install -g openclaw

# Initialize
openclaw init
```

### Step 3: Configure OpenClaw

Copy this example config to `~/.openclaw/openclaw.json` and adjust:

```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "YOUR-OWN-TOKEN"
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
        "name": "My Bot",
        "workspaceDir": "~/openclaw-workspace"
      }
    ]
  },
  "channels": {
    "telegram": {
      "streamMode": "off",
      "dmPolicy": "allowlist",
      "accounts": {
        "mybot": {
          "botToken": "YOUR-BOT-TOKEN-FROM-BOTFATHER",
          "dmPolicy": "allowlist",
          "allowFrom": ["YOUR-TELEGRAM-USER-ID"]
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
        "language": "en"
      }
    }
  }
}
```

**Find your Telegram user ID:**
- Message @userinfobot on Telegram → it replies with your ID

### Step 4: Configure TTS (Text-to-Speech)

**Recommended: Google Cloud TTS** (best quality, natural voice)

```bash
# Get a Google Cloud API Key at console.cloud.google.com
# Enable the Text-to-Speech API

# Add to openclaw.json under env.vars:
"env": {
  "vars": {
    "GOOGLE_API_KEY": "YOUR-GOOGLE-API-KEY"
  }
}
```

Available English voices:
- `en-US-Chirp3-HD-Aoede` — natural, warm (recommended)
- `en-US-Chirp3-HD-Charon` — clear, precise
- `en-US-Standard-A` — simple, free tier

### Step 5: Start OpenClaw

```bash
# Start as background service (macOS LaunchAgent)
openclaw gateway start

# Check status
openclaw gateway status
# → should show "running on port 18789"

# Test: message your Telegram bot
# → it should respond
```

### Step 6: Configure the app

1. Open Speak with Claw
2. Settings → enter your bot token
3. Enter your Telegram user ID
4. "Test connection" → ✅ Connected
5. Done — switch to Conversation mode and start talking

---

## Hotword customization

Default hotword is "Hey Bot". You can change it:

- In the app: Settings → Hotword field
- **Recommendation:** short, clear words like "hello", "hey bot", "hey [name]"
- ⚠️ **"OpenClaw"** may **not** work reliably — on-device speech recognition sometimes misrecognizes unknown brand names
- Hotword language is adjustable: Settings → Recognition language (matches the hotword language)

**Silence detection:**
- Settings → Silence slider
- 1s = very fast (short commands)
- 2s = recommended
- 5s = for longer sentences

---

## Multiple bots

You can configure multiple bots in OpenClaw and switch between them in the app:

```json
"accounts": {
  "assistant": {
    "botToken": "TOKEN-BOT-1",
    "allowFrom": ["YOUR-ID"]
  },
  "creative": {
    "botToken": "TOKEN-BOT-2",
    "allowFrom": ["YOUR-ID"]
  }
}
```

In the app: top left → select bot.

---

## Troubleshooting

**Bot doesn't respond:**
- Is OpenClaw running? → `openclaw gateway status`
- Is the bot token correct? → Connection test in the app
- Did you start the bot on Telegram? → Send `/start`

**No audio:**
- Is TTS configured? → Google API key set?
- Is `messages.tts.auto` set to `"inbound"`?

**Hotword doesn't react:**
- Speech recognition allowed? → iPhone Settings → Privacy → Speech Recognition
- On-device recognition available? → Requires iOS 16+

**App stops in background:**
- VoIP mode requires a real iPhone (not simulator)
- Simulate one phone call to let iOS recognize the app as VoIP

---

## Privacy

- **Hotword detection:** 100% on-device, no cloud upload
- **Voice recordings:** go only to your own Telegram bot
- **AI responses:** via your own API (Claude, GPT, Gemini, etc.) — you control everything
- No data is sent to the app developer

---

## License & Cost

- **App:** 24 hours free trial — then €6.99 one-time (App Store)
- **OpenClaw:** free (open source)
- **LLM API:** pay-per-use (e.g. ~€0.003 per message with Claude Sonnet)
- **Google TTS/STT:** free up to 1M characters/month
- **Telegram:** free

---

## Built by

J.H. — built with OpenClaw

*Questions, bugs, feature requests: GitHub Issues*

---

## App Store Description (Draft)

**Speak with Claw — Voice Interface for AI Bots**

Talk to your AI bots on Telegram — hands-free, like a real conversation.

Speak with Claw connects your iPhone to your own AI assistant running on your Mac. Just talk — the app automatically detects your voice, sends when you pause, and plays the bot's audio response. Real back-and-forth dialog, no button, no keyword, no friction.

**Features:**
• Conversation mode (VAD) — just talk, fully hands-free
• Hotword detection ("Hey Bot") — optional activation
• Automatic silence detection — no button needed
• Audio responses play instantly
• Background mode with screen locked
• Multiple bots selectable
• On-device speech recognition — no cloud upload

**Requirement:** OpenClaw on your Mac (free, open source, setup guide on GitHub)

**24 hours free — then €6.99 one-time.**

*Privacy: No data is sent to the developer. Everything runs on your own infrastructure.*
