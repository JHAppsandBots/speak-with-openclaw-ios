import Foundation
import AVFoundation
import Speech

/// VADService — Voice Activity Detection ohne Hotword
/// Hört kontinuierlich zu, erkennt Sprache, nimmt auf (mit Pre-roll), sendet bei Stille.
///
/// Flow: idle → calibrating (2s) → monitoring → recording → done → monitoring
///
/// Pre-roll: Letzten 600ms immer im Puffer → kein abgeschnittener Anfang.
/// Kalibrierung: Hintergrundpegel messen → adaptiver Threshold (Pegel + 15 dB).
/// Stille-Ende: X Sekunden unter Threshold → Aufnahme senden.

@MainActor
class VADService: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isActive      = false   // VAD läuft (monitoring oder recording)
    @Published var isRecording   = false   // Gerade am Aufnehmen
    @Published var isCalibrating = false   // Kalibrierungsphase
    @Published var isPaused      = false   // Aufnahme pausiert via Hotword

    // MARK: - Callbacks
    var onRecordingComplete: ((URL) -> Void)?  // URL der fertigen Aufnahme
    var onRecordingStarted:  (() -> Void)?     // Sprache erkannt → UI-Feedback
    var onRecordingDiscarded: (() -> Void)?    // Aufnahme verworfen (kein Wort erkannt)
    var onCalibrationDone:   (() -> Void)?     // Kalibrierung abgeschlossen

    // MARK: - Config
    var silenceThreshold: Double = 2.0   // Sekunden Stille bis Senden
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

    // MARK: - Private Engine
    private var audioEngine   = AVAudioEngine()
    private var audioFile:    AVAudioFile?
    private var outputURL:    URL?
    private var tapInstalled  = false

    // Pre-roll: Circular Buffer für letzten ~600ms Audio
    private var prerollBuffers: [AVAudioPCMBuffer] = []
    private var prerollDuration: Double = 0.0
    private let prerollMaxDuration: Double = 0.6  // 600ms Pre-roll

    // Kalibrierung
    private var calibrationSamples: [Float] = []
    private var calibrationTimer: Timer?
    private var noiseFloor: Float = -50.0   // dB, angepasst durch Kalibrierung
    private var speechThreshold: Float = -35.0  // dB, noiseFloor + 15dB

    // Energie-Monitoring
    private var energyHistory: [Float] = []       // Letzten 5 Messungen (100ms)
    private var speechStartTime: Date?
    private var lastSpeechTime:  Date?
    private var silenceTimer: Timer?
    private var monitorTimer: Timer?

    // Validator (SFSpeechRecognizer als Fake-Rauschen-Filter)
    private var speechRecognizer: SFSpeechRecognizer?
    private var validationRequest: SFSpeechAudioBufferRecognitionRequest?
    private var validationTask: SFSpeechRecognitionTask?
    private var validationWordCount = 0
    private var validationTimer: Timer?
    @Published var hasValidatedSpeech = false
    private var lastRecognizedText = ""

    // MARK: - Init

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
    }

    // MARK: - Public API

    /// Aktiviert VAD: zuerst 2s Kalibrierung, dann kontinuierliches Monitoring
    func start() async {
        guard !isActive else { return }
        isActive = true

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP,
                                              .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true)
            let hasExternal = session.currentRoute.outputs.contains {
                $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP ||
                $0.portType == .headphones   || $0.portType == .airPlay
            }
            if !hasExternal { try? session.overrideOutputAudioPort(.speaker) }
        } catch {
            print("VADService: Session-Fehler \(error)")
        }

        await calibrate()
    }

    /// Deaktiviert VAD vollständig
    func stop() {
        isActive    = false
        isRecording = false
        isCalibrating = false
        stopSilenceTimer()
        stopMonitorTimer()
        cancelValidation()
        stopCalibrationTimer()
        teardownEngine()
    }

    // MARK: - Kalibrierung (2s)

    private func calibrate() async {
        isCalibrating = true
        calibrationSamples = []
        print("VADService: Kalibrierung gestartet...")

        do {
            try startEngine(mode: .calibrating)
        } catch {
            print("VADService: Engine-Start-Fehler \(error)")
            isCalibrating = false
            startMonitoring()
            return
        }

        // 2s Hintergrundgeräusche messen
        await withCheckedContinuation { cont in
            calibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishCalibration()
                    cont.resume()
                }
            }
        }
    }

    private func finishCalibration() {
        isCalibrating = false
        teardownEngine()

        if calibrationSamples.isEmpty {
            noiseFloor     = -50.0
            speechThreshold = -35.0
        } else {
            // Mittlerer Rauschpegel
            let mean = calibrationSamples.reduce(0, +) / Float(calibrationSamples.count)
            noiseFloor = mean
            // Threshold: 15 dB über Rauschen, aber mindestens -40 dB
            speechThreshold = max(noiseFloor + 15.0, -42.0)
        }

        print("VADService: Kalibrierung fertig — noiseFloor=\(String(format:"%.1f", noiseFloor))dB, threshold=\(String(format:"%.1f", speechThreshold))dB")
        onCalibrationDone?()
        startMonitoring()
    }

    private func stopCalibrationTimer() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard isActive else { return }
        energyHistory = []
        speechStartTime = nil
        lastSpeechTime  = nil
        prerollBuffers  = []
        prerollDuration = 0.0

        do {
            try startEngine(mode: .monitoring)
        } catch {
            print("VADService: Monitoring Engine-Fehler \(error) — Retry in 1s")
            monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.startMonitoring() }
            }
        }
    }

    private func stopMonitorTimer() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    // MARK: - Engine + Tap

    private enum EngineMode { case calibrating, monitoring }

    private func startEngine(mode: EngineMode) throws {
        teardownEngine()
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch mode {
                case .calibrating: self.processCalibratingBuffer(buffer)
                case .monitoring:  self.processMonitoringBuffer(buffer, format: format)
                }
            }
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func teardownEngine() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine = AVAudioEngine()
    }

    // MARK: - Buffer Processing: Kalibrierung

    private func processCalibratingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let db = rmsDB(buffer) else { return }
        calibrationSamples.append(db)
    }

    // MARK: - Buffer Processing: Monitoring

    private func processMonitoringBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let db = rmsDB(buffer) else { return }

        // Pre-roll: Buffer in Ringpuffer halten
        if !isRecording {
            let bufDuration = Double(buffer.frameLength) / format.sampleRate
            prerollBuffers.append(copyBuffer(buffer))
            prerollDuration += bufDuration
            // Älteste Buffers rauswerfen wenn zu lang
            while prerollDuration > prerollMaxDuration + 0.1, !prerollBuffers.isEmpty {
                let oldest = prerollBuffers.removeFirst()
                let oldDur = Double(oldest.frameLength) / format.sampleRate
                prerollDuration -= oldDur
            }
        }

        // Energie-History für smoothing (letzte 5 = ~100ms)
        energyHistory.append(db)
        if energyHistory.count > 5 { energyHistory.removeFirst() }
        let smoothedDB = energyHistory.reduce(0, +) / Float(energyHistory.count)

        if isRecording {
            // Während Aufnahme: Buffer in Datei schreiben + Validation füttern
            writeToFile(buffer)
            feedValidation(buffer)

            // Stille-Erkennung: unter Threshold → Silence-Timer starten
            if smoothedDB < speechThreshold {
                if silenceTimer == nil {
                    startSilenceTimer()
                }
            } else {
                // Noch Sprache → Timer resetten
                lastSpeechTime = Date()
                stopSilenceTimer()
            }
        } else {
            // Monitoring: Sprache erkannt?
            if smoothedDB > speechThreshold {
                if speechStartTime == nil {
                    speechStartTime = Date()
                }
                let speechDuration = Date().timeIntervalSince(speechStartTime!)
                // Erst nach 300ms kontinuierlicher Aktivität auslösen
                if speechDuration >= 0.30 {
                    beginRecording(format: format)
                }
            } else {
                speechStartTime = nil  // Reset wenn Stille
            }
        }
    }

    // MARK: - Recording Starten

    private func beginRecording(format: AVAudioFormat) {
        guard isActive, !isRecording else { return }
        isRecording = true
        lastSpeechTime = Date()
        print("VADService: Sprache erkannt — Recording startet")

        // Output-Datei anlegen
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

            // Pre-roll zuerst schreiben (damit Anfang nicht verloren geht)
            for preBuffer in prerollBuffers {
                writeToFile(preBuffer)
            }
            prerollBuffers = []
            prerollDuration = 0.0

            // Validator starten (Fake-Rauschen-Filter via SFSpeechRecognizer)
            startValidation(format: format)

            onRecordingStarted?()
        } catch {
            print("VADService: Datei-Fehler \(error)")
            isRecording = false
        }
    }

    // MARK: - Datei schreiben

    private func writeToFile(_ buffer: AVAudioPCMBuffer) {
        guard let file = audioFile else { return }
        do {
            try file.write(from: buffer)
        } catch {
            // Stille — ignorieren
        }
    }

    // MARK: - Silence Timer

    private func startSilenceTimer() {
        stopSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishRecording()
            }
        }
    }

    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - Aufnahme beenden

    private func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        stopSilenceTimer()
        cancelValidation()

        audioFile = nil  // Schließt die Datei

        // Voice Validator: Wenn keine Wörter erkannt → verwerfen (Hintergrundgeräusch)
        if !hasValidatedSpeech {
            print("VADService: Kein Wort erkannt — Aufnahme verworfen (Hintergrundgeräusch)")
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            outputURL = nil
            onRecordingDiscarded?()
            startMonitoring()
            return
        }

        if let url = outputURL {
            let text = lastRecognizedText.lowercased()
            lastRecognizedText = ""
            if text.contains(pauseHotword) {
                isPaused = true
                HotwordService.playPauseOnSound()
                try? FileManager.default.removeItem(at: url)
                outputURL = nil
            } else if text.contains(resumeHotword) {
                isPaused = false
                HotwordService.playPauseOffSound()
                try? FileManager.default.removeItem(at: url)
                outputURL = nil
            } else if isPaused {
                try? FileManager.default.removeItem(at: url)
                outputURL = nil
            } else {
                print("VADService: Aufnahme fertig → \(url.lastPathComponent)")
                onRecordingComplete?(url)
                outputURL = nil
            }
        }

        // Kurze Pause damit AudioSession + Engine sich erholen können, dann weiter überwachen
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.startMonitoring()
            }
        }
    }

    // MARK: - Voice Validator (SFSpeechRecognizer)

    private func startValidation(format: AVAudioFormat) {
        hasValidatedSpeech = false
        validationWordCount = 0
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

        // Nach 2.5s entscheiden — wenn noch kein Wort → wahrscheinlich kein Mensch
        validationTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.hasValidatedSpeech else { return }
                // Kein Wort in 2.5s → als Rauschen markieren (Aufnahme läuft weiter, aber beim Beenden wird verworfen)
                print("VADService: Validierung — kein Wort in 2.5s, markiere als Rauschen")
            }
        }
    }

    private func cancelValidation() {
        validationTimer?.invalidate()
        validationTimer = nil
        validationTask?.cancel()
        validationTask = nil
        validationRequest?.endAudio()
        validationRequest = nil
    }

    // Feed validation buffers
    private func feedValidation(_ buffer: AVAudioPCMBuffer) {
        validationRequest?.append(buffer)
    }

    // MARK: - Helpers

    /// RMS-Energie als dB (approx)
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

    /// Kopiert einen AVAudioPCMBuffer (für Pre-roll)
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
