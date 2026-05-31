# Latency — where the time actually goes (measured)

**Updated: 2026-05-31.** Concerns: "I speak → reply (transcript + text + audio)". An earlier version of
this doc guessed *host machine load (iCloud/Spotlight)* as the main cause — that was wrong (a transient
measurement artefact). The real breakdown, measured stage by stage:

## The components are fast — the agent runtime was the bottleneck

| Stage | Time | Bottleneck? |
|---|---|---|
| Gemini LLM (direct, trivial prompt) | ~0.7 s | no |
| Google STT (`latest_short`) | ~1.1 s | no |
| Google TTS (reply audio) | ~0.6 s | no |
| OpenClaw agent turn (warm) | **21 s → 5 s** | yes — **fixed by updating OpenClaw** |
| Telegram transport (poll pickup + reply delivery) | **~44 s → small** | yes — fixed by the same update |
| Node memory / gateway restart | — | no (RSS ~500 MB; a restart makes the first turn *slower* via cold start) |

## What fixed it

**Update the OpenClaw gateway to the latest version.** The version jump (here 2026.5.22 → 2026.5.28)
made cold/warm agent turns much faster and — crucially — **separated the user-facing reply from slow
follow-up work**, so the reply is delivered immediately instead of waiting. Measured: a real round-trip
dropped from ~80 s to ~15 s, and the direct agent turn from 21 s to 3–5 s — **with the full rich agent
(persona + memory) intact**.

```
npm i -g openclaw@latest      # then restart the gateway; verify /health = 200 and your bots start
```
Keep a backup of `openclaw.json` first; you can roll back with `npm i -g openclaw@<previous-version>`.

## How to diagnose your own latency (microscopically)

1. **Time the LLM alone** — `curl` Gemini's `generateContent` directly. If it's ~1 s, the model is fine.
2. **Time the agent alone** — `openclaw agent --agent <id> --message "test" --json` runs one turn via the
   gateway **without** the chat transport. This isolates agent overhead from Telegram transport.
3. **Compare to the full path** (through Telegram/the relay). The difference is pure transport overhead.
4. Check the gateway log during one request — if it's silent for tens of seconds, the time is inside an
   opaque step (agent turn or transport), not the LLM.

## ✅ Built (v1.0.3): direct path + toggle + auth

- **Direct agent path for voice — shipped.** New relay endpoint **`/talk`**: STT →
  `openclaw agent --agent <id> --message <transcript> --json` directly via the gateway (no chat channel)
  → Google TTS (per-bot voice) → `{transcript, text, audio}`. With a gateway retry + an automatic
  Telegram fallback (for bots that reply out-of-band via their own TTS tool) → you always get a reply.
  Measured ~5–12 s vs. ~15–22 s via the chat channel. **App toggle:** Settings → Connection.
- **Security — shipped.** Bearer-token auth on all relay endpoints except `/health`; the app sends the token.

## Going further (optional)

- **Gemini context caching** (implicit on 2.5+): a large recurring system prompt is cached → no
  re-processing per call.
- **Gemini Live API**: native bidirectional audio (no STT/TTS wrapper), sub-second.
- **Streaming pipeline** (STT partial → LLM stream → sentence-wise TTS): ~800 ms time-to-first-audio.

> The app itself does not add latency — it waits for the backend. Optimize the gateway/agent path first.
