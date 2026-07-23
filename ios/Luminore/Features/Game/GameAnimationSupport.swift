import LuminoreCore
import SwiftUI

enum GameAnchorID: Hashable {
    case bankGem(GemColor)
    case playerStack(UUID, GemColor)
    case scoreLabel(UUID)
    case reservedArea(UUID)
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
        case noble(NobleTile)
    }

    let id = UUID()
    let kind: Kind
    let from: GameAnchorID
    let to: GameAnchorID
    var delay: Double = 0
    var resolvedStart: CGRect?
    var resolvedEnd: CGRect?
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
    let onFlightResolved: (UUID, CGRect, CGRect) -> Void
    let onBurstEnded: (UUID) -> Void

    var body: some View {
        ZStack {
            ForEach(flights) { flight in
                if let start = flight.resolvedStart ?? anchors[flight.from].map({ proxy[$0] }),
                   let end = flight.resolvedEnd ?? anchors[flight.to].map({ proxy[$0] }) {
                    GameFlightView(
                        flight: flight,
                        start: start,
                        end: end,
                        onLand: { onFlightEnded(flight.id) }
                    )
                    .onAppear {
                        guard flight.resolvedStart == nil || flight.resolvedEnd == nil else { return }
                        onFlightResolved(flight.id, start, end)
                    }
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
    @State private var wiggle: Double = 0
    @State private var didLand = false

    private var isNoble: Bool {
        if case .noble = flight.kind { return true }
        return false
    }

    private var endScale: CGFloat {
        switch flight.kind {
        case .gem: 0.7
        case .cardBuy, .cardReserve: 0.32
        case .noble: 0.28
        }
    }

    private var flightResponse: Double { isNoble ? 0.55 : 0.5 }

    var body: some View {
        ghost
            .frame(width: start.width, height: start.height)
            .rotationEffect(.degrees(wiggle))
            .scaleEffect(moved ? endScale : 1)
            .opacity(moved ? 0.15 : 1)
            .position(moved ? end.gameCenter : start.gameCenter)
            .onAppear(perform: run)
    }

    private func run() {
        if isNoble {
            DispatchQueue.main.asyncAfter(deadline: .now() + flight.delay) {
                withAnimation(.easeInOut(duration: 0.08).repeatCount(7, autoreverses: true)) {
                    wiggle = 9
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    wiggle = 0
                    fly(delay: 0)
                }
            }
        } else {
            fly(delay: flight.delay)
        }
    }

    private func fly(delay: Double) {
        withAnimation(.spring(response: flightResponse, dampingFraction: 0.82).delay(delay)) {
            moved = true
        } completion: {
            land()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + flightResponse + 0.1) { land() }
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
        case let .noble(noble):
            NobleTileView(noble: noble)
                .shadow(
                    color: Color(red: 0.86, green: 0.66, blue: 0.20).opacity(0.5),
                    radius: 8
                )
        }
    }
}

private struct GameSparkleBurst: View {
    let center: CGPoint
    var count = 12
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var progress: CGFloat = 0

    private var gold: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.82, blue: 0.35)
            : Color(red: 0.76, green: 0.40, blue: 0.00)
    }

    private var flash: Color {
        colorScheme == .dark
            ? Color.yellow
            : Color(red: 0.92, green: 0.53, blue: 0.02)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(flash.opacity(Double((colorScheme == .light ? 0.62 : 0.5) * (1 - progress))))
                .frame(
                    width: colorScheme == .light ? 30 : 26,
                    height: colorScheme == .light ? 30 : 26
                )
                .scaleEffect(1 + progress * 2.2)

            if colorScheme == .light {
                Circle()
                    .strokeBorder(gold.opacity(Double(0.72 * (1 - progress))), lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .scaleEffect(1 + progress * 2.2)
            }

            ForEach(0 ..< count, id: \.self) { index in
                let angle = Double(index) / Double(count) * 2 * .pi
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(gold)
                    .shadow(
                        color: colorScheme == .light ? gold.opacity(0.45) : .clear,
                        radius: 1
                    )
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { onDone() }
        }
    }
}
