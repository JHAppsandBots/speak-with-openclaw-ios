import Foundation
import AVFoundation
import UIKit
import Combine

/// AudioSessionManager — Single Source of Truth für die AVAudioSession.
///
/// Löst zwei Probleme:
/// 1. Hintergrund/Sperrzustand: Session wird EINMAL konfiguriert und bleibt aktiv.
///    Kein Service darf setCategory/setActive selbst aufrufen.
/// 2. Audio-Route: Weil setCategory nur einmal aufgerufen wird, bleibt die Route stabil.
///    iOS evaluiert die Route nur bei setCategory → weniger Aufrufe = stabile Route.
///
/// Regel: ALLE Audio-Services (VAD, AudioService, HotwordService, Playback) nutzen
/// AudioSessionManager.shared statt direkt AVAudioSession.
@MainActor
class AudioSessionManager: ObservableObject {

    static let shared = AudioSessionManager()

    @Published var isConfigured = false
    @Published var currentRoute: String = ""

    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    // MARK: - Einmalige Konfiguration

    /// Wird einmal beim App-Start aufgerufen. Danach nie wieder setCategory.
    func configure() {
        guard !isConfigured else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // EINMALIGER setCategory-Aufruf:
            // - .playAndRecord: Aufnahme + Wiedergabe
            // - mode: .default: kein spezieller Modus (voiceChat stört Bluetooth)
            // - .allowBluetoothHFP: AirPods/Bluetooth-Headset Mikrofon
            // - .allowBluetoothA2DP: Bluetooth-Audio-Ausgabe
            // - .mixWithOthers: andere Audio-Apps nicht unterbrechen
            //
            // KEIN .defaultToSpeaker — iOS wählt automatisch:
            //   Kopfhörer verbunden → Kopfhörer (Input + Output)
            //   Nichts verbunden → eingebautes Mikrofon + Lautsprecher (über Earpiece)
            //
            // Für Lautsprecher-Output OHNE Kopfhörer: overrideOutputAudioPort(.speaker)
            // wird nur einmal beim Start gesetzt falls keine Kopfhörer da sind.
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true, options: [])

            // Wenn keine externen Geräte → Lautsprecher statt Earpiece
            let hasExternal = session.currentRoute.outputs.contains {
                $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP ||
                $0.portType == .headphones   || $0.portType == .airPlay
            }
            if !hasExternal {
                try session.overrideOutputAudioPort(.speaker)
                print("AudioSessionManager: Kein externes Gerät → Lautsprecher aktiviert")
            }

            isConfigured = true
            updateRouteInfo()
            print("AudioSessionManager: Konfiguriert ✅ Route: \(currentRoute)")

        } catch {
            print("AudioSessionManager: FEHLER \(error)")
        }

        // Route-Änderungen beobachten (Kopfhörer ein-/ausstecken)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
            }
        }

        // Audio-Unterbrechungen (Telefonanruf, Siri, etc.)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }
    }

    // MARK: - Sicherstellen dass Session aktiv ist

    /// Services rufen das auf statt setCategory/setActive.
    /// Aktiviert die Session nur wenn nötig — ändert NICHT die Kategorie.
    func ensureActive() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Nur setActive — KEIN setCategory. Route bleibt stabil.
            try session.setActive(true, options: [])
        } catch {
            print("AudioSessionManager: ensureActive Fehler \(error)")
        }
    }

    // MARK: - Route-Handling

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        let session = AVAudioSession.sharedInstance()
        updateRouteInfo()

        switch reason {
        case .newDeviceAvailable:
            // Kopfhörer eingesteckt → Override aufheben, iOS nutzt automatisch Kopfhörer
            try? session.overrideOutputAudioPort(.none)
            print("AudioSessionManager: Neues Gerät → \(currentRoute)")

        case .oldDeviceUnavailable:
            // Kopfhörer rausgenommen → Lautsprecher aktivieren
            try? session.overrideOutputAudioPort(.speaker)
            print("AudioSessionManager: Gerät entfernt → Lautsprecher. Route: \(currentRoute)")

        default:
            print("AudioSessionManager: Route-Change (\(reason.rawValue)) → \(currentRoute)")
        }
    }

    // MARK: - Interruption-Handling

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            print("AudioSessionManager: ⚠️ Audio-Unterbrechung (Anruf/Siri)")

        case .ended:
            print("AudioSessionManager: Audio-Unterbrechung beendet → Session reaktivieren")
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true, options: [])
            updateRouteInfo()

        @unknown default: break
        }
    }

    // MARK: - Helpers

    private func updateRouteInfo() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map { "\($0.portName)[\($0.portType.rawValue)]" }.joined(separator: ",")
        let outputs = route.outputs.map { "\($0.portName)[\($0.portType.rawValue)]" }.joined(separator: ",")
        currentRoute = "IN:\(inputs) OUT:\(outputs)"
    }
}
