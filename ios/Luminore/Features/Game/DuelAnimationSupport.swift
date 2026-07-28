import LuminoreCore
import SwiftUI

// MARK: - Anchor plumbing

/// Stable identity for every point a Duel flying animation can start from or land on.
/// Every case is a *persistent position* (a board cell, a player's gem stack, the bag,
/// a market slot) so that flights derived from a snapshot delta still resolve even
/// though the moved content has already changed underneath.
enum DuelAnchorID: Hashable {
    case boardCell(Int)
    case takeControl
    case token(UUID, DuelTokenColor)
    case bag
    case deck(Int)
    case marketSlot(Int, Int)
    case reserved(UUID)
    case score(UUID)
    case victory(UUID)
    case marketCard(String)
    case royal(String)
    case privilegeControl
    case replenishControl
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
        case gem(DuelTokenColor)
        case card(DuelJewelCard)
    }

    let id = UUID()
    let kind: Kind
    let from: DuelAnchorID
    let to: DuelAnchorID
    var delay: Double = 0
    // Frozen once resolved, so the ghost keeps flying after the source/destination
    // view disappears when the authoritative snapshot flips.
    var resolvedStart: CGRect?
    var resolvedEnd: CGRect?
}

struct DuelBurst: Identifiable {
    let id = UUID()
    let at: DuelAnchorID
}

// MARK: - Root flight layer

struct DuelFlightLayer: View {
    let flights: [DuelFlight]
    let bursts: [DuelBurst]
    let anchors: [DuelAnchorID: Anchor<CGRect>]
    let proxy: GeometryProxy
    let onFlightEnded: (UUID) -> Void
    let onFlightResolved: (UUID, CGRect, CGRect) -> Void
    let onBurstEnded: (UUID) -> Void

    var body: some View {
        ZStack {
            ForEach(flights) { flight in
                if let start = flight.resolvedStart ?? anchors[flight.from].map({ proxy[$0] }),
                   let end = flight.resolvedEnd ?? anchors[flight.to].map({ proxy[$0] }) {
                    DuelFlightView(flight: flight, start: start, end: end) {
                        onFlightEnded(flight.id)
                    }
                    .onAppear {
                        guard flight.resolvedStart == nil || flight.resolvedEnd == nil else { return }
                        onFlightResolved(flight.id, start, end)
                    }
                }
            }

            ForEach(bursts) { burst in
                if let anchor = anchors[burst.at] {
                    DuelSparkleBurst(center: proxy[anchor].duelCenter) { onBurstEnded(burst.id) }
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
        case .card: 0.32
        }
    }

    var body: some View {
        ghost
            .frame(width: start.width, height: start.height)
            .scaleEffect(moved ? endScale : 1)
            .opacity(moved ? 0.15 : 1)
            .position(moved ? end.duelCenter : start.duelCenter)
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
        case let .card(card):
            DuelJewelCardView(card: card)
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

private extension CGRect {
    var duelCenter: CGPoint { CGPoint(x: midX, y: midY) }
}
