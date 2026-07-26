import LuminoreCore
import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var session: MatchSessionService

    var body: some View {
        Form {
            if let room = session.room {
                Section("config.mode") {
                    modeRow("config.mode.standard", mode: .standard, enabled: true, configuration: room.configuration)
                    modeRow("config.mode.silkRoad", mode: .silkRoad, enabled: false, configuration: room.configuration)
                    modeRow(
                        "config.mode.duel",
                        mode: .duel,
                        enabled: room.participants.filter(\.isConnected).count == 2,
                        configuration: room.configuration
                    )
                }
                Section("config.rules") {
                    if room.configuration.mode == .standard {
                        Stepper(
                            value: scoreBinding(room.configuration),
                            in: 10 ... 30
                        ) {
                            LabeledContent("config.targetScore", value: "\(room.configuration.targetPrestige)")
                        }
                    } else if room.configuration.mode == .duel {
                        Label("config.duel.fixedVictory", systemImage: "crown")
                            .font(.footnote)
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
                    if room.configuration.mode == .standard, room.participants.count > 4 {
                        Label("config.customLargeTable", systemImage: "person.3.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .disabled(!session.isHost)
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

    private func modeRow(
        _ title: LocalizedStringKey,
        mode: GameMode,
        enabled: Bool,
        configuration: GameConfiguration
    ) -> some View {
        Button {
            update(configuration) { $0.mode = mode }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if !enabled {
                    Text(mode == .duel ? "config.duel.requiresTwo" : "common.comingSoon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: configuration.mode == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.mode == mode ? Color.accentColor : Color.secondary.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
