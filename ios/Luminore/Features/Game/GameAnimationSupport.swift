import LuminoreCore
import SwiftUI

enum GameAnchorID: Hashable {
    case bankGem(GemColor)
    case playerStack(GemColor)
    case scoreLabel
    case reservedArea
    case marketCard(String)
    case nobleTile(String)
}

struct GameAnchorKey: PreferenceKey {
    static var defaultValue: [GameAnchorID: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [GameAnchorID: Anchor<CGRect>],
        nextValue: () -> [GameAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func gameFlightAnchor(_ id: GameAnchorID) -> some View {
        anchorPreference(key: GameAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

private extension CGRect {
    var gameCenter: CGPoint { CGPoint(x: midX, y: midY) }
}

struct GameFlight: Identifiable {
    enum Kind {
        case gem(GemColor)
        case cardBuy(DevelopmentCard)
        case cardReserve(DevelopmentCard)
    }

    let id = UUID()
    let kind: Kind
    let from: GameAnchorID
    let to: GameAnchorID
    var delay: Double = 0
}

struct GameBurst: Identifiable {
    let id = UUID()
    let at: GameAnchorID
}

struct GameFlightLayer: View {
    let flights: [GameFlight]
    let bursts: [GameBurst]
    let anchors: [GameAnchorID: Anchor<CGRect>]
    let proxy: GeometryProxy
    let onFlightEnded: (UUID) -> Void
    let onBurstEnded: (UUID) -> Void

    var body: some View {
        ZStack {
            ForEach(flights) { flight in
                if let from = anchors[flight.from], let to = anchors[flight.to] {
                    GameFlightView(
                        flight: flight,
                        start: proxy[from],
                        end: proxy[to],
                        onLand: { onFlightEnded(flight.id) }
                    )
                }
            }

            ForEach(bursts) { burst in
                if let anchor = anchors[burst.at] {
                    GameSparkleBurst(center: proxy[anchor].gameCenter) {
                        onBurstEnded(burst.id)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GameFlightView: View {
    let flight: GameFlight
    let start: CGRect
    let end: CGRect
    let onLand: () -> Void

    @State private var moved = false
    @State private var didLand = false

    private var endScale: CGFloat {
        switch flight.kind {
        case .gem: 0.7
        case .cardBuy, .cardReserve: 0.32
        }
    }

    var body: some View {
        ghost
            .frame(width: start.width, height: start.height)
            .scaleEffect(moved ? endScale : 1)
            .opacity(moved ? 0.15 : 1)
            .position(moved ? end.gameCenter : start.gameCenter)
            .onAppear(perform: run)
    }

    private func run() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(flight.delay)) {
            moved = true
        } completion: {
            land()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + flight.delay + 0.6) { land() }
    }

    private func land() {
        guard !didLand else { return }
        didLand = true
        onLand()
    }

    @ViewBuilder private var ghost: some View {
        switch flight.kind {
        case let .gem(gem):
            ZStack {
                Circle().fill(gem.tint)
                Circle().strokeBorder(.black.opacity(0.10), lineWidth: 1)
                Image(systemName: gem.iconName)
                    .font(.system(size: start.width * 0.4, weight: .semibold))
                    .foregroundStyle(gem.foreground)
            }
            .shadow(color: gem.tint.opacity(0.5), radius: 6)
        case let .cardBuy(card), let .cardReserve(card):
            DevelopmentCardView(card: card)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
    }
}

private struct GameSparkleBurst: View {
    let center: CGPoint
    var count = 12
    let onDone: () -> Void

    @State private var progress: CGFloat = 0
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.35)

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(Double(0.5 * (1 - progress))))
                .frame(width: 26, height: 26)
                .scaleEffect(1 + progress * 2.2)

            ForEach(0 ..< count, id: \.self) { index in
                let angle = Double(index) / Double(count) * 2 * .pi
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(gold)
                    .scaleEffect(0.4 + (1 - progress) * 0.9)
                    .opacity(Double(1 - progress))
                    .offset(
                        x: CGFloat(cos(angle)) * 48 * progress,
                        y: CGFloat(sin(angle)) * 48 * progress
                    )
            }
        }
        .position(center)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72, execute: onDone)
        }
    }
}
