import SwiftUI

// MARK: - Anchor plumbing

/// Stable identity for every point a Duel flying animation can start from or land on.
enum DuelAnchorID: Hashable {
    case boardCell(Int)
    case playerToken(DuelColor)
    case playerScore
    case reservedArea
    case marketCard(String)
}

struct DuelAnchorKey: PreferenceKey {
    static var defaultValue: [DuelAnchorID: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [DuelAnchorID: Anchor<CGRect>],
        nextValue: () -> [DuelAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func duelFlightAnchor(_ id: DuelAnchorID) -> some View {
        anchorPreference(key: DuelAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - Flight & burst models

struct DuelFlight: Identifiable {
    enum Kind {
        case gem(DuelColor)
        case cardBuy(DuelCard)
        case cardReserve(DuelCard)
    }

    let id = UUID()
    let kind: Kind
    let from: DuelAnchorID
    let to: DuelAnchorID
    var delay: Double = 0
}

struct DuelBurst: Identifiable {
    let id = UUID()
    let at: DuelAnchorID
}

// MARK: - Root flight layer

struct DuelFlightLayer: View {
    @ObservedObject var state: DuelGameState
    let anchors: [DuelAnchorID: Anchor<CGRect>]
    let proxy: GeometryProxy

    var body: some View {
        ZStack {
            ForEach(state.flights) { flight in
                if let from = anchors[flight.from], let to = anchors[flight.to] {
                    DuelFlightView(flight: flight, start: proxy[from], end: proxy[to]) {
                        state.land(flight)
                    }
                }
            }

            ForEach(state.bursts) { burst in
                if let at = anchors[burst.at] {
                    DuelSparkleBurst(center: proxy[at].center) {
                        state.endBurst(burst)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Flying ghost

private struct DuelFlightView: View {
    let flight: DuelFlight
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
            .position(moved ? end.center : start.center)
            .onAppear(perform: fly)
    }

    private func fly() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(flight.delay)) {
            moved = true
        } completion: {
            land()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + flight.delay + 0.62) { land() }
    }

    private func land() {
        guard !didLand else { return }
        didLand = true
        onLand()
    }

    @ViewBuilder private var ghost: some View {
        switch flight.kind {
        case let .gem(color):
            ZStack {
                Circle().fill(color.tint)
                Circle().strokeBorder(.black.opacity(0.10), lineWidth: 1)
                Image(systemName: color.iconName)
                    .font(.system(size: start.width * 0.4, weight: .semibold))
                    .foregroundStyle(color.foreground)
            }
            .shadow(color: color.tint.opacity(0.5), radius: 6)
        case let .cardBuy(card):
            DuelCardView(card: card)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        case let .cardReserve(card):
            DuelCardView(card: card)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
    }
}

// MARK: - Golden sparkle burst

private struct DuelSparkleBurst: View {
    let center: CGPoint
    var count = 12
    let onDone: () -> Void

    @State private var t: CGFloat = 0
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.35)

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(Double(0.5 * (1 - t))))
                .frame(width: 26, height: 26)
                .scaleEffect(1 + t * 2.2)

            ForEach(0 ..< count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(gold)
                    .scaleEffect(0.4 + (1 - t) * 0.9)
                    .opacity(Double(1 - t))
                    .offset(x: CGFloat(cos(angle)) * 48 * t, y: CGFloat(sin(angle)) * 48 * t)
            }
        }
        .position(center)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { t = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { onDone() }
        }
    }
}
