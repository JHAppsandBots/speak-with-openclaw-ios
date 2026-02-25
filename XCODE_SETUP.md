# Speak with Claw — Xcode Setup

## Requirements

- macOS 14+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

---

## Build the project

```bash
# Clone the repo
git clone https://github.com/JHAppsandBots/speak-with-claw-ios.git
cd speak-with-claw-ios

# Generate the Xcode project
xcodegen generate

# Open in Xcode
open BotVoice.xcodeproj
```

---

## Configure signing

1. Open Xcode → **Signing & Capabilities**
2. Select your **Development Team**
3. Set your own **Bundle Identifier** (e.g. `com.yourname.speakwithclaw`)

---

## Permissions (already in Info.plist)

- Microphone — for voice recording
- Speech Recognition — for hotword detection

---

## Run on device

1. Connect your iPhone via USB
2. Select it as the target in Xcode
3. Hit **Run** (⌘R)
4. On first launch: grant Microphone and Speech Recognition permissions

> ⚠️ The simulator does not have a real microphone. Test on a real device.

---

## File structure

```
Sources/         ← Source of truth (edit these)
*.swift          ← Copies used by Xcode build (sync with Sources/)
project.yml      ← XcodeGen config
```

After editing files in `Sources/`, copy them to root and regenerate:

```bash
cp Sources/*.swift .
xcodegen generate
```

---

## Troubleshooting

**Build fails after pulling:**
```bash
xcodegen generate
```

**App won't run in background (no VoIP):**
- Background Modes must include `audio` and `voip` in Info.plist
- Test on a real device, not simulator
