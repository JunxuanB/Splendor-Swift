import LuminoreCore
import SwiftUI

struct ResultView: View {
    @ObservedObject var session: MatchSessionService
    @State private var isShowingAwardAnimation = true

    var body: some View {
        ZStack {
            resultContent
                .blur(radius: isPresentingAwards ? 4 : 0)
                .allowsHitTesting(!isPresentingAwards)

            if isPresentingAwards, let presentation {
                MedalAwardOverlay(presentation: presentation) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isShowingAwardAnimation = false
                    }
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("result.title")
    }

    private var resultContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 58)).foregroundStyle(.yellow)
            Text("result.title").font(.largeTitle.bold())
            if let standings = session.game?.result?.standings {
                List(standings) { standing in
                    HStack {
                        Text("#\(standing.rank)").font(.title3.bold()).frame(width: 38)
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text(standing.nickname).font(.headline)
                                if let player = session.game?.players.first(where: { $0.id == standing.playerID }),
                                   player.kind == .human {
                                    MedalCountLabel(count: player.medalCount, compact: true)
                                }
                            }
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
    }

    private var presentation: MedalAwardPresentation? {
        session.game.map(MedalAwardPresentation.init)
    }

    private var isPresentingAwards: Bool {
        isShowingAwardAnimation && presentation?.hasAwards == true
    }
}

struct ReconnectingView: View {
    @ObservedObject var session: MatchSessionService

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

/// Finds the saved room through the session's original transport and rejoins with
/// the persisted session token held by `MatchSessionService`.
struct RejoinView: View {
    @ObservedObject var session: MatchSessionService
    let roomID: UUID
    @State private var password = ""
    @State private var lockedRoom: DiscoveredMatchRoom?

    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("multiplayer.rejoin.searching").font(.title2.bold())
            Text("multiplayer.rejoin.detail")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .onAppear { session.startBrowsing() }
        .onDisappear { session.stopBrowsing() }
        .onChange(of: session.discoveredRooms) { _, rooms in
            guard session.phase == .menu, lockedRoom == nil,
                  let room = rooms.first(where: { $0.id == roomID })
            else { return }
            joinOrAskPassword(room)
        }
        .task(id: roomID) {
            while !Task.isCancelled, session.phase == .menu {
                if let room = try? await session.resolveRoom(id: roomID) {
                    joinOrAskPassword(room)
                    return
                }
                try? await Task.sleep(for: .seconds(3))
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

    private func joinOrAskPassword(_ room: DiscoveredMatchRoom) {
        guard session.phase == .menu, lockedRoom == nil else { return }
        if room.descriptor.isPasswordProtected {
            lockedRoom = room
        } else {
            session.join(room, password: "")
        }
    }
}

extension MultiplayerMode {
    var titleKey: LocalizedStringKey {
        switch self {
        case .lan: "mode.lan.title"
        case .internet: "mode.internet.title"
        case .nearby: "mode.multipeer.title"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .lan: "mode.lan.subtitle"
        case .internet: "mode.internet.subtitle"
        case .nearby: "mode.multipeer.subtitle"
        }
    }

    var presenceContext: String {
        switch self {
        case .lan: String(localized: "presence.context.lan")
        case .internet: String(localized: "presence.context.internet")
        case .nearby: String(localized: "presence.context.nearby")
        }
    }
}
