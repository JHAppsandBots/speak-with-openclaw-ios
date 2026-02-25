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
              let bots = try? JSONDecoder().decode([Bot].self, from: data),
              !bots.isEmpty else {
            // No bots saved yet — seed with presets and persist
            saveAll(presets)
            return presets
        }
        return bots
    }
}

/// Conversation message
struct Message: Identifiable, Codable {
    let id: UUID
    let text: String?
    let isFromUser: Bool
    let timestamp: Date

    // audioURL is transient (temp files don't survive app restart) — not persisted
    var audioURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        case id, text, isFromUser, timestamp
    }

    init(id: UUID = UUID(), text: String?, audioURL: URL? = nil, isFromUser: Bool, timestamp: Date = .now) {
        self.id = id
        self.text = text
        self.audioURL = audioURL
        self.isFromUser = isFromUser
        self.timestamp = timestamp
    }
}

// MARK: - Chat History Persistence

struct ChatHistory {
    private static let key = "chatHistories"

    /// Save all bot chat histories
    static func saveAll(_ histories: [UUID: [Message]]) {
        // Only save messages that have text (skip audio-only)
        let textHistories = histories.mapValues { messages in
            messages.filter { $0.text != nil && !($0.text?.isEmpty ?? true) }
        }
        if let data = try? JSONEncoder().encode(textHistories) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Load all bot chat histories
    static func loadAll() -> [UUID: [Message]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let histories = try? JSONDecoder().decode([UUID: [Message]].self, from: data) else {
            return [:]
        }
        return histories
    }

    /// Delete all chat histories
    static func deleteAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
