# Architektur-Entscheidungen — Speak with Claw

**Letztes Update:** 30.05.2026, 22:20 Uhr
**Zweck:** WHY statt WHAT — warum diese Technologien und Strukturen gewählt wurden.

---

## Warum native SwiftUI (kein React Native / Expo)?
**Entscheidung:** 100 % SwiftUI + Apple-Frameworks, keine Fremd-Dependencies.
**Grund:** Zuverlässiger Hardware-Audio-Zugriff (AVAudioEngine, Aufnahme + Wiedergabe), echte
Background-Modi (`audio`, `voip`), On-Device-Spracherkennung (`SFSpeechRecognizer`). Das ist mit
Cross-Platform-Stacks nicht stabil genug.
**Trade-off:** iOS-only, dafür robust und wartungsarm (keine npm-Supply-Chain).

## Warum `AudioSessionManager` als Single Source of Truth?
**Entscheidung:** Genau **eine** Stelle ruft `setCategory(...)` auf (beim App-Start), danach nie wieder.
**Grund:** iOS evaluiert die Audio-Route nur bei `setCategory`. Wenn mehrere Services die Session
umkonfigurieren, springt die Route (Kopfhörer ↔ Lautsprecher) und es knackt/bricht ab. Eine einmalige
Konfiguration + nur `setActive` hält die Route stabil. Alle Services (VAD, Hotword, Aufnahme, Playback)
nutzen `AudioSessionManager.shared`.

## Warum VAD (Voice Activity Detection) als Hauptmodus?
**Entscheidung:** Gesprächsmodus (VAD) ist Default, Hotword + Push-to-Talk sind Alternativen.
**Grund:** Freihändig ohne Schlüsselwort; die App kalibriert 2 s Umgebungslärm und erkennt dann
Sprechanfang/-ende selbst. `AVAudioEngine` wird nach jedem Zyklus frisch instanziiert (bekannter
iOS-Bug: Engine startet nach vollem Stop nicht zuverlässig neu).

## Warum Relay über OpenClaw statt Telegram direkt?
**Entscheidung:** Die App spricht mit einem lokalen Voice-Relay auf dem Mac (Port 18800), nicht mit der Telegram-API.
**Grund:** Kein Bot-Token im Client (Sicherheit), der Mac antwortet als der echte Account über OpenClaw,
STT/TTS (Google) laufen serverseitig. Die App bleibt dünn und enthält keine Secrets.
**Erreichbarkeit:** Heimnetz-IP oder Tailscale (empfohlen, von überall).

## Warum XcodeGen (`project.yml`)?
**Entscheidung:** Das `.xcodeproj` wird aus `project.yml` generiert; `project.yml` ist die Wahrheit.
**Grund:** Vermeidet `project.pbxproj`-Merge-Konflikte. `fastlane release` ruft vorher `xcodegen generate`.
**Wichtig (Lektion 30.05.2026):** Quellen liegen unter `sources: [Sources]` → **nur `Sources/` wird gebaut**.
Es gab historisch doppelte `.swift` im Repo-Root, die ignoriert wurden → neueste Edits liefen nicht im Build.
Konsolidiert: eine Quelle in `Sources/`.

---

## Bekannte Technical Debt / History
- **Bundle-ID-Altlast:** früher `de.johanneshahn.heyopenclaw` (uralter Name „Hey OpenClaw"); seit 30.05.2026
  korrekt `de.johanneshahn.speakwithopenclaw` (passend zu App Store Connect + fastlane Appfile).
- **Umbenennung:** „Speak with OpenClaw" → „Speak with Claw" (App-Store-Compliance). Display-Name jetzt konsistent.
- Public-Repo (`speak-with-claw-ios`) = veröffentlichte/bereinigte Version; Arbeitskopie = `BotVoice_Privat`
  (Repo `speak-with-claw-ios`).
