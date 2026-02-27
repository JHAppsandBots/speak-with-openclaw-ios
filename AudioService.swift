import Foundation
import AVFoundation

/// AudioService — Aufnahme via AVAudioRecorder + Playback via AVAudioPlayer.
/// Session bleibt dauerhaft aktiv (Background-Modus).
@MainActor
class AudioService: NSObject, ObservableObject {
    
    @Published var isRecording = false
    @Published var isPlaying  = false
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    
    // MARK: - Permissions
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - Recording
    
    func startRecording() throws -> URL {
        // Session wird NICHT hier konfiguriert — AudioSessionManager.shared ist Single Source of Truth.
        AudioSessionManager.shared.ensureActive()
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("botvoice_\(Date().timeIntervalSince1970).m4a")
        recordingURL = url
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        // Debug: Aktive Input-Route loggen → in Xcode Console sichtbar
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
        print("🎙️ AudioService: Aufnahme startet — Input: \(inputs.isEmpty ? "keiner?" : inputs)")

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.record()
        isRecording = true
        return url
    }
    
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        return recordingURL
    }
    
    // MARK: - Playback
    
    func play(url: URL) throws {
        // Session aktiv halten — keine Neukonfiguration, Route bleibt stabil.
        AudioSessionManager.shared.ensureActive()
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        // prepareToPlay() weckt die Hardware auf, ohne Ton zu erzeugen.
        // 40ms warten → Hardware ist warm → kein Knacken beim ersten Sample
        player.prepareToPlay()
        audioPlayer = player
        isPlaying = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.audioPlayer?.play()
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
