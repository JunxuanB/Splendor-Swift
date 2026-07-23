import LuminoreCore
import SwiftUI

struct MedalAwardPresentation: Equatable {
    let winners: [PublicPlayerSnapshot]
    let issuers: [PublicPlayerSnapshot]

    init(snapshot: ClientGameSnapshot) {
        let winnerIDs = Set(snapshot.result?.winnerIDs ?? [])
        winners = snapshot.players.filter { $0.kind == .human && winnerIDs.contains($0.id) }
        issuers = snapshot.players.filter { $0.kind == .human && !winnerIDs.contains($0.id) }
    }

    var hasAwards: Bool { !winners.isEmpty && !issuers.isEmpty }
    var transferCount: Int { winners.count * issuers.count }

    func countBeforeAward(for winner: PublicPlayerSnapshot) -> Int {
        max(0, winner.medalCount - issuers.count)
    }
}

struct MedalAwardOverlay: View {
    let presentation: MedalAwardPresentation
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var medalsAreFlying = false
    @State private var isSettled = false
    @State private var didFinish = false

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("award.title").font(.title2.bold())
                    Text("award.subtitle \(presentation.transferCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("award.skip", action: finishImmediately)
                    .buttonStyle(.bordered)
            }

            ZStack {
                HStack(alignment: .top, spacing: 18) {
                    playerColumn(title: "award.from", players: presentation.issuers, isWinner: false)

                    Image(systemName: "arrow.right")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity)

                    playerColumn(title: "award.to", players: presentation.winners, isWinner: true)
                }

                if !reduceMotion {
                    GeometryReader { proxy in
                        ForEach(0 ..< presentation.transferCount, id: \.self) { index in
                            Image(systemName: "medal.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .shadow(color: .orange.opacity(0.35), radius: 5)
                                .position(
                                    x: medalsAreFlying ? proxy.size.width - 62 : 62,
                                    y: particleY(index: index, height: proxy.size.height)
                                )
                                .scaleEffect(medalsAreFlying ? 1.15 : 0.7)
                                .opacity(medalsAreFlying ? 1 : 0.25)
                                .animation(
                                    .easeInOut(duration: 1.2).delay(Double(index % 7) * 0.055),
                                    value: medalsAreFlying
                                )
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 210)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.22))
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(20)
        .sensoryFeedback(.success, trigger: isSettled)
        .task { await play() }
        .accessibilityElement(children: .contain)
    }

    private func playerColumn(
        title: LocalizedStringKey,
        players: [PublicPlayerSnapshot],
        isWinner: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(players) { player in
                HStack(spacing: 6) {
                    Image(systemName: isWinner ? "crown.fill" : "person.crop.circle.fill")
                        .foregroundStyle(isWinner ? Color.yellow : Color.secondary)
                    Text(player.nickname)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if isWinner {
                        MedalCountLabel(
                            count: isSettled ? player.medalCount : presentation.countBeforeAward(for: player),
                            compact: true
                        )
                        .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isWinner ? Color.yellow.opacity(0.12) : Color.secondary.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func particleY(index: Int, height: CGFloat) -> CGFloat {
        let lanes = max(1, min(presentation.transferCount, 6))
        let lane = index % lanes
        return height * CGFloat(lane + 1) / CGFloat(lanes + 1)
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { isSettled = true }
            try? await Task.sleep(for: .milliseconds(850))
            finish()
            return
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, !didFinish else { return }
        medalsAreFlying = true
        try? await Task.sleep(for: .milliseconds(1_650))
        guard !Task.isCancelled, !didFinish else { return }
        withAnimation(.snappy) { isSettled = true }
        try? await Task.sleep(for: .milliseconds(600))
        finish()
    }

    private func finishImmediately() {
        medalsAreFlying = true
        isSettled = true
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}
