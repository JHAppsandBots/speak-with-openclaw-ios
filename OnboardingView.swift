import SwiftUI

/// Onboarding — erscheint beim ersten Start
/// Führt Schritt für Schritt durch das Setup
struct OnboardingView: View {
    
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var currentStep = 0
    
    private var steps: [OnboardingStep] {
        [
            OnboardingStep(
                icon: "🦞",
                title: L("Willkommen bei\nSpeak with OpenClaw", "Welcome to\nSpeak with OpenClaw"),
                description: L(
                    "Sprich mit deinen KI-Bots auf Telegram — freihändig, wie mit Siri.",
                    "Talk to your AI bots on Telegram — hands-free, like Siri."
                ),
                detail: nil
            ),
            OnboardingStep(
                icon: "🖥️",
                title: L("Was du brauchst", "What you need"),
                description: L(
                    "Speak with OpenClaw ist eine App-Oberfläche. Du brauchst einen laufenden KI-Bot im Hintergrund.",
                    "Speak with OpenClaw is an app interface. You need a running AI bot in the background."
                ),
                detail: L(
                    "• Einen Mac mit OpenClaw\n• Einen Telegram-Bot (kostenlos)\n• Claude API Key (von Anthropic)",
                    "• A Mac with OpenClaw\n• A Telegram bot (free)\n• Claude API Key (from Anthropic)"
                )
            ),
            OnboardingStep(
                icon: "🤖",
                title: L("Schritt 1: Bot erstellen", "Step 1: Create bot"),
                description: L(
                    "Öffne Telegram und schreibe @BotFather.",
                    "Open Telegram and message @BotFather."
                ),
                detail: L(
                    "1. /newbot eingeben\n2. Namen vergeben (z.B. \"Mein KI-Bot\")\n3. Bot-Token kopieren — den brauchst du gleich",
                    "1. Type /newbot\n2. Choose a name (e.g. \"My AI Bot\")\n3. Copy the bot token — you'll need it shortly"
                )
            ),
            OnboardingStep(
                icon: "🖥️",
                title: L("Schritt 2: OpenClaw einrichten", "Step 2: Set up OpenClaw"),
                description: L(
                    "Installiere OpenClaw auf deinem Mac und verbinde deinen Bot.",
                    "Install OpenClaw on your Mac and connect your bot."
                ),
                detail: L(
                    "Die vollständige Anleitung findest du auf GitHub:\ngithub.com/JHAppsandBots/speak-with-openclaw-ios\n\nDort gibt es auch eine fertige Beispiel-Config die du nur anpassen musst.",
                    "Full instructions on GitHub:\ngithub.com/JHAppsandBots/speak-with-openclaw-ios\n\nA ready-made example config is available — just customize it."
                )
            ),
            OnboardingStep(
                icon: "🎤",
                title: L("Schritt 3: Token eintragen", "Step 3: Enter token"),
                description: L(
                    "Trag deinen Bot-Token in den Einstellungen ein — dann kann die App mit deinem Bot sprechen.",
                    "Enter your bot token in Settings — then the app can talk to your bot."
                ),
                detail: L(
                    "Einstellungen → Bot-Token einfügen → Verbindung testen",
                    "Settings → Paste bot token → Test connection"
                )
            ),
            OnboardingStep(
                icon: "✅",
                title: L("Fertig!", "Ready!"),
                description: L(
                    "Halte den Mikrofon-Button gedrückt und sprich. Oder aktiviere das Hotword für freihändige Bedienung.",
                    "Hold the microphone button and speak. Or enable hotword for hands-free use."
                ),
                detail: L(
                    "Tipp: Sag \"Hey Bot\" um die App zu aktivieren ohne den Bildschirm zu berühren.",
                    "Tip: Say \"Hey Bot\" to activate the app without touching the screen."
                )
            )
        ]
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // Progress Dots
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Color.indigo : Color.gray.opacity(0.4))
                            .frame(width: i == currentStep ? 10 : 6, height: i == currentStep ? 10 : 6)
                            .animation(.spring(duration: 0.3), value: currentStep)
                    }
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Content
                TabView(selection: $currentStep) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        StepView(step: step)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: currentStep)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    if currentStep < steps.count - 1 {
                        Button {
                            withAnimation { currentStep += 1 }
                        } label: {
                            Text(L("Weiter", "Next"))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [.indigo, .purple],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(.rect(cornerRadius: 14))
                        }
                        
                        if currentStep > 0 {
                            Button(L("Überspringen", "Skip")) {
                                onboardingDone = true
                            }
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        }
                    } else {
                        Button {
                            onboardingDone = true
                        } label: {
                            Text(L("Los geht's!", "Let's go!"))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [.green, .teal],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(.rect(cornerRadius: 14))
                        }
                        
                        Link(destination: URL(string: "https://github.com/JHAppsandBots/speak-with-openclaw-ios")!) {
                            Label(L("Setup-Anleitung auf GitHub", "Setup guide on GitHub"),
                                  systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                                .foregroundStyle(.indigo)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Step View

struct StepView: View {
    let step: OnboardingStep
    
    var body: some View {
        VStack(spacing: 24) {
            Text(step.icon)
                .font(.system(size: 80))
            
            Text(step.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            
            Text(step.description)
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            if let detail = step.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.horizontal, 24)
            }
        }
        .padding()
    }
}

// MARK: - Model

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let detail: String?
}

#Preview {
    OnboardingView()
}
