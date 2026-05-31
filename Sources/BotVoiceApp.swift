import SwiftUI
import AVFoundation

@main
struct SpeakWithOpenClawApp: App {

    @StateObject private var voipService = VoIPService()
    @StateObject private var hotwordService = HotwordService()
    @AppStorage("onboardingDone") private var onboardingDone = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // EINMALIGE Audio-Session-Konfiguration — kein Service darf danach setCategory aufrufen.
        // Das löst das Route-Wechsel-Problem (Kopfhörer → Lautsprecher).
        // Außerdem alte Temp-Audio-Dateien aufräumen (Dauerbetrieb → sonst läuft der Speicher voll).
        Task { @MainActor in
            AudioSessionManager.shared.configure()
            BackgroundKeepAlive.shared.start()
        }
        TempCleanup.purgeOldAudio()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingDone {
                    MainView(voipService: voipService, hotwordService: hotwordService)
                        .task {
                            voipService.register()
                            let _ = await hotwordService.requestPermissions()
                        }
                } else {
                    OnboardingView()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Rückkehr in den Vordergrund: Audio-Session robust reaktivieren.
                // Verhindert „App muss neu gestartet werden" nach längerem Hintergrund/Lock.
                if newPhase == .active {
                    Task { @MainActor in AudioSessionManager.shared.reactivate() }
                }
            }
        }
    }
}
