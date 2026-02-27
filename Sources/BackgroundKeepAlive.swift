import Foundation
import AVFoundation
import UIKit

/// BackgroundKeepAlive — hält die App aktiv wenn sie im Hintergrund läuft oder das Telefon gesperrt ist.
///
/// Mechanismen:
/// 1. idleTimerDisabled — verhindert Bildschirm-Abschalten während App offen ist
/// 2. beginBackgroundTask — iOS darf uns während Aufnahme/Senden nicht suspendieren
/// 3. Watchdog-Timer — erkennt wenn VAD hängt und startet neu
///
/// Kein stiller Audio-Loop nötig — UIBackgroundModes: audio + voip in Info.plist
/// erlauben Hintergrund-Betrieb offiziell solange AVAudioSession aktiv ist.
@MainActor
class BackgroundKeepAlive: ObservableObject {

    static let shared = BackgroundKeepAlive()

    private var watchdogTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // Watchdog-Callback — MainViewModel setzt diesen
    var onWatchdogFired: (() -> Void)?

    // MARK: - Start/Stop

    func start() {
        UIApplication.shared.isIdleTimerDisabled = true
        startWatchdog()
        print("BackgroundKeepAlive: gestartet ✓")
    }

    func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        endBackgroundTask()
        print("BackgroundKeepAlive: gestoppt")
    }

    // MARK: - Background Task

    func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BotVoiceAudio") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundTask()
                self?.beginBackgroundTask()
            }
        }
    }

    func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Watchdog

    /// Prüft alle 8 Sekunden ob VAD noch aktiv ist.
    /// Callback entscheidet was zu tun ist — greift nie während Aufnahme/Playback.
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onWatchdogFired?()
            }
        }
    }
}
