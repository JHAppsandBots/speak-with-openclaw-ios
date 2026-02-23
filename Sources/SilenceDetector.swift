import Foundation
import Speech
import AVFoundation

/// SilenceDetector — Erkennt wann der Nutzer aufgehört hat zu sprechen
/// Nutzt SpeechRecognizer: sobald X Sekunden keine neuen Wörter kommen → Callback
/// Einstellbar: 1-5 Sekunden Stille-Schwelle

@MainActor
class SilenceDetector: NSObject, ObservableObject {
    
    // MARK: - Config
    /// Wie viele Sekunden Stille bis automatisch gestoppt wird (1–5s)
    @Published var silenceThreshold: Double = 2.0
    
    // MARK: - Callback
    var onSilenceDetected: (() -> Void)?
    
    // MARK: - Private
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var lastTranscriptLength = 0
    private var hasSpeechStarted = false
    
    override init() {
        super.init()
        // Gleiche Locale wie HotwordService
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    }
    
    // MARK: - Start / Stop
    
    /// Startet die Stille-Erkennung parallel zur Aufnahme
    func start() throws {
        stop()
        hasSpeechStarted = false
        lastTranscriptLength = 0
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let newLength = result.bestTranscription.formattedString.count
                    if newLength > self.lastTranscriptLength {
                        // Neue Wörter → Sprechen erkannt → Timer neu starten
                        self.lastTranscriptLength = newLength
                        self.hasSpeechStarted = true
                        self.resetSilenceTimer()
                    }
                }
            }
        }
        
        // Fallback: Wenn nach 8s noch gar nichts gesprochen → abbrechen
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, !self.hasSpeechStarted else { return }
            self.onSilenceDetected?()
        }
    }
    
    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }
    
    // MARK: - Timer
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: silenceThreshold,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.hasSpeechStarted else { return }
                self.stop()
                self.onSilenceDetected?()
            }
        }
    }
}
