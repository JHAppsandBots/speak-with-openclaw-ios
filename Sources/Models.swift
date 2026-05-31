import Foundation
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

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
    /// No presets — the user adds their own bots during onboarding
    /// (keine personenbezogenen Bot-Handles im öffentlichen Repo).
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

// MARK: - Markdown-Export (Teilen → in Dateien sichern)

/// Teilbares Markdown-Dokument des Chat-Verlaufs. Die Datei wird erst beim tatsächlichen
/// Teilen geschrieben (nicht bei jedem View-Render), und mit `.md`-Endung in Dateien speicherbar.
struct ChatMarkdownFile: Transferable {
    let messages: [Message]
    let botName: String

    private var filename: String {
        let safe = botName.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        return "Speak with Claw – \(safe).md"
    }

    func markdown() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "dd.MM.yyyy, HH:mm"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"

        var out = "# Chat mit \(botName)\n\n"
        out += "_Exportiert am \(df.string(from: Date())) · Speak with Claw_\n\n---\n\n"
        for m in messages {
            let who = m.isFromUser ? "Du" : botName
            out += "**\(who)** · \(tf.string(from: m.timestamp))\n\n"
            if let t = m.text, !t.isEmpty {
                out += t + "\n\n"
            } else if m.audioURL != nil {
                out += "_(Sprachnachricht)_\n\n"
            }
        }
        return out
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { doc in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.filename)
            try doc.markdown().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

/// Teilbares reines Textdokument (.txt) des Chat-Verlaufs — ohne Markdown-Zeichen.
struct ChatTextFile: Transferable {
    let messages: [Message]
    let botName: String

    private var filename: String {
        let safe = botName.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        return "Speak with Claw – \(safe).txt"
    }

    func plainText() -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "de_DE"); df.dateFormat = "dd.MM.yyyy, HH:mm"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"

        var out = "Chat mit \(botName)\nExportiert am \(df.string(from: Date())) · Speak with Claw\n"
        out += String(repeating: "—", count: 24) + "\n\n"
        for m in messages {
            let who = m.isFromUser ? "Du" : botName
            out += "\(who) · \(tf.string(from: m.timestamp))\n"
            if let t = m.text, !t.isEmpty {
                out += t + "\n\n"
            } else if m.audioURL != nil {
                out += "(Sprachnachricht)\n\n"
            }
        }
        return out
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { doc in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.filename)
            try doc.plainText().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
