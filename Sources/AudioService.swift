import Foundation
import AVFoundation

/// AudioService — Aufnahme via AVAudioRecorder + Playback via AVAudioPlayer.
/// AudioSessionManager.shared ist Single Source of Truth für die Session.
@MainActor
class AudioService: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var isPlaying  = false
    @Published var isPaused   = false   // pausiert (nicht beendet) — Wiedergabe fortsetzbar

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var playbackWatchdog: Task<Void, Never>?
    private(set) var currentURL: URL?   // zuletzt gespielte Datei

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Recording

    func startRecording() throws -> URL {
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
        AudioSessionManager.shared.ensureActive()
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()       // Hardware aufwecken → kein Knacken beim ersten Sample
        audioPlayer = player
        currentURL = url
        isPlaying = true
        isPaused = false
        // 40ms warten → Hardware ist warm → sauberer Start ohne Knacken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.audioPlayer?.play()
        }
        startPlaybackWatchdog()
    }

    func pause() {
        guard isPlaying, !isPaused else { return }
        audioPlayer?.pause()
        isPaused = true
    }

    func resume() {
        guard isPlaying, isPaused else { return }
        AudioSessionManager.shared.ensureActive()
        audioPlayer?.play()
        isPaused = false
    }

    func stop() {
        playbackWatchdog?.cancel(); playbackWatchdog = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPaused = false
    }

    /// Watchdog gegen hängenden `isPlaying`-Zustand: feuert das `didFinishPlaying`-Delegate
    /// nicht (z.B. Route-Wechsel/Unterbrechung mitten in der Wiedergabe), bliebe die App sonst
    /// dauerhaft „beschäftigt" → Hör-Modus käme nie zurück → Neustart nötig. Hier erkennen wir
    /// das fertige/gestoppte Abspielen aktiv und räumen den Zustand auf.
    private func startPlaybackWatchdog() {
        playbackWatchdog?.cancel()
        playbackWatchdog = Task { @MainActor [weak self] in
            // while let self: hält self pro Iteration stark, re-checkt isPlaying am Schleifenkopf.
            while let self, self.isPlaying {
                try? await Task.sleep(for: .milliseconds(500))
                if self.isPaused { continue }                  // pausiert → weiter warten
                if !(self.audioPlayer?.isPlaying ?? false) {   // läuft nicht mehr & nicht pausiert → fertig
                    self.isPlaying = false
                    self.isPaused = false
                    return
                }
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.isPaused = false
        }
    }
}

// MARK: - Temp-Datei-Aufräumung

/// Im Dauerbetrieb (Gesprächsmodus) sammeln sich Aufnahme-/Antwort-Dateien im temporaryDirectory.
/// Einmal beim App-Start aufräumen hält den Speicher sauber, ohne laufende Wiedergabe zu stören.
enum TempCleanup {
    static func purgeOldAudio() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let prefixes = ["botvoice_", "vad_recording_", "relay_reply_", "relay_text_reply_"]
        guard let files = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for url in files where prefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) {
            try? fm.removeItem(at: url)
        }
    }
}
