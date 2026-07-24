import LuminoreCore
import SwiftData
import SwiftUI

struct ProfileRecordsSections: View {
    let profile: AccountProfile
    @Query private var medals: [MedalRecord]
    @Query private var games: [CompletedGameRecord]

    init(profile: AccountProfile) {
        self.profile = profile
        let ownerKey = profile.uuid.uuidString
        _medals = Query(
            filter: #Predicate<MedalRecord> { $0.ownerKey == ownerKey },
            sort: \.awardedAt,
            order: .reverse
        )
        _games = Query(
            filter: #Predicate<CompletedGameRecord> { $0.ownerKey == ownerKey },
            sort: \.endedAt,
            order: .reverse
        )
    }

    var body: some View {
        Section {
            NavigationLink {
                MedalListView(profile: profile)
            } label: {
                HStack {
                    Label("account.medals", systemImage: "medal.fill")
                    Spacer()
                    MedalCountLabel(count: medals.uniqueScopedMedals.count)
                }
            }
        }

        Section {
            NavigationLink {
                MatchHistoryView(profile: profile)
            } label: {
                LabeledContent(
                    "account.history",
                    value: "\(games.uniqueScopedGames.filter { $0.result != nil }.count)"
                )
            }
        }
    }
}

struct MatchHistoryView: View {
    @Query private var games: [CompletedGameRecord]

    init(profile: AccountProfile) {
        let ownerKey = profile.uuid.uuidString
        _games = Query(
            filter: #Predicate<CompletedGameRecord> { $0.ownerKey == ownerKey },
            sort: \.endedAt,
            order: .reverse
        )
    }

    private var validGames: [CompletedGameRecord] {
        games.uniqueScopedGames.filter { $0.result != nil }
    }

    var body: some View {
        Group {
            if validGames.isEmpty {
                ContentUnavailableView("account.history.empty", systemImage: "clock.arrow.circlepath")
            } else {
                List(validGames) { game in
                    NavigationLink {
                        MatchHistoryDetailView(record: game)
                    } label: {
                        MatchHistoryRow(record: game)
                    }
                }
            }
        }
        .navigationTitle("account.history")
    }
}

private struct MatchHistoryRow: View {
    let record: CompletedGameRecord

    private var result: GameResult? { record.result }
    private var localStanding: GameResult.Standing? {
        result?.standings.first { $0.playerID == record.localParticipantID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(outcomeKey)
                    .font(.headline)
                    .foregroundStyle(isWinner ? Color.green : Color.primary)
                Spacer()
                Text(record.endedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Label(gameModeKey, systemImage: "diamond.fill")
                Text("·")
                Text(record.multiplayerMode.titleKey)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if !record.roomName.isEmpty {
                Label {
                    Text(verbatim: record.roomName)
                } icon: {
                    Image(systemName: "door.left.hand.open")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            if let standing = localStanding, let result {
                Text("history.summary \(standing.rank) \(result.standings.count) \(standing.prestige)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var isWinner: Bool {
        result?.winnerIDs.contains(record.localParticipantID) == true
    }

    private var outcomeKey: LocalizedStringKey {
        guard isWinner else { return "history.outcome.loss" }
        return (result?.winnerIDs.count ?? 0) > 1
            ? "history.outcome.tiedWin"
            : "history.outcome.win"
    }

    private var gameModeKey: LocalizedStringKey {
        switch record.gameMode {
        case .standard: "config.mode.standard"
        case .silkRoad: "config.mode.silkRoad"
        case .duel: "config.mode.duel"
        }
    }
}

private struct MatchHistoryDetailView: View {
    let record: CompletedGameRecord

    var body: some View {
        List {
            Section("history.details") {
                LabeledContent("history.date") {
                    Text(record.endedAt, format: .dateTime.year().month().day().hour().minute())
                }
                LabeledContent("history.gameMode") {
                    Text(gameModeKey)
                }
                LabeledContent("history.transport") {
                    Text(record.multiplayerMode.titleKey)
                }
                LabeledContent("history.room") {
                    if record.roomName.isEmpty {
                        Text("history.room.unavailable")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: record.roomName)
                    }
                }
                LabeledContent("history.gameID") {
                    Text(record.gameID.uuidString)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let result = record.result {
                Section("history.standings") {
                    ForEach(result.standings) { standing in
                        HStack(spacing: 12) {
                            Text("#\(standing.rank)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(standing.nickname).font(.headline)
                                    if standing.isWinner {
                                        Image(systemName: "crown.fill").foregroundStyle(.yellow)
                                    }
                                }
                                Text("result.cards \(standing.developmentCards)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(standing.prestige)")
                                .font(.title3.bold().monospacedDigit())
                        }
                    }
                }
            }
        }
        .navigationTitle("history.detail.title")
    }

    private var gameModeKey: LocalizedStringKey {
        switch record.gameMode {
        case .standard: "config.mode.standard"
        case .silkRoad: "config.mode.silkRoad"
        case .duel: "config.mode.duel"
        }
    }
}
