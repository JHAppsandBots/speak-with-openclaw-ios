import SwiftUI
import AudioToolbox

// MARK: - Localization Helper (App-Level)
func L(_ de: String, _ en: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    return lang == "en" ? en : de
}

struct SettingsView: View {

    @AppStorage("serverURL")        private var serverURL = "http://192.168.0.X:18800"
    @AppStorage("hotword")          private var hotword = "hey bot"
    @AppStorage("listenMode")       private var listenModeRaw = "vad"
    @AppStorage("hotwordEnabled")   private var hotwordEnabled = false  // Legacy, nicht mehr direkt nutzen
    @AppStorage("silenceThreshold") private var silenceThreshold: Double = 2.0
    @AppStorage("hotwordLanguage")  private var hotwordLanguage = "en-US"
    @AppStorage("appLanguage")      private var appLanguage = "en"

    @AppStorage("sendSoundID")       private var sendSoundID: Int = 1114  // Bloom 🌸
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

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let service = RelayService(serverURL: serverURL, botUsername: "")
        let ok = await service.checkHealth()
        testResult = ok
            ? L("✅ Server erreichbar", "✅ Server reachable")
            : L("❌ Nicht erreichbar — gleiches WLAN?", "❌ Not reachable — same WiFi?")
        isTesting = false
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
