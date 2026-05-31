import UIKit

/// Dezentes haptisches Feedback für ein reaktionsschnelles, hochwertiges Gefühl.
/// Bewusst sparsam (KISS): nur an den vier Schlüsselmomenten der Sprach-Interaktion.
@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let soft   = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()

    /// Generatoren vorwärmen — macht den ersten Impuls spürbar latenzärmer.
    static func prepare() {
        impact.prepare()
        soft.prepare()
        notify.prepare()
    }

    /// Aufnahme beginnt (manueller Druck oder VAD-Spracherkennung).
    static func recordStart() {
        impact.impactOccurred(intensity: 0.9)
        impact.prepare()
    }

    /// Sprachnachricht wird abgeschickt.
    static func sendTap() {
        soft.impactOccurred(intensity: 0.7)
        soft.prepare()
    }

    /// Hotword bzw. Sprache erkannt — sanfter Hinweis.
    static func detected() {
        soft.impactOccurred(intensity: 0.5)
    }

    /// Antwort des Bots ist da — kurzer Erfolgs-Impuls.
    static func replyArrived() {
        notify.notificationOccurred(.success)
        notify.prepare()
    }
}
