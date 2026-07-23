import LuminoreCore
import SwiftData
import SwiftUI

struct LANFlowView: View {
    let profile: AccountProfile
    @StateObject private var session: LANSessionService
    @StateObject private var presence = PresenceCoordinator()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var presenceConflict: PresenceCoordinator.Conflict?

    init(profile: AccountProfile) {
        self.profile = profile
        _session = StateObject(wrappedValue: LANSessionService(localID: profile.uuid, nickname: profile.nickname))
    }

    var body: some View {
        Group {
            switch session.phase {
            case .menu:
                LANMenuView(session: session)
            case .connecting:
                ProgressView("lan.connecting")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .lobby:
                LobbyView(session: session)
            case .configuration:
                ConfigurationView(session: session)
            case .game:
                GameBoardView(session: session) {
                    session.leave()
                    dismiss()
                }
            case .results:
                ResultView(session: session)
            case .reconnecting:
                ReconnectingView(session: session)
            case .ended:
                ContentUnavailableView(
                    "lan.sessionEnded",
                    systemImage: "wifi.exclamationmark",
                    description: Text("lan.sessionEnded.detail")
                )
            }
        }
        .navigationBarBackButtonHidden(session.phase != .menu)
        .toolbar {
            if session.phase != .menu {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.leave", role: .destructive) {
                        session.leave()
                        dismiss()
                    }
                }
            }
        }
        .alert("common.error", isPresented: Binding(
            get: { session.presentedError != nil },
            set: { if !$0 { session.presentedError = nil } }
        )) {
            Button("common.ok") { session.presentedError = nil }
        } message: {
            Text(session.presentedError ?? "")
        }
        .alert("presence.takeover.title", isPresented: Binding(
            get: { presenceConflict != nil },
            set: { if !$0 { presenceConflict = nil } }
        ), presenting: presenceConflict) { _ in
            Button("presence.takeover.confirm") { presenceConflict = nil }
            Button("common.leave", role: .cancel) {
                presenceConflict = nil
                session.leave()
                presence.release()
                dismiss()
            }
        } message: { conflict in
            Text("presence.takeover.message \(conflict.deviceName)")
        }
        .alert("presence.takenOver.title", isPresented: $presence.wasTakenOver) {
            Button("common.ok") {
                session.leave()
                dismiss()
            }
        } message: {
            Text("presence.takenOver.message")
        }
        .onAppear {
            presence.configure(modelContext)
            session.updateNickname(profile.nickname)
        }
        .onChange(of: session.phase) { old, new in handlePhaseChange(from: old, to: new) }
        .onDisappear {
            if session.phase == .menu { session.leave() }
            presence.release()
        }
    }

    /// Claim the presence lease when a match becomes active and release it when the
    /// session returns to the menu or ends. `presenceConflict` surfaces the soft
    /// "already playing on another device" prompt.
    private func handlePhaseChange(from old: LANSessionService.Phase, to new: LANSessionService.Phase) {
        let wasActive = old != .menu && old != .ended
        let isActive = new != .menu && new != .ended
        if !wasActive, isActive {
            presenceConflict = presence.claim(
                profileUUID: profile.uuid,
                context: String(localized: "presence.context.lan")
            )
        } else if wasActive, !isActive {
            presence.release()
        }
    }
}

private struct LANMenuView: View {
    @ObservedObject var session: LANSessionService
    @State private var showingCreate = false
    @State private var showingJoin = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AppMark(size: 88)
            Text("lan.title").font(.largeTitle.bold())
            Text("lan.subtitle")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showingCreate = true
            } label: {
                Label("lan.create", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            Button {
                showingJoin = true
            } label: {
                Label("lan.join", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .navigationTitle("lan.title")
        .sheet(isPresented: $showingCreate) {
            CreateRoomView(session: session)
        }
        .sheet(isPresented: $showingJoin) {
            JoinRoomView(session: session)
        }
    }
}

private struct CreateRoomView: View {
    @ObservedObject var session: LANSessionService
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("lan.room.details") {
                    TextField("lan.room.name", text: $roomName)
                    SecureField("lan.room.password.optional", text: $password)
                }
                Section {
                    Text("lan.room.password.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("lan.create")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("lan.create") {
                        session.host(roomName: roomName.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                        dismiss()
                    }
                    .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roomName.count > 40)
                }
            }
        }
    }
}

private struct JoinRoomView: View {
    @ObservedObject var session: LANSessionService
    @StateObject private var browser = LANRoomBrowser()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRoom: DiscoveredLANRoom?
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Group {
                if browser.rooms.isEmpty {
                    ContentUnavailableView(
                        "lan.rooms.empty",
                        systemImage: "wifi",
                        description: Text("lan.rooms.searching")
                    )
                } else {
                    List(browser.rooms) { room in
                        Button {
                            selectedRoom = room
                            if !room.descriptor.isPasswordProtected { connect(room) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: room.descriptor.isPasswordProtected ? "lock.fill" : "wifi")
                                    .foregroundStyle(room.descriptor.stage == .lobby ? Color.accentColor : .secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(room.descriptor.name).font(.headline)
                                    Text("lan.room.host \(room.descriptor.hostNickname)")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(room.descriptor.playerCount)/\(room.descriptor.maximumPlayers)")
                                        .monospacedDigit()
                                    Text(stageKey(room.descriptor.stage))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(room.descriptor.stage != .lobby)
                    }
                }
            }
            .navigationTitle("lan.join")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .alert("lan.password.title", isPresented: Binding(
                get: { selectedRoom?.descriptor.isPasswordProtected == true },
                set: { if !$0 { selectedRoom = nil; password = "" } }
            )) {
                SecureField("lan.room.password", text: $password)
                Button("lan.join") {
                    if let selectedRoom { connect(selectedRoom) }
                }
                Button("common.cancel", role: .cancel) { selectedRoom = nil }
            }
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    private func connect(_ room: DiscoveredLANRoom) {
        session.join(room, password: password)
        selectedRoom = nil
        dismiss()
    }

    private func stageKey(_ stage: RoomStage) -> LocalizedStringKey {
        switch stage {
        case .lobby: "lan.stage.lobby"
        case .configuration: "lan.stage.configuration"
        case .playing: "lan.stage.playing"
        case .results: "lan.stage.results"
        }
    }
}

private struct LobbyView: View {
    @ObservedObject var session: LANSessionService

    var body: some View {
        VStack(spacing: 16) {
            if let room = session.room {
                VStack(spacing: 4) {
                    Text(room.descriptor.name).font(.largeTitle.bold())
                    Label(
                        room.descriptor.isPasswordProtected ? "lan.password.protected" : "lan.password.open",
                        systemImage: room.descriptor.isPasswordProtected ? "lock.fill" : "lock.open"
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                List(room.participants) { participant in
                    HStack {
                        Image(systemName: participant.kind == .bot ? "cpu" : "person.crop.circle.fill")
                        Text(participant.nickname)
                        if participant.isHost {
                            Image(systemName: "crown.fill").foregroundStyle(.yellow)
                        }
                        Spacer()
                        Circle()
                            .fill(participant.isConnected ? Color.green : Color.gray)
                            .frame(width: 9, height: 9)
                    }
                }
                .listStyle(.plain)
                if session.isHost {
                    Button("lobby.configure") { session.enterConfiguration() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(room.participants.filter(\.isConnected).count < 2)
                    Text("lobby.minimum")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ProgressView("lobby.waitingHost")
                }
            }
        }
        .padding(.vertical)
        .navigationTitle("lobby.title")
    }
}

private struct ConfigurationView: View {
    @ObservedObject var session: LANSessionService

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
                    if room.participants.count > 4 {
                        Label("config.customLargeTable", systemImage: "person.3.fill")
                            .foregroundStyle(.orange)
                    }
                }
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
                    }
                }
            }
        }
        .navigationTitle("config.title")
        .disabled(!session.isHost)
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
            set: {
                session.updateConfiguration(.init(
                    mode: .standard,
                    targetPrestige: $0,
                    turnDurationSeconds: session.room?.configuration.turnDurationSeconds,
                    turnGracePeriodEnabled: session.room?.configuration.turnGracePeriodEnabled
                        ?? configuration.turnGracePeriodEnabled
                ))
            }
        )
    }

    private func timerEnabledBinding(_ configuration: GameConfiguration) -> Binding<Bool> {
        Binding(
            get: { session.room?.configuration.turnDurationSeconds != nil },
            set: { enabled in
                session.updateConfiguration(.init(
                    mode: .standard,
                    targetPrestige: session.room?.configuration.targetPrestige ?? configuration.targetPrestige,
                    turnDurationSeconds: enabled ? 30 : nil,
                    turnGracePeriodEnabled: session.room?.configuration.turnGracePeriodEnabled
                        ?? configuration.turnGracePeriodEnabled
                ))
            }
        )
    }

    private func timerBinding(_ configuration: GameConfiguration) -> Binding<Int> {
        Binding(
            get: { session.room?.configuration.turnDurationSeconds ?? configuration.turnDurationSeconds ?? 30 },
            set: { seconds in
                session.updateConfiguration(.init(
                    mode: .standard,
                    targetPrestige: session.room?.configuration.targetPrestige ?? configuration.targetPrestige,
                    turnDurationSeconds: seconds,
                    turnGracePeriodEnabled: session.room?.configuration.turnGracePeriodEnabled
                        ?? configuration.turnGracePeriodEnabled
                ))
            }
        )
    }

    private func gracePeriodBinding(_ configuration: GameConfiguration) -> Binding<Bool> {
        Binding(
            get: {
                session.room?.configuration.turnGracePeriodEnabled
                    ?? configuration.turnGracePeriodEnabled
            },
            set: { enabled in
                session.updateConfiguration(.init(
                    mode: .standard,
                    targetPrestige: session.room?.configuration.targetPrestige
                        ?? configuration.targetPrestige,
                    turnDurationSeconds: session.room?.configuration.turnDurationSeconds
                        ?? configuration.turnDurationSeconds,
                    turnGracePeriodEnabled: enabled
                ))
            }
        )
    }
}

private struct ResultView: View {
    @ObservedObject var session: LANSessionService

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 58)).foregroundStyle(.yellow)
            Text("result.title").font(.largeTitle.bold())
            if let standings = session.game?.result?.standings {
                List(standings) { standing in
                    HStack {
                        Text("#\(standing.rank)").font(.title3.bold()).frame(width: 38)
                        VStack(alignment: .leading) {
                            Text(standing.nickname).font(.headline)
                            Text("result.cards \(standing.developmentCards)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(standing.prestige)").font(.title2.bold())
                        if standing.isWinner { Image(systemName: "crown.fill").foregroundStyle(.yellow) }
                    }
                }
                .listStyle(.plain)
            }
            if session.isHost {
                Button("result.rematch") { session.returnToConfiguration() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                ProgressView("result.waitingHost")
            }
        }
        .padding(.vertical)
        .navigationTitle("result.title")
    }
}

private struct ReconnectingView: View {
    @ObservedObject var session: LANSessionService

    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("lan.reconnecting").font(.title2.bold())
            Text("lan.reconnecting.detail")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
