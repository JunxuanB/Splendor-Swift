import LuminoreCore
import SwiftUI
import UIKit

struct MultiplayerMenuView: View {
    @ObservedObject var session: MatchSessionService
    @State private var showingCreate = false
    @State private var showingJoin = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AppMark(size: 88)
            Text(session.mode.titleKey).font(.largeTitle.bold())
            Text(session.mode.subtitleKey)
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
        .navigationTitle(session.mode.titleKey)
        .sheet(isPresented: $showingCreate) {
            CreateRoomView(session: session)
        }
        .sheet(isPresented: $showingJoin) {
            JoinRoomView(session: session)
        }
    }
}

struct CreateRoomView: View {
    @ObservedObject var session: MatchSessionService
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var password = ""
    @State private var isPublic = true

    var body: some View {
        NavigationStack {
            Form {
                Section("lan.room.details") {
                    TextField("lan.room.name", text: $roomName)
                    SecureField("lan.room.password.optional", text: $password)
                    if session.mode == .internet {
                        Toggle("internet.room.public", isOn: $isPublic)
                    }
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
                        session.host(
                            roomName: roomName.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password,
                            isPublic: session.mode == .internet ? isPublic : true
                        )
                        dismiss()
                    }
                    .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roomName.count > 40)
                }
            }
        }
    }
}

struct JoinRoomView: View {
    @ObservedObject var session: MatchSessionService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRoom: DiscoveredMatchRoom?
    @State private var password = ""
    @State private var roomCode = ""
    @State private var isResolvingCode = false

    var body: some View {
        NavigationStack {
            List {
                if session.mode == .internet {
                    Section("internet.room.code.section") {
                        HStack {
                            TextField("internet.room.code.placeholder", text: $roomCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .monospaced()
                            if isResolvingCode { ProgressView() }
                            Button("internet.room.code.join") { resolveCode() }
                                .disabled(normalizedCode.count != 6 || isResolvingCode)
                        }
                    }
                }
                Section(session.mode == .internet ? "internet.rooms.public" : "multiplayer.rooms.nearby") {
                    if session.discoveredRooms.isEmpty {
                    ContentUnavailableView(
                        session.mode == .internet ? "internet.rooms.empty" : "lan.rooms.empty",
                        systemImage: session.mode == .internet ? "globe" : "wifi",
                        description: Text(session.mode == .internet ? "internet.rooms.searching" : "lan.rooms.searching")
                    )
                } else {
                    ForEach(session.discoveredRooms) { room in
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
        .onAppear { session.startBrowsing() }
        .onDisappear { session.stopBrowsing() }
    }

    private var normalizedCode: String {
        roomCode.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private func resolveCode() {
        let code = roomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        isResolvingCode = true
        Task {
            defer { isResolvingCode = false }
            do {
                let room = try await session.resolveRoom(code: code)
                selectedRoom = room
                if !room.descriptor.isPasswordProtected { connect(room) }
            } catch {
                session.presentedError = error.localizedDescription
            }
        }
    }

    private func connect(_ room: DiscoveredMatchRoom) {
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

struct LobbyView: View {
    @ObservedObject var session: MatchSessionService

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
                    if let code = session.roomCode {
                        HStack(spacing: 10) {
                            Text(code)
                                .font(.title3.bold().monospaced())
                                .textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = code
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .accessibilityLabel("internet.room.code.copy")
                            ShareLink(item: code) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("internet.room.code.share")
                        }
                        Text("internet.room.code.hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                List(room.participants) { participant in
                    HStack {
                        Image(systemName: participant.kind == .bot ? "cpu" : "person.crop.circle.fill")
                        Text(participant.nickname)
                        if participant.kind == .human {
                            MedalCountLabel(count: participant.medalCount, compact: true)
                        }
                        if participant.isHost {
                            Image(systemName: "crown.fill").foregroundStyle(.yellow)
                        }
                        Spacer()
                        if session.isAwaitingResumeAssignment, session.isHost,
                           !participant.isConnected, !session.pendingSubstitutes.isEmpty {
                            Menu {
                                ForEach(session.pendingSubstitutes) { substitute in
                                    Button(substitute.nickname) {
                                        session.assignSubstitute(seatID: participant.id, substituteID: substitute.id)
                                    }
                                }
                            } label: {
                                Label("game.resume.seat.assign", systemImage: "person.fill.badge.plus")
                                    .font(.caption)
                            }
                        }
                        Circle()
                            .fill(participant.isConnected ? Color.green : Color.gray)
                            .frame(width: 9, height: 9)
                    }
                }
                .listStyle(.plain)
                if session.isHost {
                    if session.isAwaitingResumeAssignment {
                        Text("game.resume.assign.hint")
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("game.resume.continue") { session.continueResumedGame() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    } else {
                        Button("lobby.configure") { session.enterConfiguration() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(room.participants.filter(\.isConnected).count < 2)
                        Text("lobby.minimum")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if session.isAwaitingResumeAssignment {
                    ProgressView("game.resume.waitingHost")
                } else {
                    ProgressView("lobby.waitingHost")
                }
            }
        }
        .padding(.vertical)
        .navigationTitle(session.isAwaitingResumeAssignment ? "game.resume.assign.title" : "lobby.title")
    }
}
