import LuminoreCore
import SwiftUI

struct OpeningTurnRouletteView: View {
    let players: [PublicPlayerSnapshot]
    let startingPlayerID: UUID
    let selection: OpeningTurnSelection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var startingIndex: Int {
        players.firstIndex(where: { $0.id == startingPlayerID }) ?? 0
    }

    private var startingPlayer: PublicPlayerSnapshot? {
        players.first(where: { $0.id == startingPlayerID })
    }

    private var orderedPlayers: [PublicPlayerSnapshot] {
        guard !players.isEmpty else { return [] }
        return Array(players[startingIndex...]) + Array(players[..<startingIndex])
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let progress = animationProgress(at: timeline.date)
            let revealsWinner = reduceMotion || progress >= 0.75

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Text(revealsWinner ? "game.opening.selected" : "game.opening.deciding")
                        .font(.title2.bold())

                    roulette(progress: reduceMotion ? 1 : progress)

                    VStack(spacing: 10) {
                        if let startingPlayer, revealsWinner {
                            Text("game.opening.starts \(startingPlayer.nickname)")
                                .font(.headline)
                                .contentTransition(.numericText())
                        }

                        if revealsWinner {
                            Text("game.opening.order")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(orderedPlayers.map(\.nickname).joined(separator: "  →  "))
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .minimumScaleFactor(0.72)
                        } else {
                            Text("game.opening.order.pending")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 360)
                }
                .padding(28)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary(revealsWinner: revealsWinner))
        }
    }

    private func roulette(progress: Double) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let segmentAngle = 360 / Double(max(players.count, 1))
            let targetOffset = -(Double(startingIndex) + 0.5) * segmentAngle
            let easedProgress = 1 - pow(1 - progress, 4)
            let rotation = (360 * 5 + targetOffset) * easedProgress

            ZStack {
                ZStack {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        RouletteSegment(
                            startAngle: -90 + Double(index) * segmentAngle,
                            endAngle: -90 + Double(index + 1) * segmentAngle
                        )
                        .fill(segmentColor(at: index))

                        Text(player.nickname)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: side * 0.32)
                            .offset(y: -side * 0.31)
                            .rotationEffect(.degrees((Double(index) + 0.5) * segmentAngle))
                    }
                }
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 5))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                .rotationEffect(.degrees(rotation))

                Circle()
                    .fill(.regularMaterial)
                    .frame(width: side * 0.2, height: side * 0.2)
                    .overlay(Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint))
                    .shadow(radius: 4, y: 2)

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.primary)
                    .offset(y: -side / 2 - 11)
                    .shadow(color: .white.opacity(0.8), radius: 1)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(height: 300)
    }

    private func animationProgress(at date: Date) -> Double {
        let duration = max(selection.endsAt.timeIntervalSince(selection.startedAt), 0.001)
        let elapsed = date.timeIntervalSince(selection.startedAt)
        return min(max(elapsed / duration, 0), 1)
    }

    private func segmentColor(at index: Int) -> Color {
        let colors: [Color] = [.indigo, .cyan, .green, .orange, .pink, .purple, .blue]
        return colors[index % colors.count]
    }

    private func accessibilitySummary(revealsWinner: Bool) -> Text {
        guard revealsWinner, let startingPlayer else { return Text("game.opening.deciding") }
        return Text("game.opening.starts \(startingPlayer.nickname)")
    }
}

private struct RouletteSegment: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
