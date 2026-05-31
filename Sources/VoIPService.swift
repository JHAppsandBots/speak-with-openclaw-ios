import Foundation
import PushKit

/// VoIPService — Hält die App im Hintergrund aktiv (auch bei gesperrtem Handy)
/// Nutzt PushKit VoIP Push um im Hintergrund zu bleiben
/// Das ist der gleiche Mechanismus wie WhatsApp/Signal/FaceTime

class VoIPService: NSObject, ObservableObject, PKPushRegistryDelegate {
    
    // MARK: - State
    @Published var isRegistered = false
    var voipToken: Data?
    
    private var pushRegistry: PKPushRegistry?
    var onWakeReceived: (() -> Void)?
    
    // MARK: - Setup
    
    func register() {
        pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry?.delegate = self
        pushRegistry?.desiredPushTypes = [.voIP]
    }
    
    // MARK: - PKPushRegistryDelegate
    
    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        voipToken = pushCredentials.token
        isRegistered = true
        print("VoIP Token: \(pushCredentials.token.map { String(format: "%02x", $0) }.joined())")
    }
    
    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        // App wird geweckt — Hotword-Service starten
        print("VoIP Push received: \(payload.dictionaryPayload)")
        onWakeReceived?()
        completion()
    }
    
    func pushRegistry(_ registry: PKPushRegistry,
                      didInvalidatePushTokenFor type: PKPushType) {
        voipToken = nil
        isRegistered = false
    }
}
