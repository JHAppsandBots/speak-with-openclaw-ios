import Foundation
import AVFoundation
import Speech

/// VADService — Voice Activity Detection ohne Hotword
///
/// **Architektur-Prinzip (ab 27.02.2026):**
/// Die AudioEngine läuft DURCHGEHEND — auch während Playback. Nur die Buffer-Verarbeitung
/// wird pausiert/resumed. Das ist der Schlüssel für zuverlässigen Hintergrund-Betrieb:
/// iOS hält die App aktiv solange die AudioEngine läuft.
///
/// Flow: idle → calibrating (2s) → monitoring → recording → done → monitoring
///       Während Playback: Engine läuft, aber Buffers werden ignoriert (suspended=true)
///
/// Pre-roll: Letzten 600ms immer im Puffer → kein abgeschnittener Anfang.
/// Kalibrierung: Hintergrundpegel messen → adaptiver Threshold (Pegel + 15 dB).

@MainActor
class VADService: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isActive      = false   // VAD läuft (Engine aktiv)
    @Published var isRecording   = false   // Gerade am Aufnehmen
    @Published var isCalibrating = false   // Kalibrierungsphase
    @Published var isPaused      = false   // Aufnahme pausiert via Hotword

    // Suspended = Engine läuft, aber Buffers werden ignoriert (während Playback)
    private var isSuspended = false

    // MARK: - Callbacks
    var onRecordingComplete: ((URL) -> Void)?
    var onRecordingStarted:  (() -> Void)?
    var onRecordingDiscarded: (() -> Void)?
    var onCalibrationDone:   (() -> Void)?

    // MARK: - Config
    var silenceThreshold: Double = 2.0
    var language: String = "de-DE" {
        didSet {
            if oldValue != language {
                speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
                print("VADService: SpeechRecognizer neu erstellt für Sprache \(language)")
            }
        }
    }
    var pauseHotword  = "aufnahme pause"
    var resumeHotword = "aufnahme weiter"

    // MARK: - Private Engine (bleibt durchgehend aktiv!)
    private var audioEngine   = AVAudioEngine()
    private var audioFile:    AVAudioFile?
    private var outputURL:    URL?
    private var tapInstalled  = false
    private var engineFormat: AVAudioFormat?

    // Pre-roll
    private var prerollBuffers: [AVAudioPCMBuffer] = []
    private var prerollDuration: Double = 0.0
    private let prerollMaxDuration: Double = 0.6

    // Kalibrierung
    private var calibrationSamples: [Float] = []
    private var noiseFloor: Float = -50.0
    private var speechThreshold: Float = -35.0

    // Energie-Monitoring
    private var energyHistory: [Float] = []
    private var speechStartTime: Date?
    private var lastSpeechTime:  Date?

    // Stille-Erkennung: Task-basiert statt Timer (funktioniert im Hintergrund)
    private var silenceTask: Task<Void, Never>?

    // Validator
    private var speechRecognizer: SFSpeechRecognizer?
    private var validationRequest: SFSpeechAudioBufferRecognitionRequest?
    private var validationTask: SFSpeechRecognitionTask?
    private var validationTimeout: Task<Void, Never>?
    @Published var hasValidatedSpeech = false
    private var lastRecognizedText = ""

    // State-Machine
    private enum State { case idle, calibrating, monitoring, recording }
    private var state: State = .idle

    // MARK: - Init

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
    }

    // MARK: - Public API

    /// Startet VAD: Engine starten, kalibrieren, dann monitoren.
    /// Engine bleibt danach durchgehend aktiv.
    func start() async {
        guard !isActive else { return }
        isActive = true
        isSuspended = false

        AudioSessionManager.shared.ensureActive()

        do {
            try startEngine()
        } catch {
            print("VADService: Engine-Start-Fehler \(error)")
            isActive = false
            return
        }

        await calibrate()
    }

    /// Stoppt VAD vollständig — Engine wird abgebaut.
    /// Nur beim App-Close oder Mode-Wechsel verwenden, NICHT zwischen Zyklen.
    func stop() {
        state       = .idle
        isActive    = false
        isRecording = false
        isCalibrating = false
        isSuspended = false
        silenceTask?.cancel()
        silenceTask = nil
        cancelValidation()
        teardownEngine()
    }

    /// Pausiert die Buffer-Verarbeitung — Engine läuft weiter.
    /// Für Playback-Phase: Audio-Route bleibt stabil, Background bleibt aktiv.
    func suspend() {
        guard isActive else { return }
        isSuspended = true
        isRecording = false
        silenceTask?.cancel()
        silenceTask = nil
        cancelValidation()
        print("VADService: Suspended (Engine läuft weiter)")
    }

    /// Nimmt Buffer-Verarbeitung wieder auf. Keine Rekalibrierung nötig.
    func resume() {
        guard isActive, isSuspended else { return }
        isSuspended = false
        state = .monitoring
        energyHistory = []
        speechStartTime = nil
        prerollBuffers = []
        prerollDuration = 0.0
        print("VADService: Resumed → Monitoring")
    }

    // MARK: - Engine (einmal starten, durchgehend aktiv)

    private func startEngine() throws {
        teardownEngine()
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        engineFormat = format

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                self?.processBuffer(buffer, format: format)
            }
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
        print("VADService: Engine gestartet ✅")
    }

    private func teardownEngine() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine = AVAudioEngine()
        engineFormat = nil
    }

    // MARK: - Zentrale Buffer-Verarbeitung

    private func processBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        // Suspended = ignoriere alles (Playback läuft)
        guard !isSuspended else { return }

        guard let db = rmsDB(buffer) else { return }

        switch state {
        case .idle:
            break

        case .calibrating:
            calibrationSamples.append(db)

        case .monitoring:
            processMonitoringBuffer(buffer, db: db, format: format)

        case .recording:
            processRecordingBuffer(buffer, db: db)
        }
    }

    // MARK: - Kalibrierung

    private func calibrate() async {
        state = .calibrating
        isCalibrating = true
        calibrationSamples = []
        print("VADService: Kalibrierung gestartet...")

        // 2 Sekunden Hintergrundgeräusche messen — Task.sleep statt Timer (background-safe)
        try? await Task.sleep(for: .seconds(2))

        finishCalibration()
    }

    private func finishCalibration() {
        isCalibrating = false

        if calibrationSamples.isEmpty {
            noiseFloor     = -50.0
            speechThreshold = -35.0
        } else {
            let mean = calibrationSamples.reduce(0, +) / Float(calibrationSamples.count)
            noiseFloor = mean
            speechThreshold = max(noiseFloor + 15.0, -42.0)
        }

        print("VADService: Kalibrierung fertig — noiseFloor=\(String(format:"%.1f", noiseFloor))dB, threshold=\(String(format:"%.1f", speechThreshold))dB")
        onCalibrationDone?()

        state = .monitoring
        energyHistory = []
        speechStartTime = nil
        prerollBuffers = []
        prerollDuration = 0.0
    }

    // MARK: - Monitoring

    private func processMonitoringBuffer(_ buffer: AVAudioPCMBuffer, db: Float, format: AVAudioFormat) {
        // Pre-roll
        let bufDuration = Double(buffer.frameLength) / format.sampleRate
        prerollBuffers.append(copyBuffer(buffer))
        prerollDuration += bufDuration
        while prerollDuration > prerollMaxDuration + 0.1, !prerollBuffers.isEmpty {
            let oldest = prerollBuffers.removeFirst()
            prerollDuration -= Double(oldest.frameLength) / format.sampleRate
        }

        // Smoothing
        energyHistory.append(db)
        if energyHistory.count > 5 { energyHistory.removeFirst() }
        let smoothed = energyHistory.reduce(0, +) / Float(energyHistory.count)

        if smoothed > speechThreshold {
            if speechStartTime == nil { speechStartTime = Date() }
            if Date().timeIntervalSince(speechStartTime!) >= 0.30 {
                beginRecording(format: format)
            }
        } else {
            speechStartTime = nil
        }
    }

    // MARK: - Recording

    private func beginRecording(format: AVAudioFormat) {
        guard state == .monitoring else { return }
        state = .recording
        isRecording = true
        lastSpeechTime = Date()
        print("VADService: Sprache erkannt — Recording startet")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vad_recording_\(Date().timeIntervalSince1970).caf")
        outputURL = url

        do {
            let settings: [String: Any] = [
                AVFormatIDKey:            Int(kAudioFormatLinearPCM),
                AVSampleRateKey:          format.sampleRate,
                AVNumberOfChannelsKey:    1,
                AVLinearPCMBitDepthKey:   16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey:    false,
            ]
            audioFile = try AVAudioFile(forWriting: url, settings: settings)

            for preBuffer in prerollBuffers {
                writeToFile(preBuffer)
            }
            prerollBuffers = []
            prerollDuration = 0.0

            startValidation(format: format)
            onRecordingStarted?()
        } catch {
            print("VADService: Datei-Fehler \(error)")
            state = .monitoring
            isRecording = false
        }
    }

    private func processRecordingBuffer(_ buffer: AVAudioPCMBuffer, db: Float) {
        writeToFile(buffer)
        feedValidation(buffer)

        energyHistory.append(db)
        if energyHistory.count > 5 { energyHistory.removeFirst() }
        let smoothed = energyHistory.reduce(0, +) / Float(energyHistory.count)

        if smoothed < speechThreshold {
            if silenceTask == nil {
                startSilenceCountdown()
            }
        } else {
            lastSpeechTime = Date()
            silenceTask?.cancel()
            silenceTask = nil
        }
    }

    // MARK: - Silence Countdown (Task-basiert, background-safe)

    private func startSilenceCountdown() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.silenceThreshold ?? 2.0))
            guard !Task.isCancelled else { return }
            self?.finishRecording()
        }
    }

    // MARK: - Aufnahme beenden

    private func finishRecording() {
        guard state == .recording else { return }
        isRecording = false
        silenceTask?.cancel()
        silenceTask = nil
        cancelValidation()

        audioFile = nil

        if !hasValidatedSpeech {
            print("VADService: Kein Wort erkannt — verworfen")
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            outputURL = nil
            onRecordingDiscarded?()
            transitionToMonitoring()
            return
        }

        if let url = outputURL {
            let text = lastRecognizedText.lowercased()
            lastRecognizedText = ""
            if text.contains(pauseHotword) {
                isPaused = true
                HotwordService.playPauseOnSound()
                try? FileManager.default.removeItem(at: url)
            } else if text.contains(resumeHotword) {
                isPaused = false
                HotwordService.playPauseOffSound()
                try? FileManager.default.removeItem(at: url)
            } else if isPaused {
                try? FileManager.default.removeItem(at: url)
            } else {
                print("VADService: Aufnahme fertig → \(url.lastPathComponent)")
                onRecordingComplete?(url)
            }
            outputURL = nil
        }

        // Kurze Pause, dann zurück zu Monitoring (Task statt Timer)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.transitionToMonitoring()
        }
    }

    private func transitionToMonitoring() {
        guard isActive, !isSuspended else { return }
        state = .monitoring
        energyHistory = []
        speechStartTime = nil
        prerollBuffers = []
        prerollDuration = 0.0
    }

    // MARK: - Datei schreiben

    private func writeToFile(_ buffer: AVAudioPCMBuffer) {
        guard let file = audioFile else { return }
        try? file.write(from: buffer)
    }

    // MARK: - Voice Validator

    private func startValidation(format: AVAudioFormat) {
        hasValidatedSpeech = false
        lastRecognizedText = ""
        validationRequest = SFSpeechAudioBufferRecognitionRequest()
        validationRequest?.shouldReportPartialResults = true
        validationRequest?.requiresOnDeviceRecognition = false

        guard let req = validationRequest else { return }

        validationTask = speechRecognizer?.recognitionTask(with: req) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let r = result, !r.bestTranscription.formattedString.isEmpty {
                    self.lastRecognizedText = r.bestTranscription.formattedString
                    self.hasValidatedSpeech = true
                    self.validationTask?.cancel()
                    self.validationTask = nil
                }
            }
        }

        // Timeout: Task-basiert statt Timer (background-safe)
        validationTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            guard let self, !self.hasValidatedSpeech else { return }
            print("VADService: Validierung — kein Wort in 2.5s")
        }
    }

    private func cancelValidation() {
        validationTimeout?.cancel()
        validationTimeout = nil
        validationTask?.cancel()
        validationTask = nil
        validationRequest?.endAudio()
        validationRequest = nil
    }

    private func feedValidation(_ buffer: AVAudioPCMBuffer) {
        validationRequest?.append(buffer)
    }

    // MARK: - Helpers

    private func rmsDB(_ buffer: AVAudioPCMBuffer) -> Float? {
        guard let data = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        var rms: Float = 0
        for i in 0..<count { rms += data[i] * data[i] }
        rms = sqrt(rms / Float(count))
        if rms < 1e-8 { return -80.0 }
        return 20.0 * log10(rms)
    }

    private func copyBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let copy = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: src.frameLength)!
        copy.frameLength = src.frameLength
        if let srcData = src.floatChannelData, let dstData = copy.floatChannelData {
            let n = Int(src.frameLength)
            for ch in 0..<Int(src.format.channelCount) {
                dstData[ch].assign(from: srcData[ch], count: n)
            }
        }
        return copy
    }
}
