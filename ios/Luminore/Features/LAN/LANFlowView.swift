import LuminoreCore
import SwiftData
import SwiftUI

struct LANFlowView: View {
    let profile: AccountProfile
    let autoResume: Bool
    @StateObject private var session: LANSessionService
    @StateObject private var presence = PresenceCoordinator()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var presenceConflict: PresenceCoordinator.Conflict?
    @State private var didAttemptAutoResume = false
    @State private var rejoinRoomID: UUID?

    init(profile: AccountProfile, autoResume: Bool = false) {
        self.profile = profile
        self.autoResume = autoResume
        _session = StateObject(wrappedValue: LANSessionService(localID: profile.uuid, nickname: profile.nickname))
    }

    @ViewBuilder private var phaseContent: some View {
        switch session.phase {
        case .menu:
            if let rejoinRoomID {
                RejoinView(session: session, roomID: rejoinRoomID)
            } else {
                LANMenuView(session: session)
            }
        case .connecting:
            ProgressView("lan.connecting")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .lobby:
            LobbyView(session: session)
        case .configuration:
            ConfigurationView(session: session)
        case .game:
            GameBoardView(
                session: session,
                onExit: {
                    clearActiveMatch(includeSaved: true)
                    session.leave()
                    dismiss()
                },
                onSaveAndSuspend: {
                    session.saveAndSuspend(context: modelContext)
                }
            )
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

    var body: some View {
        withLifecycle(withAlerts(withChrome(phaseContent)))
    }

    private func withChrome<V: View>(_ content: V) -> some View {
        content
            .navigationBarBackButtonHidden(session.phase != .menu)
            .toolbar {
                if session.phase != .menu {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("common.leave", role: .destructive) {
                            clearActiveMatch(includeSaved: true)
                            session.leave()
                            dismiss()
                        }
                    }
                }
            }
    }

    private func withAlerts<V: View>(_ content: V) -> some View {
        content
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
    }

    private func withLifecycle<V: View>(_ content: V) -> some View {
        content
            .onAppear {
                presence.configure(modelContext)
                session.updateNickname(profile.nickname)
                startAutoResumeIfNeeded()
            }
            .onChange(of: session.phase) { old, new in handlePhaseChange(from: old, to: new) }
            .onChange(of: session.game?.revision) { _, _ in syncActiveMatch() }
            .onChange(of: scenePhase) { _, new in
                if new == .active { session.applicationDidBecomeActive() }
            }
            .onChange(of: session.wasSuspended) { _, suspended in
                // A graceful host suspend (ours or received) returns everyone home
                // while keeping the rejoin record intact.
                if suspended { dismiss() }
            }
            .onDisappear {
                if session.phase == .menu { session.leave() }
                presence.release()
            }
    }

    private func startAutoResumeIfNeeded() {
        guard autoResume, !didAttemptAutoResume, session.phase == .menu else { return }
        didAttemptAutoResume = true
        let ownerKey = profile.uuid.uuidString
        guard let active = try? modelContext.fetch(
            FetchDescriptor<ActiveMatchRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
        ).first else { return }
        if active.wasHost {
            if let saved = try? modelContext.fetch(
                FetchDescriptor<SavedGameRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
            ).first {
                session.resumeSavedGame(saved)
            } else {
                // Host record with no saved state to reload — stale, drop it.
                clearActiveMatch(includeSaved: false)
            }
        } else {
            rejoinRoomID = active.roomID
        }
    }

    /// Upsert the local "match in progress" marker as snapshots arrive; clear it when
    /// the match finishes.
    private func syncActiveMatch() {
        guard let game = session.game, let room = session.room, session.phase == .game else { return }
        if game.status == .finished {
            clearActiveMatch(includeSaved: true)
            return
        }
        let ownerKey = profile.uuid.uuidString
        let existing = try? modelContext.fetch(
            FetchDescriptor<ActiveMatchRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
        )
        let record: ActiveMatchRecord
        if let found = existing?.first {
            record = found
        } else {
            record = ActiveMatchRecord(
                ownerKey: ownerKey,
                gameID: game.gameID,
                roomID: room.descriptor.id,
                roomName: room.descriptor.name,
                modeRawValue: game.configuration.mode.rawValue,
                myParticipantID: profile.uuid,
                wasHost: session.isHost
            )
            modelContext.insert(record)
        }
        record.gameID = game.gameID
        record.roomID = room.descriptor.id
        record.roomName = room.descriptor.name
        record.modeRawValue = game.configuration.mode.rawValue
        record.wasHost = session.isHost
        record.lastKnownIsMyTurn = game.currentPlayerID == profile.uuid
        record.lastKnownStatusRaw = game.status.rawValue
        record.updatedAt = Date()
        try? modelContext.save()
    }

    private func clearActiveMatch(includeSaved: Bool) {
        let ownerKey = profile.uuid.uuidString
        if let actives = try? modelContext.fetch(
            FetchDescriptor<ActiveMatchRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
        ) {
            actives.forEach(modelContext.delete)
        }
        if includeSaved, let saves = try? modelContext.fetch(
            FetchDescriptor<SavedGameRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
        ) {
            saves.forEach(modelContext.delete)
        }
        try? modelContext.save()
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

/// Shown when returning to an in-progress match from the home screen: browse the LAN
/// for the saved room id and rejoin as soon as the host is discovered.
private struct RejoinView: View {
    @ObservedObject var session: LANSessionService
    let roomID: UUID
    @StateObject private var browser = LANRoomBrowser()
    @State private var password = ""
    @State private var lockedRoom: DiscoveredLANRoom?

    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("lan.rejoin.searching").font(.title2.bold())
            Text("lan.rejoin.detail")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
        .onChange(of: browser.rooms) { _, rooms in
            guard session.phase == .menu, lockedRoom == nil,
                  let room = rooms.first(where: { $0.descriptor.id == roomID })
            else { return }
            if room.descriptor.isPasswordProtected {
                lockedRoom = room
            } else {
                session.join(room, password: "")
            }
        }
        .alert("lan.password.title", isPresented: Binding(
            get: { lockedRoom != nil },
            set: { if !$0 { lockedRoom = nil; password = "" } }
        )) {
            SecureField("lan.room.password", text: $password)
            Button("lan.join") { if let lockedRoom { session.join(lockedRoom, password: password) } }
            Button("common.cancel", role: .cancel) { lockedRoom = nil }
        }
    }
}
