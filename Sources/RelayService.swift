import Foundation

/// Voice Relay Service — kommuniziert mit dem Mac-Server statt Telegram direkt
/// Der Server läuft auf dem Mac und sendet als Johannes' Account
class RelayService {

    var serverURL: String  // z.B. "http://192.168.0.7:18800"
    var botUsername: String

    init(serverURL: String, botUsername: String) {
        self.serverURL = serverURL
        self.botUsername = botUsername
    }

    // MARK: - Health Check

    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(serverURL)/health") else { return false }
        let result = try? await URLSession.shared.data(from: url)
        return result != nil
    }

    // MARK: - Text senden + Antwort empfangen

    /// Schickt Text an den Mac-Server, wartet auf Bot-Antwort
    func sendText(text: String) async throws -> RelayReply {
        guard let url = URL(string: "\(serverURL)/text") else {
            throw RelayError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300  // max 5min — Server kann bis zu 120+30+90s brauchen
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Form-encoded body: text=...&bot=...
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let encodedBot  = botUsername.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? botUsername
        request.httpBody = "text=\(encodedText)&bot=\(encodedBot)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RelayError.invalidResponse
        }

        if http.statusCode == 408 {
            throw RelayError.timeout
        }

        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
            throw RelayError.serverError(msg)
        }

        // JSON Response parsen
        guard let json = try? JSONDecoder().decode(RelayTextResponse.self, from: data), json.ok else {
            throw RelayError.invalidResponse
        }

        if json.type == "voice", let audioB64 = json.audio_b64, let audioData = Data(base64Encoded: audioB64) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("relay_text_reply_\(Date().timeIntervalSince1970).ogg")
            try audioData.write(to: tempURL)
            let botText = (json.text?.isEmpty == false) ? json.text : nil
            return .voice(tempURL, botText, nil)  // Text-Input → kein Transkript
        }

        return .text(json.text ?? "", nil)  // Text-Input → kein Transkript
    }

    // MARK: - Voice senden + Antwort empfangen

    /// Schickt Audio an den Mac-Server, wartet auf Bot-Antwort
    /// Gibt entweder eine Audio-URL (Voice-Antwort) oder Text zurück
    func sendVoice(audioURL: URL) async throws -> RelayReply {
        guard let url = URL(string: "\(serverURL)/voice") else {
            throw RelayError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300  // max 5min — Server kann bis zu 120+30+90s brauchen

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Bot-Username
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"bot\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(botUsername)\r\n".data(using: .utf8)!)

        // Audio
        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        // Content-Type je nach Dateiformat (.caf von VAD, .m4a von AVAudioRecorder)
        let ext = audioURL.pathExtension.lowercased()
        let mime = ext == "caf" ? "audio/x-caf" : ext == "ogg" ? "audio/ogg" : "audio/m4a"
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RelayError.invalidResponse
        }

        if http.statusCode == 408 {
            throw RelayError.timeout
        }

        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
            throw RelayError.serverError(msg)
        }

        // JSON Response parsen
        guard let json = try? JSONDecoder().decode(RelayTextResponse.self, from: data), json.ok else {
            throw RelayError.invalidResponse
        }

        let transcript = (json.transcript?.isEmpty == false) ? json.transcript : nil

        if json.type == "voice", let audioB64 = json.audio_b64, let audioData = Data(base64Encoded: audioB64) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("relay_reply_\(Date().timeIntervalSince1970).ogg")
            try audioData.write(to: tempURL)
            let botText = (json.text?.isEmpty == false) ? json.text : nil
            return .voice(tempURL, botText, transcript)
        }

        return .text(json.text ?? "", transcript)
    }
}

// MARK: - Models

enum RelayReply {
    case voice(URL, String?, String?)  // Audio-URL + Bot-Text + User-Transkript
    case text(String, String?)         // Bot-Text + User-Transkript
}

struct RelayTextResponse: Decodable {
    let ok: Bool
    let type: String?
    let text: String?
    let error: String?
    let audio_b64: String?
    let transcript: String?  // Transkript der Nutzer-Aufnahme
}

enum RelayError: Error, LocalizedError {
    case badURL
    case invalidResponse
    case timeout
    case serverError(String)
    case notReachable

    var errorDescription: String? {
        switch self {
        case .badURL:            return "Server-URL ungültig"
        case .invalidResponse:   return "Ungültige Server-Antwort"
        case .timeout:           return "Bot hat nicht geantwortet (Timeout)"
        case .serverError(let m): return "Server-Fehler: \(m)"
        case .notReachable:      return "Mac nicht erreichbar — gleiches WLAN?"
        }
    }
}
