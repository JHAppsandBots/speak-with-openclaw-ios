import SwiftUI
import AVFoundation
import Combine

/// Haupt-Screen der BotVoice App
struct MainView: View {
    
    @StateObject private var viewModel: MainViewModel
    @State private var showConversation = false
    @State private var showSettings = false
    
    init(voipService: VoIPService, hotwordService: HotwordService) {
        _viewModel = StateObject(wrappedValue: MainViewModel(
            voipService: voipService,
            hotwordService: hotwordService
        ))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {

                    // MARK: — Top: Bot-Name + Status (kompakt)
                    VStack(spacing: 4) {
                        Text(viewModel.selectedBot?.name ?? L("Kein Bot", "No Bot"))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        HStack(spacing: 10) {
                            Label(
                                viewModel.isConnected ? L("Verbunden", "Connected") : L("Nicht konfiguriert", "Not configured"),
                                systemImage: viewModel.isConnected ? "checkmark.circle.fill" : "xmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(viewModel.isConnected ? .green : .gray)
                            switch viewModel.listenMode {
                            case .hotword:
                                Label(
                                    viewModel.hotwordService.isListening ? L("Hört zu", "Listening") : L("Hotword aus", "Hotword off"),
                                    systemImage: viewModel.hotwordService.isListening ? "ear.fill" : "ear.trianglebadge.exclamationmark"
                                )
                                .font(.caption)
                                .foregroundStyle(viewModel.hotwordService.isListening ? .blue : .gray)
                            case .vad:
                                Label(
                                    viewModel.vadIsCalibrating ? L("Kalibriere...", "Calibrating...") :
                                    viewModel.vadIsRecording   ? L("Aufnahme", "Recording") :
                                    viewModel.vadIsActive      ? L("Gesprächsmodus", "Conversation") : L("VAD aus", "VAD off"),
                                    systemImage: viewModel.vadIsRecording ? "waveform" :
                                                 viewModel.vadIsActive    ? "ear.fill"  : "ear.trianglebadge.exclamationmark"
                                )
                                .font(.caption)
                                .foregroundStyle(viewModel.vadIsRecording ? .red :
                                                 viewModel.vadIsActive    ? .green  : .gray)
                            case .off:
                                EmptyView()
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    // MARK: — Mitte: Button + Status-Text (kompakt, feste Höhe)
                    VStack(spacing: 8) {
                        // Status + Hotword-Hinweis ÜBER dem Button
                        VStack(spacing: 3) {
                            Text(viewModel.statusText)
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .animation(.easeInOut(duration: 0.25), value: viewModel.statusText)
                            if viewModel.listenMode == .hotword {
                                Text(L("oder sag \"\(viewModel.hotwordService.hotword)\"",
                                       "or say \"\(viewModel.hotwordService.hotword)\""))
                                    .font(.caption2)
                                    .foregroundStyle(.blue.opacity(0.7))
                            } else if viewModel.listenMode == .vad && viewModel.vadIsActive && !viewModel.vadIsCalibrating {
                                Text(L("Sprich einfach — ich höre zu", "Just speak — I'm listening"))
                                    .font(.caption2)
                                    .foregroundStyle(.green.opacity(0.7))
                            }
                        }

                        // Mikrofon-Button (kleiner)
                        ZStack {
                            if isActivelyRecording || viewModel.isPlaying || viewModel.vadIsActive || viewModel.hotwordService.isListening {
                                ForEach(0..<3, id: \.self) { i in
                                    Circle()
                                        .stroke(pulseColor.opacity(0.3 - Double(i) * 0.08), lineWidth: 1.5)
                                        .frame(width: 120 + CGFloat(i * 50), height: 120 + CGFloat(i * 50))
                                        .scaleEffect(viewModel.pulseScale)
                                        .animation(
                                            .easeInOut(duration: isActivelyRecording ? 0.6 : 1.2)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(i) * 0.2),
                                            value: viewModel.pulseScale
                                        )
                                }
                            }
                            Circle()
                                .fill(buttonGradient)
                                .frame(width: 120, height: 120)
                                .overlay {
                                    Image(systemName: buttonIcon)
                                        .font(.system(size: 48, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: pulseColor.opacity(0.45), radius: 30, y: 8)
                                .scaleEffect(isActivelyRecording ? 1.1 : 1.0)
                                .animation(.spring(duration: 0.25), value: isActivelyRecording)
                        }
                        .frame(height: 180)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !viewModel.isRecording && !viewModel.isPlaying {
                                        viewModel.startRecording()
                                    }
                                }
                                .onEnded { _ in
                                    if viewModel.isRecording {
                                        viewModel.stopAndSend()
                                    }
                                }
                        )
                    }
                    
                    // MARK: — Unten: Transkript + Antwort + Vorschläge
                    if viewModel.lastUserTranscript != nil || viewModel.lastResponseText != nil {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                // User-Transkript
                                if let transcript = viewModel.lastUserTranscript {
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("🎤")
                                            .font(.caption)
                                        Text(transcript)
                                            .font(.callout)
                                            .foregroundStyle(.gray)
                                            .italic()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }

                                // Bot-Antwort
                                if let response = viewModel.lastResponseText {
                                    Text(response)
                                        .font(.callout)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                // Vorschläge
                                if !viewModel.suggestions.isEmpty {
                                    ForEach(viewModel.suggestions, id: \.self) { s in
                                        Button {
                                            viewModel.sendTextToBot(text: s)
                                        } label: {
                                            Text(s)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .background(Color.indigo.opacity(0.25))
                                                .clipShape(.rect(cornerRadius: 12))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.indigo.opacity(0.5), lineWidth: 1)
                                                )
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Color(white: 0.12).cornerRadius(18))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 4)
                
                // Fehler
                if let error = viewModel.errorMessage {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.85))
                        .clipShape(.capsule)
                        .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: BotSelectView(selectedBot: $viewModel.selectedBot)) {
                        HStack(spacing: 4) {
                            Text(viewModel.selectedBot?.emoji ?? "🤖")
                                .font(.title3)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 18) {
                        // Hör-Modus Toggle (Off → Hotword → Gespräch → Off)
                        Button {
                            let next: MainViewModel.ListenMode
                            switch viewModel.listenMode {
                            case .off:     next = .hotword
                            case .hotword: next = .vad
                            case .vad:     next = .off
                            }
                            viewModel.setListenMode(next)
                        } label: {
                            Image(systemName: {
                                switch viewModel.listenMode {
                                case .off:     return "ear.trianglebadge.exclamationmark"
                                case .hotword: return "ear.fill"
                                case .vad:     return "person.wave.2.fill"
                                }
                            }())
                            .foregroundStyle({
                                switch viewModel.listenMode {
                                case .off:     return Color.gray
                                case .hotword: return Color.blue
                                case .vad:     return Color.green
                                }
                            }())
                        }
                        
                        // Verlauf
                        Button { showConversation = true } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundStyle(.white)
                        }
                        
                        // Settings
                        NavigationLink(destination: SettingsView(onSave: { viewModel.reloadConfig() }, onClearChats: { viewModel.clearAllChats() })) {
                            Image(systemName: "gear")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showConversation) {
            NavigationStack {
                ConversationView(messages: viewModel.messages) { text in
                    viewModel.sendTextToBot(text: text)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("Fertig", "Done")) { showConversation = false }
                    }
                }
            }
        }
        .task { await viewModel.setup() }
        .animation(.easeInOut(duration: 0.3), value: viewModel.lastResponseText)
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
        .animation(.easeInOut(duration: 0.15), value: viewModel.showHotwordFlash)
    }
    
    /// True when confirmed speech is being recorded
    /// Button press = always red; VAD = only red after speech validated
    private var isActivelyRecording: Bool {
        if viewModel.listenMode == .vad {
            return viewModel.vadIsRecording && viewModel.vadHasValidatedSpeech
        }
        return viewModel.isRecording
    }

    private var pulseColor: Color {
        if isActivelyRecording { return .red }
        if viewModel.isPlaying { return .cyan }
        if viewModel.vadIsActive { return .blue }
        if viewModel.hotwordService.isListening { return .blue }
        return .indigo
    }
    
    private var buttonGradient: LinearGradient {
        LinearGradient(
            colors: isActivelyRecording   ? [.red, .red] :
                    viewModel.isPlaying    ? [.blue, .cyan]  :
                    viewModel.vadIsActive   ? [.indigo, .blue] :
                    viewModel.hotwordService.isListening ? [.indigo, .blue] :
                    [.indigo, .purple],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    
    private var buttonIcon: String {
        if isActivelyRecording { return "waveform" }
        if viewModel.isPlaying   { return "speaker.wave.3.fill" }
        if viewModel.vadIsActive  { return "ear.fill" }
        if viewModel.hotwordService.isListening { return "ear.fill" }
        return "mic.fill"
    }
}

// MARK: - ViewModel

@MainActor
class MainViewModel: ObservableObject {
    
    // MARK: - Published
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var statusText = L("Halten zum Sprechen", "Hold to speak")
    @Published var lastResponseText: String?
    @Published var lastUserTranscript: String?
    @Published var suggestions: [String] = []
    // Pro Bot: eigener Verlauf + letzte Antwort
    private var botMessages: [UUID: [Message]] = ChatHistory.loadAll()
    private var botLastResponse: [UUID: String] = [:]
    private var botSuggestions: [UUID: [String]] = [:]
    @Published var errorMessage: String?
    @Published var selectedBot: Bot? {
        didSet {
            // Alten Bot-Stand sichern
            if let old = oldValue {
                botMessages[old.id] = messages
                if let r = lastResponseText { botLastResponse[old.id] = r }
                botSuggestions[old.id] = suggestions
            }
            // Neuen Bot-Stand laden
            if let new = selectedBot {
                messages = botMessages[new.id] ?? []
                lastResponseText = botLastResponse[new.id]
                suggestions = botSuggestions[new.id] ?? []
            }
            saveBot()
            updateService()
        }
    }
    @Published var pulseScale: CGFloat = 1.0
    @Published var isConnected = false
    @Published var messages: [Message] = [] {
        didSet { persistChats() }
    }
    // Drei Hör-Modi: aus / Hotword / VAD (Gesprächsmodus)
    enum ListenMode: String { case off, hotword, vad }

    @Published var listenMode: ListenMode = .vad
    @Published var showHotwordFlash = false

    // hotwordEnabled als computed var → kein Break im restlichen Code
    var hotwordEnabled: Bool { listenMode == .hotword }

    // VAD-States als computed properties → kein SwiftUI-Binding-Problem
    var vadIsActive:      Bool { vadService.isActive }
    var vadIsCalibrating: Bool { vadService.isCalibrating }
    var vadIsRecording:   Bool { vadService.isRecording }
    var vadHasValidatedSpeech: Bool { vadService.hasValidatedSpeech }

    // MARK: - Services
    let hotwordService: HotwordService
    @Published var vadService = VADService()
    private var vadCancellable: AnyCancellable?   // leitet vadService-Updates an View weiter
    private let voipService: VoIPService
    private let audioService = AudioService()
    private let silenceDetector = SilenceDetector()
    private var relayService: RelayService?

    @AppStorage("silenceThreshold") private var silenceThreshold: Double = 2.0
    @AppStorage("serverURL") private var serverURL: String = "http://192.168.0.X:18800"
    
    init(voipService: VoIPService, hotwordService: HotwordService) {
        self.voipService = voipService
        self.hotwordService = hotwordService
        
        // Hotword → Aufnahme starten
        hotwordService.onHotwordDetected = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onHotwordDetected()
            }
        }
        
        // Stille erkannt → automatisch stoppen + senden
        silenceDetector.onSilenceDetected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.stopAndSend()
            }
        }

        // VAD: Sprache erkannt → UI-Feedback
        vadService.onRecordingStarted = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRecording = true
                self.pulseScale = 1.15
                self.statusText = L("🎙️ Aufnahme läuft...", "🎙️ Recording...")
            }
        }

        // VAD: Aufnahme fertig → senden
        vadService.onRecordingComplete = { [weak self] (url: URL) in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRecording = false
                self.pulseScale = 1.0
                HotwordService.playSendSound()
                self.messages.append(Message(text: nil, audioURL: url, isFromUser: true))
                await self.sendToBot(audioURL: url)
            }
        }

        // VAD: Aufnahme verworfen (kein Wort erkannt) → UI zurücksetzen
        vadService.onRecordingDiscarded = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRecording = false
                self.pulseScale = 1.0
                self.statusText = L("👂 Höre zu...", "👂 Listening...")
            }
        }

        // VAD: Kalibrierung fertig
        vadService.onCalibrationDone = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.statusText = L("👂 Höre zu...", "👂 Listening...")
            }
        }

        // VAD-Zustandsänderungen → View neu rendern (Combine-Relay)
        vadCancellable = vadService.objectWillChange.sink { [weak self] (_: Void) in
            self?.objectWillChange.send()
        }
    }
    
    // MARK: - Setup
    
    func setup() async {
        // Mikrofon
        let granted = await audioService.requestPermission()
        if !granted { showError(L("Mikrofon-Zugriff verweigern", "Microphone access denied")) }
        
        // Bot laden
        loadBot()
        updateService()
        await testConnection()
        
        // Hör-Modus laden
        let savedMode = UserDefaults.standard.string(forKey: "listenMode") ?? "vad"
        listenMode = ListenMode(rawValue: savedMode) ?? .vad
        let savedHotword = UserDefaults.standard.string(forKey: "hotword") ?? "hey bot"
        hotwordService.hotword = savedHotword
        let savedLanguage = UserDefaults.standard.string(forKey: "hotwordLanguage") ?? "en-US"
        hotwordService.language = savedLanguage
        vadService.language = savedLanguage

        await applyListenMode(listenMode)

        // Legacy: hotwordEnabled=true → auf .hotword migrieren
        if listenMode == .off && UserDefaults.standard.bool(forKey: "hotwordEnabled") {
            listenMode = .hotword
            UserDefaults.standard.set("hotword", forKey: "listenMode")
            await applyListenMode(.hotword)
        }
        
        pulseScale = 1.1
    }
    
    func reloadConfig() {
        loadBot()
        updateService()
        Task { await testConnection() }
        
        // Hotword + Sprache aktualisieren
        let savedHotword = UserDefaults.standard.string(forKey: "hotword") ?? "hey bot"
        hotwordService.hotword = savedHotword
        let savedLanguage = UserDefaults.standard.string(forKey: "hotwordLanguage") ?? "en-US"
        hotwordService.language = savedLanguage
        vadService.language = savedLanguage

        // Modus neu laden (kann in Settings geändert worden sein)
        let newModeRaw = UserDefaults.standard.string(forKey: "listenMode") ?? "vad"
        let newMode = ListenMode(rawValue: newModeRaw) ?? .off
        if newMode != listenMode {
            Task { await applyListenMode(newMode) }
        }
    }
    
    // MARK: - Hör-Modus

    func setListenMode(_ mode: ListenMode) {
        Task { await applyListenMode(mode) }
    }

    func applyListenMode(_ mode: ListenMode) async {
        // Alles stoppen was lief
        hotwordService.stopListening()
        vadService.stop()

        listenMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "listenMode")

        switch mode {
        case .off:
            statusText = L("Halten zum Sprechen", "Hold to speak")

        case .hotword:
            let granted = await hotwordService.requestPermissions()
            if granted {
                hotwordService.startListening()
                statusText = L("Sag \"\(hotwordService.hotword)\"", "Say \"\(hotwordService.hotword)\"")
            } else {
                listenMode = .off
                UserDefaults.standard.set("off", forKey: "listenMode")
                showError(L("Spracherkennung nicht erlaubt — Einstellungen öffnen",
                             "Speech recognition not allowed — open Settings"))
            }

        case .vad:
            let granted = await hotwordService.requestPermissions()  // nutzt dieselben Permissions
            if granted {
                statusText = L("⏳ Kalibriere...", "⏳ Calibrating...")
                await vadService.start()
            } else {
                listenMode = .off
                UserDefaults.standard.set("off", forKey: "listenMode")
                showError(L("Mikrofon-Zugriff verweigert — Einstellungen öffnen",
                             "Microphone access denied — open Settings"))
            }
        }
    }
    
    private func onHotwordDetected() {
        guard !isRecording, !isPlaying else { return }
        
        // Ton spielen, exakte Dauer zurückbekommen, dann erst Recording starten.
        // Session-Rekonfiguration in startRecording() würde AVAudioPlayer unterbrechen.
        let soundDuration = HotwordService.playActivationSound()
        let waitMs = Int((soundDuration * 1000) + 80) // Ton-Dauer + 80ms Puffer
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(waitMs))
            self?.startRecording(fromHotword: true)
        }
    }
    
    // MARK: - Recording
    
    func startRecording(fromHotword: Bool = false) {
        guard !isRecording, !isPlaying else { return }

        // Laufende Auto-Modi pausieren
        hotwordService.stopListening()
        vadService.stop()

        do {
            _ = try audioService.startRecording()
            isRecording = true
            statusText = L("🎙️ Aufnahme läuft...", "🎙️ Recording...")
            errorMessage = nil
            pulseScale = 1.15
            
            // Stille-Erkennung NUR bei Hotword-Trigger (nicht bei manuellem Button)
            if fromHotword {
                silenceDetector.silenceThreshold = silenceThreshold
                try? silenceDetector.start()
            }
        } catch {
            showError(L("Aufnahme-Fehler: \(error.localizedDescription)",
                        "Recording error: \(error.localizedDescription)"))
            if hotwordEnabled { hotwordService.startListening() }
        }
    }
    
    func stopAndSend() {
        guard isRecording, let url = audioService.stopRecording() else { return }
        isRecording = false
        pulseScale = 1.0
        silenceDetector.stop()
        HotwordService.playSendSound()
        messages.append(Message(text: nil, audioURL: url, isFromUser: true))
        Task { await sendToBot(audioURL: url) }
    }
    
    // MARK: - Text senden
    
    func sendTextToBot(text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        lastUserTranscript = text
        messages.append(Message(text: text, audioURL: nil, isFromUser: true))
        Task { await sendTextToBotAsync(text: text) }
    }
    
    private func sendTextToBotAsync(text: String) async {
        guard let relay = relayService else {
            showError(L("Server nicht konfiguriert — Einstellungen öffnen",
                        "Server not configured — open Settings"))
            return
        }
        
        statusText = L("📤 Sende Text...", "📤 Sending text...")
        
        do {
            statusText = L("⏳ Warte auf Antwort...", "⏳ Waiting for reply...")
            let reply = try await relay.sendText(text: text)
            
            switch reply {
            case .voice(let voiceURL, let botText, _):
                let cleanedBot = botText.map { cleanBotResponse($0) }
                messages.append(Message(text: cleanedBot, audioURL: voiceURL, isFromUser: false))
                if let t = cleanedBot {
                    lastResponseText = t
                    suggestions = extractSuggestions(from: t)
                }
                statusText = L("🔊 Antwort...", "🔊 Reply...")
                isPlaying = true
                pulseScale = 1.1
                pauseListening()   // stop VAD/hotword so bot doesn't hear itself
                try audioService.play(url: voiceURL)
                while audioService.isPlaying {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                
            case .text(let responseText, _):
                let cleanedResp = cleanBotResponse(responseText)
                lastResponseText = cleanedResp
                suggestions = extractSuggestions(from: cleanedResp)
                messages.append(Message(text: cleanedResp, audioURL: nil, isFromUser: false))
            }
            
            statusText = L("Halten zum Sprechen", "Hold to speak")
            
        } catch {
            showError(error.localizedDescription)
            statusText = L("Halten zum Sprechen", "Hold to speak")
        }
        
        isPlaying = false
        pulseScale = 1.0
        restoreHotword()
    }
    
    // MARK: - Send + Receive (Voice)
    
    private func sendToBot(audioURL: URL) async {
        guard let relay = relayService else {
            showError(L("Server nicht konfiguriert — Einstellungen öffnen",
                        "Server not configured — open Settings"))
            statusText = L("Halten zum Sprechen", "Hold to speak")
            restoreHotword()
            return
        }

        statusText = L("📤 Sende...", "📤 Sending...")

        do {
            statusText = L("⏳ Warte auf Antwort...", "⏳ Waiting for reply...")
            let reply = try await relay.sendVoice(audioURL: audioURL)

            switch reply {
            case .voice(let voiceURL, let botText, let transcript):
                // User-Nachricht mit Transkript aktualisieren — stabile ID behalten!
                if let t = transcript, !t.isEmpty {
                    lastUserTranscript = t
                    if let idx = messages.lastIndex(where: { $0.isFromUser }) {
                        let existing = messages[idx]
                        messages[idx] = Message(id: existing.id, text: t,
                                                audioURL: existing.audioURL, isFromUser: true)
                    }
                }
                let cleanedBot = botText.map { cleanBotResponse($0) }
                messages.append(Message(text: cleanedBot, audioURL: voiceURL, isFromUser: false))
                if let t = cleanedBot {
                    lastResponseText = t
                    suggestions = extractSuggestions(from: t)
                } else {
                    // Bot hat nur Audio gesendet (kein Text) — Hauptscreen-Placeholder
                    lastResponseText = lastResponseText ?? "🎵"
                    suggestions = []
                }
                statusText = L("🔊 Antwort...", "🔊 Reply...")
                isPlaying = true
                pulseScale = 1.1
                pauseListening()   // stop VAD/hotword so bot doesn't hear itself
                try audioService.play(url: voiceURL)
                while audioService.isPlaying {
                    try? await Task.sleep(for: .milliseconds(200))
                }

            case .text(let text, let transcript):
                // Transkript der User-Aufnahme setzen — stabile ID behalten!
                if let t = transcript, !t.isEmpty {
                    lastUserTranscript = t
                    if let idx = messages.lastIndex(where: { $0.isFromUser }) {
                        let existing = messages[idx]
                        messages[idx] = Message(id: existing.id, text: t,
                                                audioURL: existing.audioURL, isFromUser: true)
                    }
                }
                let cleanedText = cleanBotResponse(text)
                lastResponseText = cleanedText
                suggestions = extractSuggestions(from: cleanedText)
                messages.append(Message(text: cleanedText, audioURL: nil, isFromUser: false))
            }

            statusText = L("Halten zum Sprechen", "Hold to speak")

        } catch {
            showError(error.localizedDescription)
            statusText = L("Halten zum Sprechen", "Hold to speak")
        }

        isPlaying = false
        pulseScale = 1.0
        restoreHotword()
    }
    
    /// Extrahiert bis zu 3 kurze Antwort-Vorschläge aus Bot-Text.
    /// Nur echte nummerierte Listen (1. / 2. / 3.) oder Bullet-Punkte (• / -),
    /// NICHT Markdown-Kursiv (*text*) oder Haiku-Zeilen.
    /// Strip bot's echo of user transcript (lines starting with > 🎤)
    private func cleanBotResponse(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let cleaned = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("> 🎤")
        }
        let result = cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result
    }

    private func extractSuggestions(from text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var found: [String] = []
        for line in lines {
            // Nur echte Listen-Zeilen: "1. ", "2) ", "• ", "- " (kein Asterisk!)
            guard let _ = line.range(of: #"^(\d+[\.\)]\s+|[•\-]\s+)"#, options: .regularExpression) else {
                continue
            }
            let stripped = line
                .replacingOccurrences(of: #"^\d+[\.\)]\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[•\-]\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            // Mindestens 5 Zeichen, max 140, kein reines Markdown (*fett* / _kursiv_)
            let looksLikeMarkdown = stripped.hasPrefix("*") || stripped.hasPrefix("_")
            if stripped.count >= 5 && stripped.count <= 140 && !looksLikeMarkdown {
                found.append(stripped)
            }
            if found.count >= 3 { break }
        }
        return found
    }

    private func restoreHotword() {
        switch listenMode {
        case .off: break
        case .hotword:
            hotwordService.resumeAfterRecording()
        case .vad:
            Task { await vadService.start() }
        }
    }

    /// Pause VAD/hotword before bot plays audio — prevents bot from hearing itself
    private func pauseListening() {
        switch listenMode {
        case .off: break
        case .hotword: hotwordService.stopListening()
        case .vad:     vadService.stop()
        }
    }
    
    // MARK: - Chat Persistence

    private func persistChats() {
        if let bot = selectedBot {
            botMessages[bot.id] = messages
        }
        ChatHistory.saveAll(botMessages)
    }

    func clearAllChats() {
        botMessages = [:]
        messages = []
        lastResponseText = nil
        suggestions = []
        botLastResponse = [:]
        botSuggestions = [:]
        ChatHistory.deleteAll()
    }

    // MARK: - Helpers
    
    private func showError(_ msg: String) {
        errorMessage = msg
        Task {
            try? await Task.sleep(for: .seconds(4))
            errorMessage = nil
        }
    }
    
    private func updateService() {
        let username = selectedBot?.username ?? ""
        relayService = RelayService(serverURL: serverURL, botUsername: username)
    }

    private func testConnection() async {
        guard let r = relayService else { isConnected = false; return }
        isConnected = await r.checkHealth()
    }

    private func saveBot() {
        if let b = selectedBot {
            UserDefaults.standard.set(b.id.uuidString, forKey: "selectedBotId")
        }
    }

    private func loadBot() {
        let bots = Bot.loadAll()
        if let savedId = UserDefaults.standard.string(forKey: "selectedBotId"),
           let uuid = UUID(uuidString: savedId),
           let bot = bots.first(where: { $0.id == uuid }) {
            selectedBot = bot
        } else {
            selectedBot = bots.first
        }
    }
}

#Preview {
    MainView(voipService: VoIPService(), hotwordService: HotwordService())
}
