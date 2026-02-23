import Foundation

/// Telegram Bot API Service (Legacy — wird in der Relay-Architektur nicht mehr direkt verwendet)
/// Die App kommuniziert über einen lokalen Relay-Server (voice-relay-server.py),
/// der seinerseits als Telegram-User-Account Nachrichten an die Bots schickt.
class TelegramService: ObservableObject {

    // MARK: - Config
    let botToken: String
    let chatId: String
    private var baseURL: String { "https://api.telegram.org/bot\(botToken)" }
    private var lastUpdateId: Int = 0

    init(botToken: String, chatId: String = "") {
        self.botToken = botToken
        self.chatId = chatId
    }

    // MARK: - Voice senden

    func sendVoice(audioURL: URL) async throws -> TelegramMessage {
        let url = URL(string: "\(baseURL)/sendVoice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(chatId)\r\n".data(using: .utf8)!)

        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"voice\"; filename=\"voice.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TelegramResponse<TelegramMessage>.self, from: data)
        guard response.ok, let message = response.result else {
            throw TelegramError.sendFailed
        }
        return message
    }

    // MARK: - Auf Bot-Antwort warten

    func waitForBotReply(timeoutSeconds: Int = 30) async throws -> TelegramMessage? {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < Double(timeoutSeconds) {
            let updates = try await getUpdates(offset: lastUpdateId + 1, timeout: 5)

            for update in updates {
                lastUpdateId = max(lastUpdateId, update.updateId)
                // Bot-Antworten kommen vom Bot selbst (isBot == true)
                if let msg = update.message, msg.from?.isBot == true {
                    return msg
                }
            }

            try await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    func getUpdates(offset: Int = 0, timeout: Int = 0) async throws -> [TelegramUpdate] {
        let urlStr = "\(baseURL)/getUpdates?offset=\(offset)&timeout=\(timeout)&allowed_updates=%5B%22message%22%5D"
        var request = URLRequest(url: URL(string: urlStr)!)
        request.timeoutInterval = Double(timeout) + 5
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TelegramResponse<[TelegramUpdate]>.self, from: data)
        return response.result ?? []
    }

    // MARK: - Voice herunterladen

    func downloadVoice(fileId: String) async throws -> URL {
        let fileUrl = URL(string: "\(baseURL)/getFile?file_id=\(fileId)")!
        let (fileData, _) = try await URLSession.shared.data(from: fileUrl)
        let fileResponse = try JSONDecoder().decode(TelegramResponse<TelegramFile>.self, from: fileData)
        guard let filePath = fileResponse.result?.filePath else {
            throw TelegramError.downloadFailed
        }

        let downloadUrl = URL(string: "https://api.telegram.org/file/bot\(botToken)/\(filePath)")!
        let (audioData, _) = try await URLSession.shared.data(from: downloadUrl)

        let ext = (filePath as NSString).pathExtension.isEmpty ? "ogg" : (filePath as NSString).pathExtension
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("bot_reply_\(Date().timeIntervalSince1970).\(ext)")
        try audioData.write(to: tempUrl)
        return tempUrl
    }

    // MARK: - Verbindungstest

    func getMe() async throws -> TelegramUser {
        let url = URL(string: "\(baseURL)/getMe")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TelegramResponse<TelegramUser>.self, from: data)
        guard let user = response.result else { throw TelegramError.sendFailed }
        return user
    }
}

// MARK: - Telegram API Models

struct TelegramResponse<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
}

struct TelegramUser: Decodable {
    let id: Int
    let firstName: String
    let username: String?
    let isBot: Bool
    enum CodingKeys: String, CodingKey {
        case id; case firstName = "first_name"; case username; case isBot = "is_bot"
    }
}

struct TelegramChat: Decodable { let id: Int }

struct TelegramMessage: Decodable {
    let messageId: Int
    let from: TelegramUser?
    let chat: TelegramChat?
    let voice: TelegramVoice?
    let audio: TelegramVoice?
    let text: String?
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"; case from; case chat; case voice; case audio; case text
    }
}

struct TelegramVoice: Decodable {
    let fileId: String
    let duration: Int
    let mimeType: String?
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"; case duration; case mimeType = "mime_type"
    }
}

struct TelegramFile: Decodable {
    let filePath: String?
    enum CodingKeys: String, CodingKey { case filePath = "file_path" }
}

struct TelegramUpdate: Decodable {
    let updateId: Int
    let message: TelegramMessage?
    enum CodingKeys: String, CodingKey { case updateId = "update_id"; case message }
}

enum TelegramError: Error, LocalizedError {
    case sendFailed, downloadFailed, notConnected
    var errorDescription: String? {
        switch self {
        case .sendFailed:    return "Nachricht konnte nicht gesendet werden"
        case .downloadFailed: return "Audio konnte nicht heruntergeladen werden"
        case .notConnected:  return "Kein Bot ausgewählt"
        }
    }
}
