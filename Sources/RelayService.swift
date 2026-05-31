import Foundation

/// Voice Relay Service — kommuniziert mit dem Mac-Server statt Telegram direkt.
/// Der Server (Voice-Relay) läuft auf dem Mac und sendet über dein eigenes Konto.
class RelayService {

    var serverURL: String  // z.B. "http://192.168.0.7:18800"
    var botUsername: String
    var useGateway: Bool = false   // true = /talk (direkt übers Gateway, schnell), false = /voice|/text (Telegram)
    var authToken: String = ""     // Bearer-Token für die Relay-Auth (muss zum Mac .env.voice-relay passen)
    // Ziel: "openclaw" (Standard) oder "claude" (Claude-Terminal-Bridge, isoliert/additiv).
    var target: String = "openclaw"
    var persona: String = "neutral"   // nur für target=claude: Persona-Name oder "neutral"
    // Schieber „Schwer/Normal" (Hauptscreen) — zur Sendezeit gelesen, damit immer aktuell.
    private var modeValue: String { UserDefaults.standard.bool(forKey: "heavyMode") ? "heavy" : "normal" }
    // Claude-Bridge läuft nur über /talk → bei target=claude immer den Gateway-Pfad nutzen.
    private var usesTalkPath: Bool { useGateway || target == "claude" }

    init(serverURL: String, botUsername: String) {
        self.serverURL = serverURL
        self.botUsername = botUsername
    }

    // MARK: - Health Check

    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(serverURL)/health") else { return false }
        var req = URLRequest(url: url); req.timeoutInterval = 8
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200   // sonst meldet jeder fremde Server fälschlich „verbunden"
    }

    /// Validiert die HTTP-Antwort + liefert geparstes JSON — mit klaren, nutzerfreundlichen Fehlern.
    private func decodeReply(_ data: Data, _ response: URLResponse) throws -> RelayTextResponse {
        guard let http = response as? HTTPURLResponse else { throw RelayError.invalidResponse }
        if http.statusCode == 408 { throw RelayError.timeout }
        let parsed = try? JSONDecoder().decode(RelayTextResponse.self, from: data)
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw RelayError.serverError(L("🔒 Relay-Token falsch — in Einstellungen prüfen",
                                               "🔒 Wrong relay token — check Settings"))
            }
            let m = parsed?.error
            throw RelayError.serverError((m?.isEmpty == false) ? m!
                : L("Server-Fehler (HTTP \(http.statusCode))", "Server error (HTTP \(http.statusCode))"))
        }
        guard let json = parsed else { throw RelayError.invalidResponse }
        guard json.ok else {
            let m = json.error
            throw RelayError.serverError((m?.isEmpty == false) ? m! : L("Keine Antwort vom Bot", "No reply from bot"))
        }
        return json
    }

    // MARK: - Text senden + Antwort empfangen

    /// Schickt Text an den Mac-Server, wartet auf Bot-Antwort
    func sendText(text: String) async throws -> RelayReply {
        guard let url = URL(string: "\(serverURL)\(usesTalkPath ? "/talk" : "/text")") else {
            throw RelayError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300  // max 5min — Server kann bis zu 120+30+90s brauchen
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if !authToken.isEmpty { request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization") }

        // Form-encoded body: text=...&bot=...&mode=...&target=...&persona=...
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let encodedBot  = botUsername.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? botUsername
        let encodedPers = persona.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? persona
        request.httpBody = "text=\(encodedText)&bot=\(encodedBot)&mode=\(modeValue)&target=\(target)&persona=\(encodedPers)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try decodeReply(data, response)

        if json.type == "voice", let audioB64 = json.audio_b64, let audioData = Data(base64Encoded: audioB64) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("relay_text_reply_\(Date().timeIntervalSince1970).mp3")
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
        guard let url = URL(string: "\(serverURL)\(usesTalkPath ? "/talk" : "/voice")") else {
            throw RelayError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300  // max 5min — Server kann bis zu 120+30+90s brauchen

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !authToken.isEmpty { request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization") }

        var body = Data()

        // Bot-Username
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"bot\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(botUsername)\r\n".data(using: .utf8)!)

        // Modus (heavy = max. Gehirn-Kraft / normal = gegated)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(modeValue)\r\n".data(using: .utf8)!)

        // Ziel + Persona (Claude-Terminal-Bridge; bei target=openclaw vom Server ignoriert)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"target\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(target)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"persona\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(persona)\r\n".data(using: .utf8)!)

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
        let json = try decodeReply(data, response)

        let transcript = (json.transcript?.isEmpty == false) ? json.transcript : nil

        if json.type == "voice", let audioB64 = json.audio_b64, let audioData = Data(base64Encoded: audioB64) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("relay_reply_\(Date().timeIntervalSince1970).mp3")
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
