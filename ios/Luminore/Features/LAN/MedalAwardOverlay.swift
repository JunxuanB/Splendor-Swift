import LuminoreCore
import SwiftUI

private enum MedalAwardEndpoint: Hashable {
    case issuer(UUID)
    case winner(UUID)
}

private struct MedalAwardAnchorKey: PreferenceKey {
    static let defaultValue: [MedalAwardEndpoint: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [MedalAwardEndpoint: Anchor<CGRect>],
        nextValue: () -> [MedalAwardEndpoint: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct MedalFlightPath: @MainActor AnimatableModifier {
    var progress: CGFloat
    let start: CGPoint
    let end: CGPoint
    let bend: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let distance = max(1, hypot(deltaX, deltaY))
        let normalX = -deltaY / distance
        let normalY = deltaX / distance
        let curve = 4 * progress * (1 - progress) * bend
        let x = start.x + deltaX * progress + normalX * curve
        let y = start.y + deltaY * progress + normalY * curve
        let lift = sin(.pi * progress)

        content
            .scaleEffect(0.72 + 0.34 * lift)
            .rotationEffect(.degrees(Double(-10 + 20 * progress)))
            .opacity(0.4 + 0.6 * min(1, progress * 4))
            .position(x: x, y: y)
    }
}

private struct MedalAwardPlayerRow: View {
    let player: PublicPlayerSnapshot
    let isWinner: Bool
    let medalCount: Int
    let landingCount: Int

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isWinner ? "crown.fill" : "person.crop.circle.fill")
                .foregroundStyle(isWinner ? Color.yellow : Color.secondary)
            Text(player.nickname)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if isWinner {
                MedalCountLabel(count: medalCount, compact: true)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isWinner ? Color.yellow.opacity(isPulsing ? 0.24 : 0.12) : Color.secondary.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            if isWinner {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.yellow.opacity(isPulsing ? 0.9 : 0), lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.045 : 0.96)
            }
        }
        .scaleEffect(isPulsing ? 1.025 : 1)
        .shadow(color: .yellow.opacity(isPulsing ? 0.32 : 0), radius: 8)
        .task(id: landingCount) {
            guard isWinner, landingCount > 0 else { return }
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { isPulsing = false }
            await Task.yield()
            withAnimation(.bouncy(duration: 0.24, extraBounce: 0.18)) { isPulsing = true }
            try? await Task.sleep(for: .milliseconds(170))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) { isPulsing = false }
        }
    }
}

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
    @State private var deliveredCounts: [UUID: Int] = [:]
    @State private var landingEvent = 0

    private let flightDuration = 0.82

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey)
                        .font(.title2.bold())
                        .contentTransition(.interpolate)
                    Group {
                        if isSettled {
                            Text("award.complete.subtitle \(presentation.transferCount)")
                        } else {
                            Text("award.subtitle \(presentation.transferCount)")
                        }
                    }
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
            }
            .overlayPreferenceValue(MedalAwardAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if !reduceMotion {
                        medalFlights(anchors: anchors, proxy: proxy)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(minHeight: 210)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.22))
        }
        .overlay {
            MedalCeremonyFinale(isPresented: isSettled)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(20)
        .sensoryFeedback(trigger: landingEvent) { previous, current in
            current > previous ? .impact(weight: .light, intensity: 0.65) : nil
        }
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
                MedalAwardPlayerRow(
                    player: player,
                    isWinner: isWinner,
                    medalCount: displayedMedalCount(for: player),
                    landingCount: deliveredCounts[player.id, default: 0]
                )
                .anchorPreference(key: MedalAwardAnchorKey.self, value: .bounds) { anchor in
                    [(isWinner ? .winner(player.id) : .issuer(player.id)): anchor]
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayedMedalCount(for player: PublicPlayerSnapshot) -> Int {
        guard !isSettled else { return player.medalCount }
        return presentation.countBeforeAward(for: player) + deliveredCounts[player.id, default: 0]
    }

    private var titleKey: LocalizedStringKey {
        isSettled ? "award.complete" : "award.title"
    }

    @ViewBuilder
    private func medalFlights(
        anchors: [MedalAwardEndpoint: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> some View {
        ForEach(Array(transferPairs.enumerated()), id: \.offset) { index, pair in
            if let sourceAnchor = anchors[.issuer(pair.issuerID)],
               let destinationAnchor = anchors[.winner(pair.winnerID)] {
                let source = proxy[sourceAnchor]
                let destination = proxy[destinationAnchor]
                let start = CGPoint(x: source.maxX + 7, y: source.midY)
                let end = CGPoint(x: destination.minX - 7, y: destination.midY)

                MedalEmblem(
                    issuerUUID: pair.issuerID,
                    scoreMargin: pair.scoreMargin,
                    size: 28
                )
                    .modifier(MedalFlightPath(
                        progress: medalsAreFlying ? 1 : 0,
                        start: start,
                        end: end,
                        bend: flightBend(for: index)
                    ))
                    .animation(
                        .timingCurve(0.22, 0.72, 0.28, 1, duration: flightDuration)
                            .delay(Double(index) * flightStagger),
                        value: medalsAreFlying
                    )
                    .zIndex(2)
            }
        }
    }

    private var transferPairs: [(issuerID: UUID, winnerID: UUID, scoreMargin: Int)] {
        presentation.issuers.flatMap { issuer in
            presentation.winners.map { winner in
                (issuer.id, winner.id, max(0, winner.prestige - issuer.prestige))
            }
        }
    }

    private var flightStagger: Double {
        guard presentation.transferCount > 1 else { return 0 }
        return min(0.075, 0.45 / Double(presentation.transferCount - 1))
    }

    private func flightBend(for index: Int) -> CGFloat {
        -18 - CGFloat(index % 3) * 5
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

        try? await Task.sleep(for: .milliseconds(Int(flightDuration * 1_000)))
        for (index, transfer) in transferPairs.enumerated() {
            if index > 0 {
                try? await Task.sleep(for: .milliseconds(Int(flightStagger * 1_000)))
            }
            guard !Task.isCancelled, !didFinish else { return }
            withAnimation(.snappy(duration: 0.2)) {
                deliveredCounts[transfer.winnerID, default: 0] += 1
                if shouldEmitLandingHaptic(at: index) {
                    landingEvent += 1
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled, !didFinish else { return }
        withAnimation(.bouncy(duration: 0.42, extraBounce: 0.08)) { isSettled = true }
        try? await Task.sleep(for: .milliseconds(950))
        finish()
    }

    private func shouldEmitLandingHaptic(at index: Int) -> Bool {
        let count = presentation.transferCount
        guard count > 8 else { return true }
        let interval = Int(ceil(Double(count) / 8))
        return index.isMultiple(of: interval) || index == count - 1
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
