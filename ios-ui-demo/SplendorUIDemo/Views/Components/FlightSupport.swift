import SwiftUI

// MARK: - Anchor plumbing

/// Stable identity for every point a flying animation can start from or land on.
enum AnchorID: Hashable {
    case bankGem(GemColor)
    case playerStack(GemColor)
    case scoreLabel
    case reservedArea
    case marketCard(String) // DevelopmentCard.id
    case nobleTile(String)  // NobleTile.id
}

/// Collects the on-screen bounds of every registered anchor so the root flight
/// layer can resolve source/destination positions in a single coordinate space.
struct AnchorKey: PreferenceKey {
    static var defaultValue: [AnchorID: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [AnchorID: Anchor<CGRect>],
        nextValue: () -> [AnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Register this view as a flight anchor. Attach at the call site so the
    /// underlying components stay generic and reusable.
    func flightAnchor(_ id: AnchorID) -> some View {
        anchorPreference(key: AnchorKey.self, value: .bounds) { [id: $0] }
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - Flight & burst models

/// A single in-flight "ghost" travelling from one anchor to another.
struct Flight: Identifiable {
    enum Kind {
        case gem(GemColor)
        case cardBuy(DevelopmentCard)
        case cardReserve(DevelopmentCard)
        case noble(NobleTile)
    }

    let id = UUID()
    let kind: Kind
    let from: AnchorID
    let to: AnchorID
    var delay: Double = 0
}

/// A one-shot golden sparkle burst anchored to a point (e.g. the total score).
struct Burst: Identifiable {
    let id = UUID()
    let at: AnchorID
}

// MARK: - Root flight layer

/// Sits above the board and renders every active flight/burst by resolving the
/// collected anchors through a single proxy so positions line up pixel-accurately.
struct FlightLayer: View {
    @ObservedObject var state: DemoGameState
    let anchors: [AnchorID: Anchor<CGRect>]
    let proxy: GeometryProxy

    var body: some View {
        ZStack {
            ForEach(state.flights) { flight in
                if let from = anchors[flight.from], let to = anchors[flight.to] {
                    FlightView(
                        flight: flight,
                        start: proxy[from],
                        end: proxy[to]
                    ) {
                        state.land(flight)
                    }
                }
            }

            ForEach(state.bursts) { burst in
                if let at = anchors[burst.at] {
                    SparkleBurst(center: proxy[at].center) {
                        state.endBurst(burst)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Flying ghost

private struct FlightView: View {
    let flight: Flight
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
            .position(moved ? end.center : start.center)
            .onAppear(perform: run)
    }

    private func run() {
        if isNoble {
            // Playful wiggle in place, then fly toward the score.
            withAnimation(.easeInOut(duration: 0.08).repeatCount(7, autoreverses: true)) {
                wiggle = 9
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                wiggle = 0
                fly(delay: 0)
            }
        } else {
            fly(delay: flight.delay)
        }
    }

    private func fly(delay: Double) {
        withAnimation(
            .spring(response: flightResponse, dampingFraction: 0.82).delay(delay)
        ) {
            moved = true
        } completion: {
            land()
        }
        // Safety net in case the completion handler is preempted (e.g. a rapid
        // re-render): guarantee the state mutation still fires exactly once.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + flightResponse + 0.1) {
            land()
        }
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

        case let .cardBuy(card):
            DevelopmentCardView(card: card)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

        case let .cardReserve(card):
            DevelopmentCardView(card: card)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

        case let .noble(noble):
            NobleTileView(noble: noble)
                .shadow(color: Color(red: 0.86, green: 0.66, blue: 0.20).opacity(0.5), radius: 8)
        }
    }
}

// MARK: - Golden sparkle burst

private struct SparkleBurst: View {
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

            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(gold)
                    .scaleEffect(0.4 + (1 - t) * 0.9)
                    .opacity(Double(1 - t))
                    .offset(
                        x: CoreGraphicsCos(angle) * 48 * t,
                        y: CoreGraphicsSin(angle) * 48 * t
                    )
            }
        }
        .position(center)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { t = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { onDone() }
        }
    }
}

// Thin wrappers keep the trig calls unambiguous for the type-checker.
private func CoreGraphicsCos(_ x: Double) -> CGFloat { CGFloat(cos(x)) }
private func CoreGraphicsSin(_ x: Double) -> CGFloat { CGFloat(sin(x)) }

// MARK: - Number "pop" on increment

private struct PopEffect: ViewModifier {
    let trigger: Int
    @State private var pop = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pop ? 1.35 : 1)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
                    pop = true
                }
                withAnimation(.spring(response: 0.30, dampingFraction: 0.70).delay(0.12)) {
                    pop = false
                }
            }
    }
}

extension View {
    /// Springy scale pop whenever `trigger` changes — drive it with the count itself.
    func popEffect(trigger: Int) -> some View {
        modifier(PopEffect(trigger: trigger))
    }
}

// MARK: - Temporary debug trigger bar

/// A temporary horizontal strip of buttons that fire each animation on demand.
struct DebugAnimationBar: View {
    @ObservedObject var state: DemoGameState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Label("调试", systemImage: "hammer.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                Button("拿宝石") { state.flyGems([.diamond: 2, .ruby: 1]) }
                Button("买牌") { state.debugBuy() }
                Button("预留") { state.debugReserve() }
                Button("贵族") { state.gainNoble(state.nobles[0]) }
                Button("金光") { state.sparkleScore() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption2.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }
}
