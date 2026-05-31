import SwiftUI

/// Bot-Auswahl Screen
struct BotSelectView: View {

    @Binding var selectedBot: Bot?
    @State private var bots: [Bot] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(bots) { bot in
                Button {
                    selectedBot = bot
                    dismiss()
                } label: {
                    HStack {
                        Text(bot.emoji)
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text(bot.name)
                                .foregroundStyle(.primary)
                                .fontWeight(.medium)
                            Text("@\(bot.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedBot?.id == bot.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Bot wählen", "Choose Bot"))
        .onAppear {
            bots = Bot.loadAll()
        }
    }
}
