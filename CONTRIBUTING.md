# Contributing to Speak with Claw iOS

Thanks for your interest! This is a personal project, but contributions are welcome.

## How to contribute

- **Bug reports:** Open an issue with steps to reproduce
- **Feature requests:** Open an issue with use case description  
- **Pull requests:** Fork → branch → PR — please describe what and why

## Setup

See [XCODE_SETUP.md](XCODE_SETUP.md) for full Xcode setup.

## What you need on your Mac

| Component | What it does | Get it |
|-----------|-------------|--------|
| **OpenClaw** | AI bot gateway (runs on your Mac) | [openclaw.ai](https://openclaw.ai) |
| **Telegram Bot** | Your AI bot's identity | [@BotFather](https://t.me/BotFather) |
| **LLM API Key** | The AI brain | e.g. [Anthropic](https://console.anthropic.com) or [OpenAI](https://platform.openai.com) |
| **Google Cloud API Key** | STT (speech-to-text) + TTS (text-to-speech) | [console.cloud.google.com](https://console.cloud.google.com) — enable *Cloud Speech-to-Text* + *Text-to-Speech* APIs |
| **Tailscale** | Access your Mac from anywhere (optional but recommended) | [tailscale.com](https://tailscale.com) — free |
| **macOS 14+** | Required for the OpenClaw gateway | — |

## What you need on your iPhone

| Component | What it does | Notes |
|-----------|-------------|-------|
| **iOS 17+** | Required | — |
| **Tailscale** (optional) | Connect to your Mac outside home network | Free |
| This app | Voice interface | You're already here 😄 |

## Code style

- Swift standard conventions
- No third-party dependencies (pure Apple frameworks only)
- Keep it simple — this is a focused utility app

## What I'm NOT looking for

- App Store monetization changes
- UI redesigns without prior discussion
- Breaking changes to the relay server protocol

## Questions?

Open an issue — happy to discuss.
