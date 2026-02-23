import SwiftUI
import AVFoundation

@main
struct HeyOpenClawApp: App {
    
    @StateObject private var voipService = VoIPService()
    @StateObject private var hotwordService = HotwordService()
    @AppStorage("onboardingDone") private var onboardingDone = false
    
    init() {
        VoIPService.configureBackgroundAudio()
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
