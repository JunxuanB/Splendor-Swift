import SwiftData
import SwiftUI

struct HomeView: View {
    let profile: AccountProfile
    @Query private var activeMatches: [ActiveMatchRecord]

    init(profile: AccountProfile) {
        self.profile = profile
        let key = profile.uuid.uuidString
        _activeMatches = Query(
            filter: #Predicate<ActiveMatchRecord> { $0.ownerKey == key },
            sort: \.updatedAt,
            order: .reverse
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 14) {
                        AppMark(size: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("app.name")
                                .font(.title.bold())
                            Text("home.greeting \(profile.nickname)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink {
                            AccountView()
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.title2)
                                .padding(8)
                        }
                        .accessibilityLabel(Text("account.title"))
                    }

                    if let active = activeMatches.first {
                        NavigationLink {
                            LANFlowView(profile: profile, autoResume: true)
                        } label: {
                            ResumeMatchCard(record: active)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("home.chooseMode").font(.headline)
                        NavigationLink {
                            LANFlowView(profile: profile)
                        } label: {
                            ModeCard(
                                title: "mode.lan.title",
                                subtitle: "mode.lan.subtitle",
                                systemImage: "wifi",
                                enabled: true
                            )
                        }
                        .buttonStyle(.plain)

                        ModeCard(
                            title: "mode.internet.title",
                            subtitle: "common.comingSoon",
                            systemImage: "globe",
                            enabled: false
                        )
                        ModeCard(
                            title: "mode.multipeer.title",
                            subtitle: "common.comingSoon",
                            systemImage: "antenna.radiowaves.left.and.right",
                            enabled: false
                        )
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
    }
}

private struct ResumeMatchCard: View {
    let record: ActiveMatchRecord

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)
                .frame(width: 48, height: 48)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text("home.resume.title").font(.headline)
                Text(verbatim: record.roomName).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if record.lastKnownIsMyTurn {
                Text("home.resume.yourTurn")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ModeCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .foregroundStyle(enabled ? Color.accentColor : .secondary)
                .frame(width: 48, height: 48)
                .background((enabled ? Color.accentColor : .gray).opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: enabled ? "chevron.right" : "lock.fill")
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(enabled ? 1 : 0.68)
    }
}
