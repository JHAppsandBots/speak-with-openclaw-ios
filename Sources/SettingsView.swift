import SwiftUI
import AudioToolbox

// MARK: - Localization Helper (App-Level)
func L(_ de: String, _ en: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "de"
    return lang == "en" ? en : de
}

struct SettingsView: View {

    @AppStorage("serverURL")        private var serverURL = "http://192.168.0.X:18800"
    @AppStorage("useGateway")       private var useGateway = true
    @AppStorage("relayToken")       private var relayToken = ""
    @AppStorage("hotword")          private var hotword = "hey bot"
    @AppStorage("listenMode")       private var listenModeRaw = "vad"
    @AppStorage("hotwordEnabled")   private var hotwordEnabled = false  // Legacy, nicht mehr direkt nutzen
    @AppStorage("silenceThreshold") private var silenceThreshold: Double = 2.0
    @AppStorage("hotwordLanguage")  private var hotwordLanguage = "de-DE"
    @AppStorage("appLanguage")      private var appLanguage = "de"

    @AppStorage("sendSoundID")       private var sendSoundID: Int = 1114  // Bloom 🌸
    @AppStorage("cueBeforeReply")    private var cueBeforeReply = false   // kurzer Ton vor der Bot-Antwort
    @AppStorage("vadPauseHotword")   private var vadPauseHotword = "aufnahme pause"
    @AppStorage("vadResumeHotword")  private var vadResumeHotword = "aufnahme weiter"

    private struct SoundOption { let id: Int; let label: String }

    private let sendSoundOptions: [SoundOption] = [
        SoundOption(id: -999, label: "🔇 Kein Ton"),
        SoundOption(id: 1114, label: "🌸 Bloom — weiches Pad"),
        SoundOption(id: 1057, label: "Tink — kurzer Klick"),
        SoundOption(id: 1117, label: "Descent — abfallend"),
        SoundOption(id: 1003, label: "iMessage Swoosh"),
        SoundOption(id: 1016, label: "Tweet"),
        SoundOption(id: 1256, label: "Heller Pip"),
    ]

    private let availableLanguages: [(code: String, label: String)] = [
        ("de-DE", "🇩🇪 Deutsch (Deutschland)"),
        ("de-AT", "🇦🇹 Deutsch (Österreich)"),
        ("de-CH", "🇨🇭 Deutsch (Schweiz)"),
        ("en-US", "🇺🇸 English (US)"),
        ("en-GB", "🇬🇧 English (UK)"),
        ("en-AU", "🇦🇺 English (Australia)"),
        ("fr-FR", "🇫🇷 Français"),
        ("es-ES", "🇪🇸 Español"),
        ("it-IT", "🇮🇹 Italiano"),
        ("nl-NL", "🇳🇱 Nederlands"),
        ("pl-PL", "🇵🇱 Polski"),
        ("pt-BR", "🇧🇷 Português (Brasil)"),
        ("ja-JP", "🇯🇵 日本語"),
        ("zh-CN", "🇨🇳 中文 (简体)"),
    ]

    @State private var testResult: String?
    @State private var isTesting = false
    @State private var restartResult: String?
    @State private var isRestarting = false
    @State private var isRestartingRelay = false
    @State private var showDeleteConfirmation = false

    var onSave: (() -> Void)?
    var onClearChats: (() -> Void)?

    var body: some View {
        Form {
            // MARK: - Sprache / Language
            Section(L("Sprache", "Language")) {
                Picker(L("Sprache / Language", "Language / Sprache"), selection: $appLanguage) {
                    Text("🇩🇪 Deutsch").tag("de")
                    Text("🇬🇧 English").tag("en")
                }
                .pickerStyle(.segmented)

                Text(L("App-Sprache für Menüs und Beschriftungen.", "App language for menus and labels."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Server
            Section(L("Mac-Server", "Mac Server")) {
                TextField(L("Server URL", "Server URL"), text: $serverURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .font(.system(.body, design: .monospaced))

                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? L("Teste...", "Testing...") : L("Verbindung testen", "Test connection"))
                    }
                }
                .disabled(serverURL.isEmpty || isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✅") ? .green : .red)
                }

                Text(L("💡 Im Heimnetz: http://<Mac-IP>:18800 — Von überall: Tailscale-IP nutzen (optional).",
                        "💡 Home network: http://<Mac-IP>:18800 — Everywhere: use Tailscale IP (optional)."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Verbindungs-Modus (direkt übers Gateway vs. Telegram)
            Section(L("Verbindung", "Connection")) {
                Picker(L("Pfad", "Path"), selection: $useGateway) {
                    Text(L("Direkt übers Gateway (schnell)", "Direct via gateway (fast)")).tag(true)
                    Text(L("Über Telegram (klassisch)", "Via Telegram (classic)")).tag(false)
                }
                Text(useGateway
                     ? L("⚡️ ~5–12 s · Persona + Gedächtnis · ohne Telegram-Umweg",
                         "⚡️ ~5–12 s · persona + memory · no Telegram detour")
                     : L("🐢 ~15–22 s · klassischer Telegram-Weg (Fallback)",
                         "🐢 ~15–22 s · classic Telegram path (fallback)"))
                    .font(.caption2).foregroundStyle(.secondary)

                SecureField(L("Relay-Token (Sicherheit)", "Relay token (security)"), text: $relayToken)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
                Text(L("🔒 Muss zum Token auf dem Mac passen (.env.voice-relay). Schützt deine Endpoints vor Fremdzugriff.",
                       "🔒 Must match the token on the Mac (.env.voice-relay). Protects your endpoints from unauthorized access."))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // MARK: - Bots neu starten
            Section(L("Bot-Verwaltung", "Bot Management")) {
                Button {
                    Task { await restartBots() }
                } label: {
                    HStack {
                        if isRestarting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        Text(isRestarting ? L("Bots werden neu gestartet...", "Restarting bots...") : L("Alle Bots neu starten", "Restart all bots"))
                    }
                }
                .disabled(serverURL.isEmpty || isRestarting)

                if let result = restartResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✅") ? .green : .red)
                }


                Button {
                    Task { await restartRelay() }
                } label: {
                    HStack {
                        if isRestartingRelay {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.blue)
                        }
                        Text(isRestartingRelay ? L("Relay wird neu gestartet...", "Restarting relay...") : L("Voice-Relay neu starten", "Restart Voice Relay"))
                    }
                }
                .disabled(serverURL.isEmpty || isRestartingRelay)

                Text(L("Startet die Bots bzw. das Voice-Relay auf dem Mac-Server neu.",
                        "Restarts the bots or the Voice Relay on the Mac server."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section(L("Hör-Modus", "Listen Mode")) {
                // 3-Wege-Auswahl: Aus / Hotword / Gesprächsmodus
                Picker(L("Modus", "Mode"), selection: $listenModeRaw) {
                    Label(L("Aus", "Off"),          systemImage: "mic.slash")       .tag("off")
                    Label(L("Hotword", "Hotword"),  systemImage: "waveform")        .tag("hotword")
                    Label(L("Gespräch", "Converse"), systemImage: "person.wave.2") .tag("vad")
                }
                .pickerStyle(.segmented)

                switch listenModeRaw {
                case "hotword":
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Aktivierungswort", "Activation word"))
                            .font(.caption).foregroundStyle(.secondary)
                        TextField(L("z.B. hey bot", "e.g. hey bot"), text: $hotword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Text(L("💡 Kurze, klare Wörter. z.B. \"hey bot\", \"hallo\".",
                               "💡 Short, clear words. e.g. \"hey bot\", \"hello\"."))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                case "vad":
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Gesprächsmodus — App hört automatisch zu und erkennt wenn du sprichst.",
                               "Conversation mode — App listens automatically and detects when you speak."))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(L("• Kalibrierung: 2s still halten beim Aktivieren\n• Hintergrundgeräusche: App verwirft Aufnahmen ohne erkanntes Wort\n• Button funktioniert immer zusätzlich",
                               "• Calibration: stay quiet for 2s when activating\n• Background noise: App discards recordings with no detected word\n• Button always works too"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Pause-Hotword", "Pause hotword"))
                            .font(.caption).foregroundStyle(.secondary)
                        TextField(L("z.B. aufnahme pause", "e.g. recording pause"), text: $vadPauseHotword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Text(L("Resume-Hotword", "Resume hotword"))
                            .font(.caption).foregroundStyle(.secondary)
                        TextField(L("z.B. aufnahme weiter", "e.g. recording resume"), text: $vadResumeHotword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Text(L("💡 Sprich das Pause-Wort um Senden zu stoppen, das Resume-Wort um fortzufahren.",
                               "💡 Speak the pause word to stop sending, the resume word to continue."))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                default:
                    Text(L("Manuell: Taste drücken und halten zum Sprechen.",
                           "Manual: press and hold to speak."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                if listenModeRaw != "off" {
                    // Sprache (für Hotword + VAD gleich)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Erkennungs-Sprache", "Recognition language"))
                            .font(.caption).foregroundStyle(.secondary)
                        Picker(L("Sprache", "Language"), selection: $hotwordLanguage) {
                            ForEach(availableLanguages, id: \.code) { lang in
                                Text(lang.label).tag(lang.code)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Stille-Erkennung (für Hotword + VAD)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L("Stille-Pause vor Senden", "Silence before send"))
                            Spacer()
                            Text(String(format: L("%.0f Sek", "%.0f sec"), silenceThreshold))
                                .foregroundStyle(.blue)
                                .fontWeight(.medium)
                        }
                        Slider(value: $silenceThreshold, in: 1...5, step: 0.5)
                            .tint(.blue)
                        HStack {
                            Text(L("1 Sek", "1 sec")); Spacer(); Text(L("5 Sek", "5 sec"))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - Absende-Sound (Aufnahme endet)
            Section {
                ForEach(sendSoundOptions, id: \.id) { s in
                    Button {
                        sendSoundID = s.id
                        UserDefaults.standard.set(s.id, forKey: "sendSoundID")
                        if s.id != -999 { AudioServicesPlaySystemSound(SystemSoundID(s.id)) }
                    } label: {
                        HStack {
                            Image(systemName: sendSoundID == s.id
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(sendSoundID == s.id ? .orange : .secondary)
                            Text(s.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "play.circle")
                                .foregroundStyle(.orange.opacity(0.6))
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text(L("📤 Absende-Sound (Aufnahme endet)", "📤 Send sound (recording ends)"))
            } footer: {
                Text(L("Antippen = anhören & auswählen.", "Tap = preview & select."))
            }

            // MARK: - Hinweis-Ton vor der Antwort
            Section {
                Toggle(isOn: $cueBeforeReply) {
                    Text(L("Ton vor der Antwort", "Cue before reply"))
                }
                .tint(.orange)
                Button {
                    AudioServicesPlaySystemSound(SystemSoundID(1113))  // Vorhören des Hinweis-Tons
                } label: {
                    Label(L("Ton anhören", "Preview cue"), systemImage: "play.circle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(L("🔔 Hinweis-Ton", "🔔 Cue sound"))
            } footer: {
                Text(L("Spielt kurz bevor die Bot-Stimme losredet — damit du nicht erschrickst. Aus = wie gehabt, keine zusätzliche Verzögerung.",
                       "Plays right before the bot's voice starts — so it doesn't startle you. Off = unchanged, no extra delay."))
            }

            // MARK: - Chatverläufe löschen
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(L("Alle Chatverläufe löschen", "Delete all chat histories"))
                    }
                }
                .alert(
                    L("Chatverläufe löschen?", "Delete chat histories?"),
                    isPresented: $showDeleteConfirmation
                ) {
                    Button(L("Abbrechen", "Cancel"), role: .cancel) { }
                    Button(L("Löschen", "Delete"), role: .destructive) {
                        onClearChats?()
                    }
                } message: {
                    Text(L("Alle gespeicherten Chatverläufe werden unwiderruflich gelöscht.",
                           "All saved chat histories will be permanently deleted."))
                }
            } footer: {
                Text(L("Löscht alle Chat-Nachrichten bei allen Bots.", "Deletes all chat messages for all bots."))
            }

        }
        .navigationTitle(L("Einstellungen", "Settings"))
        .onDisappear {
            onSave?()
        }
    }


    private func restartRelay() async {
        isRestartingRelay = true
        restartResult = nil

        guard let url = URL(string: "\(serverURL)/restart-relay") else {
            restartResult = L("❌ Server-URL ungültig", "❌ Invalid server URL")
            isRestartingRelay = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        if !relayToken.isEmpty { request.setValue("Bearer \(relayToken)", forHTTPHeaderField: "Authorization") }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                restartResult = L("❌ Ungültige Antwort", "❌ Invalid response")
                isRestartingRelay = false
                return
            }
            if http.statusCode == 200 {
                restartResult = L("✅ Voice-Relay wird neu gestartet!", "✅ Voice relay restarting!")
            } else {
                restartResult = L("❌ Fehler (HTTP \(http.statusCode))", "❌ Error (HTTP \(http.statusCode))")
            }
        } catch {
            restartResult = "❌ \(error.localizedDescription)"
        }
        isRestartingRelay = false
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        // /bots prüft Erreichbarkeit UND den Token (401 = falscher Token)
        var ok = false
        if let url = URL(string: "\(serverURL)/bots") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            if !relayToken.isEmpty { req.setValue("Bearer \(relayToken)", forHTTPHeaderField: "Authorization") }
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse {
                if http.statusCode == 401 {
                    testResult = L("🔒 Token falsch — Relay-Token prüfen", "🔒 Wrong token — check relay token")
                    isTesting = false
                    return
                }
                ok = (http.statusCode == 200)
            }
        }
        testResult = ok
            ? L("✅ Server erreichbar (Token ok)", "✅ Server reachable (token ok)")
            : L("❌ Nicht erreichbar — gleiches WLAN/Tailscale?", "❌ Not reachable — same WiFi/Tailscale?")
        isTesting = false
    }

    private func restartBots() async {
        isRestarting = true
        restartResult = nil

        guard let url = URL(string: "\(serverURL)/restart-bots") else {
            restartResult = L("❌ Server-URL ungültig", "❌ Invalid server URL")
            isRestarting = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        if !relayToken.isEmpty { request.setValue("Bearer \(relayToken)", forHTTPHeaderField: "Authorization") }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                restartResult = L("❌ Ungültige Antwort", "❌ Invalid response")
                isRestarting = false
                return
            }
            if http.statusCode == 200 {
                if let json = try? JSONDecoder().decode([String: Bool].self, from: data), json["ok"] == true {
                    restartResult = L("✅ Alle Bots neu gestartet!", "✅ All bots restarted!")
                } else {
                    restartResult = L("✅ Server hat geantwortet", "✅ Server responded")
                }
            } else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                restartResult = L("❌ Fehler (\(http.statusCode)): \(msg)", "❌ Error (\(http.statusCode)): \(msg)")
            }
        } catch {
            restartResult = L("❌ \(error.localizedDescription)", "❌ \(error.localizedDescription)")
        }
        isRestarting = false
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
