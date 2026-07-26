import LuminoreCore
import SwiftData
import SwiftUI

struct MultiplayerFlowView: View {
    let profile: AccountProfile
    let medalCount: Int
    let autoResume: Bool
    @StateObject private var session: MatchSessionService
    @StateObject private var presence = PresenceCoordinator()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var presenceConflict: PresenceCoordinator.Conflict?
    @State private var didAttemptAutoResume = false
    @State private var rejoinRoomID: UUID?
    @State private var showingServerSettings = false

    private var isLocalTurn: Bool {
        session.phase == .game
            && !session.isOpeningTurnSelection
            && session.game?.currentPlayerID == session.localID
    }

    init(
        profile: AccountProfile,
        mode: MultiplayerMode,
        serverURL: URL? = nil,
        restoredSessionToken: String? = nil,
        medalCount: Int = 0,
        autoResume: Bool = false
    ) {
        self.profile = profile
        self.medalCount = medalCount
        self.autoResume = autoResume
        _session = StateObject(wrappedValue: MatchSessionService(
            localID: profile.uuid,
            nickname: profile.nickname,
            medalCount: medalCount,
            mode: mode,
            serverURL: serverURL,
            restoredSessionToken: restoredSessionToken
        ))
    }

    @ViewBuilder private var phaseContent: some View {
        switch session.phase {
        case .menu:
            if let rejoinRoomID {
                RejoinView(session: session, roomID: rejoinRoomID)
            } else {
                MultiplayerMenuView(session: session)
            }
        case .connecting:
            ProgressView("multiplayer.connecting")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .lobby:
            LobbyView(session: session)
        case .configuration:
            ConfigurationView(session: session)
        case .game:
            if session.game?.configuration.mode == .duel {
                DuelGameBoardView(
                    session: session,
                    onExit: exitMatch,
                    onSaveAndSuspend: { session.saveAndSuspend(context: modelContext) }
                )
            } else {
                GameBoardView(
                    session: session,
                    onExit: exitMatch,
                    onSaveAndSuspend: { session.saveAndSuspend(context: modelContext) }
                )
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

    private func exitMatch() {
        clearActiveMatch(includeSaved: true)
        session.leave()
        dismiss()
    }

    var body: some View {
        withLifecycle(withAlerts(withChrome(phaseContent)))
            .localTurnNotification(isLocalTurn: isLocalTurn)
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
                if session.phase == .menu, session.mode == .internet {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingServerSettings = true
                        } label: {
                            Label("internet.server.title", systemImage: "server.rack")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingServerSettings) {
                InternetServerSettingsView { url in
                    session.updateInternetServer(url)
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
                session.updateMedalCount(medalCount)
                startAutoResumeIfNeeded()
            }
            .onChange(of: session.phase) { old, new in handlePhaseChange(from: old, to: new) }
            .onChange(of: session.game?.revision) { _, _ in syncActiveMatch() }
            .onChange(of: session.game?.status) { _, _ in syncActiveMatch() }
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
        guard let game = session.game, let room = session.room else { return }
        if game.status == .finished {
            finalizeOutcome(game, roomName: room.descriptor.name)
            return
        }
        guard session.phase == .game else { return }
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
                wasHost: session.isHost,
                transportRawValue: session.mode.rawValue,
                serverURLString: session.serverURL?.absoluteString ?? "",
                isPublic: session.isPublic,
                sessionToken: session.currentSessionToken ?? ""
            )
            modelContext.insert(record)
        }
        record.gameID = game.gameID
        record.roomID = room.descriptor.id
        record.roomName = room.descriptor.name
        record.modeRawValue = game.configuration.mode.rawValue
        record.wasHost = session.isHost
        record.transportRawValue = session.mode.rawValue
        record.serverURLString = session.serverURL?.absoluteString ?? ""
        record.isPublic = session.isPublic
        record.sessionToken = session.currentSessionToken ?? ""
        record.lastKnownIsMyTurn = game.currentPlayerID == profile.uuid
        record.lastKnownStatusRaw = game.status.rawValue
        record.updatedAt = Date()
        try? modelContext.save()
    }

    private func finalizeOutcome(_ game: ClientGameSnapshot, roomName: String) {
        do {
            _ = try MatchOutcomeRecorder.record(
                snapshot: game,
                ownerKey: profile.uuid.uuidString,
                localParticipantID: session.localID,
                transport: session.mode,
                roomName: roomName,
                context: modelContext
            )
            clearActiveMatch(includeSaved: true)
        } catch {
            session.presentedError = error.localizedDescription
        }
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
    private func handlePhaseChange(from old: MatchSessionService.Phase, to new: MatchSessionService.Phase) {
        let wasActive = old != .menu && old != .ended
        let isActive = new != .menu && new != .ended
        if !wasActive, isActive {
            presenceConflict = presence.claim(
                profileUUID: profile.uuid,
                context: session.mode.presenceContext
            )
        } else if wasActive, !isActive {
            presence.release()
        }
    }
}
