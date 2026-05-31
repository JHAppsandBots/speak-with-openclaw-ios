import SwiftUI
import AVFoundation
import UIKit

/// Konversations-Verlauf
struct ConversationView: View {

    let messages: [Message]
    var onSendText: ((String) -> Void)?

    @StateObject private var bubblePlayer = BubblePlayer()
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
                                isPlaying: bubblePlayer.playingId == message.id,
                                onPlay: { bubblePlayer.toggle(message) }
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
            Divider().background(Color.white.opacity(0.15))

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

                Button(action: sendText) {
                    Image(systemName: inputText.trimmingCharacters(in: .whitespaces).isEmpty
                          ? "arrow.up.circle" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Color.gray : Color.indigo)
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
        .onDisappear { bubblePlayer.stop() }
    }

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSendText?(text)
        inputText = ""
    }
}

// MARK: - BubblePlayer

/// Spielt die Audio einer einzelnen Sprechblase ab — mit Delegate, sodass „Spielt..." sauber
/// zurückgesetzt wird und nicht zwei Aufnahmen gleichzeitig laufen (erneutes Tippen = Stop).
@MainActor
final class BubblePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingId: UUID?
    private var player: AVAudioPlayer?

    func toggle(_ message: Message) {
        guard let url = message.audioURL else { return }
        if playingId == message.id { stop(); return }   // läuft bereits → stoppen
        stop()
        do {
            AudioSessionManager.shared.ensureActive()
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            playingId = message.id
        } catch {
            print("BubblePlayer: Wiedergabe-Fehler \(error)")
        }
    }

    func stop() {
        player?.stop(); player = nil; playingId = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playingId = nil }
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
                            Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
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

                // Transkript-Text — auswählbar + per Langdruck kopierbar
                if let text = message.text, !text.isEmpty {
                    Text(text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.isFromUser ? Color.indigo : Color(white: 0.18))
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: 18))
                        .font(.body)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = text
                            } label: {
                                Label(L("Kopieren", "Copy"), systemImage: "doc.on.doc")
                            }
                        }
                }

                // Fallback: weder Audio noch Text (sollte nicht vorkommen)
                if message.audioURL == nil && (message.text == nil || message.text!.isEmpty) {
                    Text(L("(kein Inhalt)", "(no content)"))
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .italic()
                }

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
                Message(text: "Hey Bot!", isFromUser: true),
                Message(text: "Was ist das Wetter heute?", audioURL: URL(string: "file:///tmp/test2.m4a"), isFromUser: true),
                Message(text: "Hallo, wie kann ich helfen?", isFromUser: false),
                Message(text: "Das Wetter ist heute sonnig mit 18 Grad.", audioURL: URL(string: "file:///tmp/reply.ogg"), isFromUser: false),
            ],
            onSendText: { text in print("Send: \(text)") }
        )
    }
    .preferredColorScheme(.dark)
}
