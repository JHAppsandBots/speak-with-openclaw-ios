import SwiftUI

/// Bot-Auswahl Screen
struct BotSelectView: View {

    @Binding var selectedBot: Bot?
    @State private var bots: [Bot] = []
    @State private var showAddBot = false
    @State private var showEditBot: Bot? = nil
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
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteBot(bot)
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                    Button {
                        showEditBot = bot
                    } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .navigationTitle(L("Bot wählen", "Choose Bot"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddBot = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddBot) {
            BotEditView(bot: nil) { newBot in
                bots.append(newBot)
                Bot.saveAll(bots)
            }
        }
        .sheet(item: $showEditBot) { bot in
            BotEditView(bot: bot) { updatedBot in
                if let idx = bots.firstIndex(where: { $0.id == updatedBot.id }) {
                    bots[idx] = updatedBot
                    Bot.saveAll(bots)
                }
            }
        }
        .onAppear {
            bots = Bot.loadAll()
        }
    }

    private func deleteBot(_ bot: Bot) {
        bots.removeAll { $0.id == bot.id }
        Bot.saveAll(bots)
        if selectedBot?.id == bot.id {
            selectedBot = bots.first
        }
    }
}

/// Bot hinzufügen / bearbeiten
struct BotEditView: View {
    let bot: Bot?
    let onSave: (Bot) -> Void

    @State private var name: String
    @State private var username: String
    @State private var botToken: String
    @State private var emoji: String
    @Environment(\.dismiss) private var dismiss

    init(bot: Bot?, onSave: @escaping (Bot) -> Void) {
        self.bot = bot
        self.onSave = onSave
        _name     = State(initialValue: bot?.name ?? "")
        _username = State(initialValue: bot?.username ?? "")
        _botToken = State(initialValue: bot?.botToken ?? "")
        _emoji    = State(initialValue: bot?.emoji ?? "🤖")
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Bot-Infos", "Bot Info")) {
                    HStack {
                        TextField(L("Emoji", "Emoji"), text: $emoji)
                            .frame(width: 50)
                        TextField(L("Name", "Name"), text: $name)
                    }
                    TextField("@username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section(L("Verbindung", "Connection")) {
                    TextField(L("Bot-Token (optional)", "Bot Token (optional)"), text: $botToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(bot == nil ? L("Bot hinzufügen", "Add Bot") : L("Bot bearbeiten", "Edit Bot"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Sichern", "Save")) {
                        let saved = Bot(
                            id: bot?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            botToken: botToken.trimmingCharacters(in: .whitespaces),
                            username: username.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: ""),
                            emoji: emoji.isEmpty ? "🤖" : emoji
                        )
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
