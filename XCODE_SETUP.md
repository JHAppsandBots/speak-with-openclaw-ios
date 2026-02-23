# BotVoice — Xcode Setup

## Neues Projekt erstellen

1. Xcode öffnen → "Create New Project"
2. iOS → App
3. Name: `BotVoice`
4. Team: dein Apple Developer Account
5. Bundle ID: `de.JHAppsandBots.botvoice`
6. Interface: SwiftUI
7. Language: Swift
8. Speichern in: `_App Entwicklung/BotVoice/`

## Dateien hinzufügen

Diese Dateien aus diesem Ordner in das Xcode-Projekt ziehen:
- `TelegramService.swift`
- `AudioService.swift`
- `MainView.swift`
- `Models.swift`
- `SettingsView.swift`
- `BotSelectView.swift`

## Info.plist Permissions

Im Xcode-Projekt unter "Info" diese Keys hinzufügen:

```
NSMicrophoneUsageDescription → "BotVoice braucht das Mikrofon um deine Sprachnachrichten aufzunehmen"
NSLocalNetworkUsageDescription → "Für lokale Bot-Verbindungen"
```

## Capabilities

Im "Signing & Capabilities" Tab:
- "Background Modes" hinzufügen → "Audio, AirPlay, and Picture in Picture" aktivieren
- (Phase 2): "Voice over IP" aktivieren für Hotword im Hintergrund

## App Entry Point

`BotVoiceApp.swift` (wird von Xcode erstellt):
```swift
import SwiftUI

@main
struct BotVoiceApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
```

## Testen

1. Simulator: funktioniert für UI, aber KEIN echtes Mikrofon
2. Echtes iPhone: Xcode → Gerät auswählen → Run
3. Erstes Mal: Auf dem iPhone unter Einstellungen → Datenschutz → Mikrofon → BotVoice erlauben

## Was noch fehlt (TODO)

- [ ] Onboarding-Flow (erster Start → erklärt Setup)
- [ ] Persistenz: Bots in UserDefaults speichern
- [ ] Besseres Error-Handling
- [ ] Loading-Spinner während API-Call
- [ ] Haptic Feedback
- [ ] App-Icon
- [ ] Phase 2: Hotword (CallKit + CoreML)

---
_Stand: 19.02.2026_
