import Foundation
import Speech
import AVFoundation
import AudioToolbox  // AudioServicesPlaySystemSound

/// HotwordService — Einfach und zuverlässig.
/// Bei jeder Aufnahme: vollständiger Stop → nach Antwort: vollständiger Neustart.

@MainActor
class HotwordService: NSObject, ObservableObject {
    
    // MARK: - State
    @Published var isListening = false
    @Published var isAuthorized = false
    @Published var lastDetectedWord: String?
    
    var onHotwordDetected: (() -> Void)?
    
    // MARK: - Config
    var hotword: String = "hey bot" {
        didSet { hotwordVariants = buildVariants(hotword) }
    }
    private var hotwordVariants: [String] = ["hey bot", "hey bott", "heybot"]
    
    var language: String = "de-DE" {
        didSet {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
            speechRecognizer?.delegate = self
        }
    }
    
    // MARK: - Private
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine = AVAudioEngine()
    private var tapInstalled = false
    private var renewTimer: Timer?
    private var watchdogTimer: Timer?
    private var isRestarting = false  // Verhindert Cancel-Loop
    
    // MARK: - Init
    
    override init() {
        super.init()
        let lang = UserDefaults.standard.string(forKey: "hotwordLanguage") ?? "en-US"
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: lang))
        speechRecognizer?.delegate = self
        hotwordVariants = buildVariants(hotword)
        language = lang
    }
    
    // MARK: - Permissions
    
    func requestPermissions() async -> Bool {
        let s = await requestSpeechPermission()
        let m = await requestMicPermission()
        isAuthorized = s && m
        return isAuthorized
    }
    
    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { s in c.resume(returning: s == .authorized) }
        }
    }
    
    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { g in c.resume(returning: g) }
        }
    }
    
    // MARK: - Public API
    
    func startListening() {
        guard isAuthorized, !isListening else { return }
        isListening = true
        HotwordService.warmupActivationSound() // Hardware vorwärmen
        doStart()
    }
    
    func stopListening() {
        isListening = false
        stopWatchdog()
        cancelRenewTimer()
        teardown()
    }
    
    /// Nach Aufnahme: 400ms warten dann frisch starten
    func resumeAfterRecording() {
        guard isAuthorized else {
            print("HotwordService: resumeAfterRecording — isAuthorized=false, abbruch!")
            return
        }
        print("HotwordService: resumeAfterRecording — teardown + 400ms + frischer Start")
        isListening = false
        stopWatchdog()
        cancelRenewTimer()
        teardown()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            self.isListening = true
            HotwordService.warmupActivationSound()
            self.doStart()
        }
    }
    
    // MARK: - Sounds
    // AVAudioPlayer — bypassed ringer switch, nutzt aktive Audio-Session

    private static var activationPlayer: AVAudioPlayer?
    private static var sendPlayer: AVAudioPlayer?
    private static var responsePlayer: AVAudioPlayer?
    private static var pauseOnPlayer: AVAudioPlayer?
    private static var pauseOffPlayer: AVAudioPlayer?

    /// Vorwärmen: Player erstellen + prepareToPlay() → Hardware bereits aktiv wenn Hotword feuert
    static func warmupActivationSound() {
        let saved = UserDefaults.standard.object(forKey: "activationSoundID") == nil
            ? -1 : UserDefaults.standard.integer(forKey: "activationSoundID")
        switch saved {
        case -999: return
        case -1, 0: activationPlayer = makePloppPlayer(volume: 0.4)
        case 99:    activationPlayer = makeTonePlayer(notes: [(260, 0.15), (390, 0.18)], volume: 0.35)
        default:    return  // System-Sounds können nicht vorgewärmt werden
        }
        activationPlayer?.prepareToPlay()
    }

    /// Hotword erkannt — spielt Ton, gibt Dauer zurück damit Caller warten kann
    @discardableResult
    static func playActivationSound() -> TimeInterval {
        // Default: -1 = Plopp (wenn noch nie gesetzt, liefert AppStorage 0 → auch Plopp)
        let saved = UserDefaults.standard.object(forKey: "activationSoundID") == nil
            ? -1
            : UserDefaults.standard.integer(forKey: "activationSoundID")

        switch saved {
        case -999: return 0
        case -1, 0:  // Plopp (Default)
            activationPlayer = makePloppPlayer(volume: 0.4)
            activationPlayer?.play()
            return activationPlayer?.duration ?? 0.06
        case 99:  // Sinus-Doppelton (Legacy)
            activationPlayer = makeTonePlayer(notes: [(260, 0.15), (390, 0.18)], volume: 0.35)
            activationPlayer?.play()
            return activationPlayer?.duration ?? 0.35
        default:  // System Sound
            AudioServicesPlaySystemSound(SystemSoundID(saved))
            return 0.3  // System-Sounds ~200-300ms
        }
    }

    /// Aufnahme gesendet — System Sound aus Settings ("Absende-Sound")
    static func playSendSound() {
        let id = UserDefaults.standard.object(forKey: "sendSoundID") == nil
            ? 1114  // Bloom 🌸
            : UserDefaults.standard.integer(forKey: "sendSoundID")
        guard id != -999 else { return }
        AudioServicesPlaySystemSound(SystemSoundID(id))
    }

    /// Antwort kommt — sanfter tiefer Ton, 3/4 Lautstärke
    static func playResponseSound() {
        responsePlayer = makeTonePlayer(notes: [(528, 0.18)], volume: 0.21)
        responsePlayer?.play()
    }

    /// VAD Pause aktiviert — absteigender Ton (tief = pause)
    @discardableResult
    static func playPauseOnSound() -> TimeInterval {
        let id = UserDefaults.standard.object(forKey: "pauseOnSoundID") == nil
            ? -2  // Default: absteigender Sinus-Ton
            : UserDefaults.standard.integer(forKey: "pauseOnSoundID")
        switch id {
        case -999: return 0
        case -2:   // Absteigender Ton (default)
            pauseOnPlayer = makeTonePlayer(notes: [(440, 0.15), (330, 0.15)], volume: 0.3)
            pauseOnPlayer?.play()
            return pauseOnPlayer?.duration ?? 0.3
        case -1:   pauseOnPlayer = makePloppPlayer(volume: 0.3); pauseOnPlayer?.play(); return pauseOnPlayer?.duration ?? 0.06
        default:   AudioServicesPlaySystemSound(SystemSoundID(id)); return 0.3
        }
    }

    /// VAD Pause aufgehoben — aufsteigender Ton (hoch = aktiv)
    @discardableResult
    static func playPauseOffSound() -> TimeInterval {
        let id = UserDefaults.standard.object(forKey: "pauseOffSoundID") == nil
            ? -3  // Default: aufsteigender Sinus-Ton
            : UserDefaults.standard.integer(forKey: "pauseOffSoundID")
        switch id {
        case -999: return 0
        case -3:   // Aufsteigender Ton (default)
            pauseOffPlayer = makeTonePlayer(notes: [(330, 0.15), (440, 0.15)], volume: 0.3)
            pauseOffPlayer?.play()
            return pauseOffPlayer?.duration ?? 0.3
        case -1:   pauseOffPlayer = makePloppPlayer(volume: 0.3); pauseOffPlayer?.play(); return pauseOffPlayer?.duration ?? 0.06
        default:   AudioServicesPlaySystemSound(SystemSoundID(id)); return 0.3
        }
    }

    /// Generiert einen natürlichen "Plopp" — mit 40ms Silence-Prefix gegen Hardware-Knacken
    private static func makePloppPlayer(volume: Float = 0.4) -> AVAudioPlayer? {
        let sampleRate: Double = 44100
        let silenceMs = 0.040  // 40ms Stille → Hardware wacht auf, bevor Ton startet
        let duration   = 0.06  // 60ms Plopp
        let totalN = Int(sampleRate * (silenceMs + duration))
        let silenceN = Int(sampleRate * silenceMs)
        var samples = [Int16](repeating: 0, count: totalN)
        for i in silenceN..<totalN {
            let t = Double(i - silenceN) / sampleRate
            let v = (sin(2.0 * .pi * 90.0 * t) * 0.7 +
                     sin(2.0 * .pi * 180.0 * t) * 0.3) *
                    exp(-t * 55.0) * Double(volume)
            samples[i] = Int16(clamping: Int32(v * Double(Int16.max)))
        }
        var wav = Data()
        let ch: UInt16 = 1; let bits: UInt16 = 16; let rate = UInt32(sampleRate)
        let dataSize = UInt32(samples.count * 2)
        func w<T>(_ v: T) { withUnsafeBytes(of: v) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: "RIFF".utf8); w(dataSize + 36)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8); w(UInt32(16)); w(UInt16(1))
        w(ch); w(rate); w(rate * UInt32(ch) * UInt32(bits/8)); w(ch*(bits/8)); w(bits)
        wav.append(contentsOf: "data".utf8); w(dataSize)
        for s in samples { w(s) }
        return try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
    }

    /// Generiert einen Frequency-Sweep (Glide von fromHz → toHz) als WAV
    /// 40ms Silence-Prefix → Hardware wacht auf, kein Knacken
    private static func makeSweepPlayer(fromHz: Double, toHz: Double,
                                         duration: Double, volume: Float) -> AVAudioPlayer? {
        let sampleRate: Double = 44100
        let silenceN = Int(sampleRate * 0.040)
        let n = Int(sampleRate * duration)
        let decay = min(0.04, duration * 0.3)
        var samples = [Int16](repeating: 0, count: silenceN)  // Silence-Prefix
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let hz = fromHz + (toHz - fromHz) * (t / duration)
            phase += 2.0 * .pi * hz / sampleRate
            let env = t > duration - decay ? (duration - t) / decay : 1.0
            samples.append(Int16(clamping: Int32(sin(phase) * env * Double(volume) * Double(Int16.max))))
        }
        var wav = Data()
        let ch: UInt16 = 1; let bits: UInt16 = 16; let rate = UInt32(sampleRate)
        let dataSize = UInt32(samples.count * 2)
        func w<T>(_ v: T) { withUnsafeBytes(of: v) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: "RIFF".utf8); w(dataSize + 36)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8); w(UInt32(16)); w(UInt16(1))
        w(ch); w(rate); w(rate * UInt32(ch) * UInt32(bits/8)); w(ch*(bits/8)); w(bits)
        wav.append(contentsOf: "data".utf8); w(dataSize)
        for s in samples { w(s) }
        return try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
    }

    /// Generiert WAV-Daten mit mehreren aufeinanderfolgenden Tönen + Fade-Envelope
    /// silenceMs: stille Samples am Anfang → Hardware wacht auf vor erstem Ton
    private static func makeTonePlayer(notes: [(hz: Double, dur: Double)],
                                        volume: Float,
                                        silenceMs: Double = 0.040) -> AVAudioPlayer? {
        let sampleRate: Double = 44100
        var allSamples = [Int16]()

        // Silence-Prefix: Hardware aufwecken, kein Knacken
        let silenceSamples = Int(sampleRate * silenceMs)
        allSamples.append(contentsOf: [Int16](repeating: 0, count: silenceSamples))

        for (hz, dur) in notes {
            let n = Int(sampleRate * dur)
            let attack = min(0.04, dur * 0.2)
            let decay  = min(0.06, dur * 0.3)
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let env: Double
                if t < attack          { env = t / attack }
                else if t > dur - decay { env = (dur - t) / decay }
                else                   { env = 1.0 }
                let v = sin(2.0 * .pi * hz * t) * env * Double(volume)
                allSamples.append(Int16(clamping: Int32(v * Double(Int16.max))))
            }
        }

        var wav = Data()
        let ch: UInt16 = 1
        let bits: UInt16 = 16
        let rate = UInt32(sampleRate)
        let dataSize = UInt32(allSamples.count * 2)

        func w<T>(_ v: T) { withUnsafeBytes(of: v) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: "RIFF".utf8); w(dataSize + 36)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8); w(UInt32(16)); w(UInt16(1))
        w(ch); w(rate); w(rate * UInt32(ch) * UInt32(bits / 8)); w(ch * (bits / 8)); w(bits)
        wav.append(contentsOf: "data".utf8); w(dataSize)
        for s in allSamples { w(s) }

        return try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
    }
    
    // MARK: - Engine
    
    private var isEngineRunning: Bool { audioEngine.isRunning }
    
    private func doStart() {
        print("HotwordService: doStart() — neue Engine, isAuthorized=\(isAuthorized)")
        do {
            try startEngine()
            print("HotwordService: Engine gestartet ✓")
            renewTask()
            startWatchdog()
        } catch {
            print("HotwordService: doStart FEHLER: \(error) — retry in 1s")
            scheduleRetry()
        }
    }
    
    private func startEngine() throws {
        // Session wird NICHT hier konfiguriert — AudioSessionManager.shared ist Single Source of Truth.
        AudioSessionManager.shared.ensureActive()
        
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        let fmt = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.recognitionRequest?.append(buf)
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    private func teardown() {
        isRestarting = true
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if tapInstalled {
            // Tap vor dem Stop entfernen — verhindert Crash
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning { audioEngine.stop() }
        // KRITISCH: Neue Engine-Instanz erstellen.
        // AVAudioEngine kann nach vollständigem Stop auf iOS nicht zuverlässig
        // neu gestartet werden — bekannter Apple-Bug. Neue Instanz = sauber.
        audioEngine = AVAudioEngine()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.isRestarting = false
        }
    }
    
    // MARK: - Recognition Task
    
    private func renewTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        recognitionRequest = req
        
        recognitionTask = speechRecognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            
            if let result {
                self.checkForHotword(in: result.bestTranscription.formattedString.lowercased())
            }
            
            if error != nil || result?.isFinal == true {
                Task { @MainActor [weak self] in
                    guard let self, self.isListening, !self.isRestarting else { return }
                    self.scheduleRenew(after: 0.3)
                }
            }
        }
    }
    
    private func scheduleRenew(after delay: TimeInterval) {
        cancelRenewTimer()
        renewTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                if !self.audioEngine.isRunning {
                    // Engine gestoppt → vollen Restart
                    self.doStart()
                } else {
                    // Nur neuen Task
                    self.renewTask()
                }
            }
        }
    }
    
    private func scheduleRetry() {
        cancelRenewTimer()
        renewTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                self.doStart()
            }
        }
    }
    
    private func cancelRenewTimer() {
        renewTimer?.invalidate()
        renewTimer = nil
    }
    
    // MARK: - Hotword Detection
    
    private func checkForHotword(in transcript: String) {
        for variant in hotwordVariants {
            if transcript.contains(variant) {
                lastDetectedWord = variant
                stopWatchdog()
                cancelRenewTimer()
                isRestarting = true
                recognitionTask?.cancel()
                recognitionTask = nil
                recognitionRequest?.endAudio()
                recognitionRequest = nil
                isListening = false
                isRestarting = false
                onHotwordDetected?()
                return
            }
        }
    }
    
    private func buildVariants(_ word: String) -> [String] {
        let base = word.lowercased()
        var v = [base]
        let parts = base.split(separator: " ")
        if parts.count > 1 {
            v.append(parts.joined())
            v.append(parts.joined(separator: "-"))
        }
        return v
    }
    
    // MARK: - Watchdog
    
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                if !self.audioEngine.isRunning {
                    print("HotwordService: Watchdog — neu starten")
                    self.doStart()
                }
            }
        }
    }
    
    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension HotwordService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                                      availabilityDidChange available: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.isListening, available else { return }
            self.renewTask()
        }
    }
}

enum HotwordError: Error {
    case notAuthorized
}
