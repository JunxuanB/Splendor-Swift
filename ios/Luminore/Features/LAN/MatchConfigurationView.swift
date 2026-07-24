import LuminoreCore
import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var session: MatchSessionService

    var body: some View {
        Form {
            if let room = session.room {
                Section("config.mode") {
                    modeRow("config.mode.standard", selected: true, enabled: true)
                    modeRow("config.mode.silkRoad", selected: false, enabled: false)
                    modeRow("config.mode.duel", selected: false, enabled: false)
                }
                Section("config.rules") {
                    Stepper(
                        value: scoreBinding(room.configuration),
                        in: 10 ... 30
                    ) {
                        LabeledContent("config.targetScore", value: "\(room.configuration.targetPrestige)")
                    }
                    Toggle("config.timer.enabled", isOn: timerEnabledBinding(room.configuration))
                    if let seconds = room.configuration.turnDurationSeconds {
                        Stepper(value: timerBinding(room.configuration), in: 10 ... 120, step: 5) {
                            LabeledContent("config.timer.seconds", value: "\(seconds)")
                        }
                        Toggle(
                            "config.timer.grace.enabled",
                            isOn: gracePeriodBinding(room.configuration)
                        )
                        Text("config.timer.grace.description")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Toggle(
                        "config.affordableCardHighlight.enabled",
                        isOn: affordableCardHighlightBinding(room.configuration)
                    )
                    Text("config.affordableCardHighlight.description")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if room.participants.count > 4 {
                        Label("config.customLargeTable", systemImage: "person.3.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .disabled(!session.isHost)
                Section("config.ai") {
                    Toggle("config.ai.add", isOn: .constant(false)).disabled(true)
                    Picker("config.ai.difficulty", selection: .constant(BotDifficulty.normal)) {
                        Text("config.ai.easy").tag(BotDifficulty.easy)
                        Text("config.ai.normal").tag(BotDifficulty.normal)
                        Text("config.ai.hard").tag(BotDifficulty.hard)
                    }
                    .disabled(true)
                    Text("common.comingSoon").font(.footnote).foregroundStyle(.secondary)
                }
                if session.isHost {
                    Section {
                        Button("config.start") { session.startGame() }
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Section {
                        ProgressView("config.waitingHost")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .navigationTitle("config.title")
    }

    private func modeRow(_ title: LocalizedStringKey, selected: Bool, enabled: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if !enabled { Text("common.comingSoon").font(.caption).foregroundStyle(.secondary) }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.45))
        }
    }

    private func scoreBinding(_ configuration: GameConfiguration) -> Binding<Int> {
        Binding(
            get: { session.room?.configuration.targetPrestige ?? configuration.targetPrestige },
            set: { score in update(configuration) { $0.targetPrestige = score } }
        )
    }

    private func timerEnabledBinding(_ configuration: GameConfiguration) -> Binding<Bool> {
        Binding(
            get: { session.room?.configuration.turnDurationSeconds != nil },
            set: { enabled in update(configuration) { $0.turnDurationSeconds = enabled ? 30 : nil } }
        )
    }

    private func timerBinding(_ configuration: GameConfiguration) -> Binding<Int> {
        Binding(
            get: { session.room?.configuration.turnDurationSeconds ?? configuration.turnDurationSeconds ?? 30 },
            set: { seconds in update(configuration) { $0.turnDurationSeconds = seconds } }
        )
    }

    private func gracePeriodBinding(_ configuration: GameConfiguration) -> Binding<Bool> {
        Binding(
            get: {
                session.room?.configuration.turnGracePeriodEnabled
                    ?? configuration.turnGracePeriodEnabled
            },
            set: { enabled in update(configuration) { $0.turnGracePeriodEnabled = enabled } }
        )
    }

    private func affordableCardHighlightBinding(_ configuration: GameConfiguration) -> Binding<Bool> {
        Binding(
            get: {
                session.room?.configuration.affordableCardHighlightEnabled
                    ?? configuration.affordableCardHighlightEnabled
            },
            set: { enabled in update(configuration) { $0.affordableCardHighlightEnabled = enabled } }
        )
    }

    private func update(
        _ fallback: GameConfiguration,
        mutation: (inout GameConfiguration) -> Void
    ) {
        var configuration = session.room?.configuration ?? fallback
        mutation(&configuration)
        session.updateConfiguration(configuration)
    }
}
