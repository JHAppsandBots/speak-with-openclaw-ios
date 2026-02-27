import SwiftUI
import AVFoundation

@main
struct SpeakWithOpenClawApp: App {
    
    @StateObject private var voipService = VoIPService()
    @StateObject private var hotwordService = HotwordService()
    @AppStorage("onboardingDone") private var onboardingDone = false
    
    init() {
        // EINMALIGE Audio-Session-Konfiguration — kein Service darf danach setCategory aufrufen.
        // Das löst das Route-Wechsel-Problem (Kopfhörer → Lautsprecher).
        Task { @MainActor in
            AudioSessionManager.shared.configure()
            BackgroundKeepAlive.shared.start()
        }
    }
    
    var body: some Scene {
        WindowGroup {
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
    }
}
