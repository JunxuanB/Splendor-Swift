import SwiftData
import SwiftUI

struct MedalListView: View {
    @Query private var medals: [MedalRecord]
    @State private var selectedMedal: MedalRecord?

    private let columns = [
        GridItem(.adaptive(minimum: 142, maximum: 190), spacing: 14)
    ]

    init(profile: AccountProfile) {
        let ownerKey = profile.uuid.uuidString
        _medals = Query(
            filter: #Predicate<MedalRecord> { $0.ownerKey == ownerKey },
            sort: \.awardedAt,
            order: .reverse
        )
    }

    private var uniqueMedals: [MedalRecord] { medals.uniqueScopedMedals }

    private var issuerCount: Int {
        Set(uniqueMedals.map(\.issuerUUID)).count
    }

    var body: some View {
        Group {
            if uniqueMedals.isEmpty {
                ContentUnavailableView("account.medals.empty", systemImage: "medal")
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        collectionSummary

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(uniqueMedals) { medal in
                                MedalCollectionTile(medal: medal) {
                                    selectedMedal = medal
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("account.medals")
        .sheet(item: $selectedMedal) { medal in
            MedalDetailView(medal: medal)
        }
    }

    private var collectionSummary: some View {
        HStack(spacing: 14) {
            Image(systemName: "medal.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, value: uniqueMedals.count)

            VStack(alignment: .leading, spacing: 3) {
                Text("medal.wall.title")
                    .font(.headline)
                Text("medal.wall.summary \(uniqueMedals.count) \(issuerCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.28))
        }
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }
}

private struct MedalCollectionTile: View {
    let medal: MedalRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                MedalEmblem(
                    issuerUUID: medal.issuerUUID,
                    scoreMargin: medal.scoreMargin,
                    size: 86
                )

                Text(medal.issuerNicknameSnapshot)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Label {
                    if medal.roomName.isEmpty {
                        Text("medal.room.unavailable")
                    } else {
                        Text(verbatim: medal.roomName)
                    }
                } icon: {
                    Image(systemName: "door.left.hand.open")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(medal.awardedAt, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("medal.wall.item.accessibility \(medal.issuerNicknameSnapshot)"))
        .accessibilityHint(Text("medal.wall.item.hint"))
    }
}

private struct MedalDetailView: View {
    let medal: MedalRecord

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MedalEmblem(
                        issuerUUID: medal.issuerUUID,
                        scoreMargin: medal.scoreMargin,
                        size: 150
                    )
                        .padding(.top, 12)

                    Text(medal.issuerNicknameSnapshot)
                        .font(.title2.bold())

                    VStack(spacing: 0) {
                        detailRow("medal.detail.room", systemImage: "door.left.hand.open") {
                            if medal.roomName.isEmpty {
                                Text("medal.room.unavailable")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: medal.roomName)
                            }
                        }
                        Divider().padding(.leading, 42)
                        detailRow("medal.detail.scoreMargin", systemImage: "chart.bar.fill") {
                            if let scoreMargin = medal.scoreMargin {
                                Text("+\(scoreMargin)")
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            } else {
                                Text("medal.score.unavailable")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider().padding(.leading, 42)
                        detailRow("medal.detail.awardedAt", systemImage: "calendar") {
                            Text(medal.awardedAt, format: .dateTime.year().month().day().hour().minute())
                        }
                        Divider().padding(.leading, 42)
                        detailRow("medal.detail.game", systemImage: "dice.fill") {
                            Text("history.game.short \(medal.gameID.uuidString.prefix(8))")
                        }
                        Divider().padding(.leading, 42)
                        detailRow("medal.detail.issuerID", systemImage: "number") {
                            Text(medal.issuerUUID.uuidString)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("medal.detail.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func detailRow<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            content()
        }
        .font(.subheadline)
        .padding(.vertical, 13)
    }
}
