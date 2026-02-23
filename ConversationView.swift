import SwiftUI
import AVFoundation

/// Konversations-Verlauf
struct ConversationView: View {
    
    let messages: [Message]
    var onSendText: ((String) -> Void)?

    @State private var playingId: UUID?
    @State private var player: AVAudioPlayer?
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    init(messages: [Message], onSendText: ((String) -> Void)? = nil) {
        self.messages = messages
        self.onSendText = onSendText
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isPlaying: playingId == message.id,
                                onPlay: { playAudio(message: message) }
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            
            // MARK: - Text Input Bar
            Divider()
                .background(Color.white.opacity(0.15))
            
            HStack(spacing: 10) {
                TextField(L("Nachricht...", "Message..."), text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.15))
                    .clipShape(.rect(cornerRadius: 20))
                    .foregroundStyle(.white)
                    .tint(.indigo)
                    .keyboardType(.default)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit { sendText() }
                
                // Send Button
                Button(action: sendText) {
                    Image(systemName: inputText.trimmingCharacters(in: .whitespaces).isEmpty
                          ? "arrow.up.circle"
                          : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.gray
                            : Color.indigo
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                .animation(.easeInOut(duration: 0.15), value: inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black)
        }
        .navigationTitle(L("Verlauf", "History"))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black)
    }
    
    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSendText?(text)
        inputText = ""
    }
    
    private func playAudio(message: Message) {
        guard let url = message.audioURL else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            playingId = message.id
        } catch {
            print("Playback error: \(error)")
        }
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: Message
    let isPlaying: Bool
    let onPlay: () -> Void
    
    var body: some View {
        HStack {
            if message.isFromUser { Spacer(minLength: 60) }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 6) {

                // Audio-Player (wenn vorhanden) — immer zuerst anzeigen
                if message.audioURL != nil {
                    Button(action: onPlay) {
                        HStack(spacing: 8) {
                            Image(systemName: isPlaying ? "waveform" : "play.circle.fill")
                                .font(.title3)
                            Text(isPlaying ? L("Spielt...", "Playing...") : L("Abspielen", "Play"))
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(message.isFromUser ? Color.indigo.opacity(0.7) : Color(white: 0.25))
                        .foregroundStyle(.white)
                        .clipShape(.capsule)
                    }
                }

                // Transkript-Text (wenn vorhanden) — darunter anzeigen
                if let text = message.text, !text.isEmpty {
                    Text(text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.isFromUser ? Color.indigo : Color(white: 0.18))
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: 18))
                        .font(.body)
                }

                // Fallback: wenn weder Audio noch Text (sollte nicht vorkommen)
                if message.audioURL == nil && (message.text == nil || message.text!.isEmpty) {
                    Text(L("(kein Inhalt)", "(no content)"))
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .italic()
                }
                
                // Timestamp
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            
            if !message.isFromUser { Spacer(minLength: 60) }
        }
    }
}

#Preview {
    NavigationStack {
        ConversationView(
            messages: [
                // Nur Text
                Message(text: "Hey Friedrich!", isFromUser: true),
                // Nur Audio (z.B. Aufnahme ohne Transkript)
                Message(text: nil, audioURL: URL(string: "file:///tmp/test.m4a"), isFromUser: true),
                // Text + Audio (Aufnahme mit Transkript)
                Message(text: "Was ist das Wetter heute?", audioURL: URL(string: "file:///tmp/test2.m4a"), isFromUser: true),
                // Bot-Antwort: nur Text
                Message(text: "Hallo Johannes, wie kann ich helfen?", isFromUser: false),
                // Bot-Antwort: Audio + Transkript
                Message(text: "Das Wetter ist heute sonnig mit 18 Grad.", audioURL: URL(string: "file:///tmp/reply.ogg"), isFromUser: false),
            ],
            onSendText: { text in print("Send: \(text)") }
        )
    }
    .preferredColorScheme(.dark)
}
