import Foundation

/// A bot the user wants to talk to
struct Bot: Identifiable, Codable {
    let id: UUID
    var name: String
    var botToken: String
    var username: String  // Telegram @username
    var emoji: String

    init(id: UUID = UUID(), name: String, botToken: String = "", username: String, emoji: String = "🤖") {
        self.id = id
        self.name = name
        self.botToken = botToken
        self.username = username
        self.emoji = emoji
    }
}

extension Bot {
    /// No presets — user enters their own bot credentials during onboarding.
    static let presets: [Bot] = []

    static func saveAll(_ bots: [Bot]) {
        if let data = try? JSONEncoder().encode(bots) {
            UserDefaults.standard.set(data, forKey: "savedBots")
        }
    }

    static func loadAll() -> [Bot] {
        guard let data = UserDefaults.standard.data(forKey: "savedBots"),
              let bots = try? JSONDecoder().decode([Bot].self, from: data) else {
            return presets
        }
        return bots
    }
}

/// Conversation message
struct Message: Identifiable {
    let id: UUID
    let text: String?
    let audioURL: URL?
    let isFromUser: Bool
    let timestamp: Date

    init(id: UUID = UUID(), text: String?, audioURL: URL? = nil, isFromUser: Bool, timestamp: Date = .now) {
        self.id = id
        self.text = text
        self.audioURL = audioURL
        self.isFromUser = isFromUser
        self.timestamp = timestamp
    }
}
