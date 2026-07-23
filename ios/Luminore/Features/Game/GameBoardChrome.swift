import LuminoreCore
import SwiftUI

struct GameNavigationBar: View {
    let deadline: Date?
    let hasTimer: Bool
    let gracePeriodEnabled: Bool
    let canPause: Bool
    let onPause: () -> Void
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let deadline, hasTimer {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let rawRemaining = Int(deadline.timeIntervalSince(context.date).rounded(.up))
                        let remaining = gracePeriodEnabled
                            ? max(-5, rawRemaining)
                            : max(0, rawRemaining)
                        CountdownLabel(remaining: remaining)
                    }
                } else {
                    Label("game.noTimer", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("game.board.title")
                .font(.headline)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 14) {
                Spacer(minLength: 0)
                if canPause {
                    Button(action: onPause) {
                        Image(systemName: "pause.circle")
                    }
                    .accessibilityLabel(Text("game.pause.accessibility"))
                }
                Button("game.exit", role: .destructive, action: onExit)
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .background {
            Rectangle().fill(.bar).ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct CountdownLabel: View {
    let remaining: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "timer").font(.footnote.weight(.semibold))
            Text("\(remaining)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
        }
        .foregroundStyle(remaining <= 5 ? Color.red : .primary)
        .padding(.horizontal, remaining <= 5 ? 8 : 0)
        .padding(.vertical, 3)
        .background(remaining <= 5 ? Color.red.opacity(0.14) : Color.clear, in: Capsule())
        .animation(.snappy, value: remaining <= 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("game.timer.accessibility"))
        .accessibilityValue(Text("game.timer.remaining \(remaining)"))
    }
}

struct VictoryProgressHeader: View {
    let current: Int
    let target: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.subheadline)
                .foregroundStyle(.blue)
            ProgressView(value: Double(current), total: Double(target)).tint(.blue)
            Text(String(format: "%02d / %02d", current, target))
                .font(.subheadline.bold().monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("game.victory.accessibility \(current) \(target)"))
    }
}

struct PlayerInventoryBar: View {
    let player: PublicPlayerSnapshot
    let reservedCardCount: Int
    let isCurrentPlayer: Bool
    let deadline: Date?
    let turnDurationSeconds: Int?
    let onOpenReservedCards: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenReservedCards) {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(player.prestige)")
                            .font(.title.bold().monospacedDigit())
                            .contentTransition(.numericText())
                            .popEffect(trigger: player.prestige)
                            .gameFlightAnchor(.scoreLabel)
                        Text("game.score.total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 2) {
                            Text("\(reservedCardCount) / 3")
                                .font(.caption.bold().monospacedDigit())
                                .contentTransition(.numericText())
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .popEffect(trigger: reservedCardCount)
                        Text("game.stat.reserved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .gameFlightAnchor(.reservedArea)
                }
                .frame(width: 54, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("game.inventory.accessibility \(player.prestige) \(reservedCardCount)"))
            .accessibilityHint(Text("game.inventory.hint"))

            Divider().frame(height: 62)

            HStack(spacing: 5) {
                ForEach(GemColor.allCases) { gem in
                    ResourceStackView(
                        gem: gem,
                        permanent: player.bonuses[gem, default: 0],
                        tokens: player.tokens[gem, default: 0]
                    )
                    .popEffect(trigger: player.tokens[gem, default: 0] + player.bonuses[gem, default: 0])
                    .gameFlightAnchor(.playerStack(gem))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            if isCurrentPlayer {
                TurnProgressBar(deadline: deadline, duration: turnDurationSeconds)
            } else {
                Divider()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct TurnProgressBar: View {
    let deadline: Date?
    let duration: Int?

    var body: some View {
        if let deadline, let duration {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let remaining = max(0, deadline.timeIntervalSince(context.date))
                let progress = min(1, remaining / Double(duration))
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * progress)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 3)
        } else {
            Rectangle().fill(Color.accentColor).frame(height: 3)
        }
    }
}

struct CurrentTurnBorder: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let cycleDuration = 16.0
            let progress = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            let angle = Angle.degrees(progress * 360)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color.accentColor.opacity(0.12),
                            Color.cyan.opacity(0.72),
                            Color.white.opacity(0.82),
                            Color.cyan.opacity(0.42),
                            Color.accentColor.opacity(0.12),
                            Color.accentColor.opacity(0.12)
                        ],
                        center: .center,
                        startAngle: angle,
                        endAngle: angle + .degrees(360)
                    ),
                    lineWidth: 3
                )
                .shadow(color: Color.accentColor.opacity(0.3), radius: 7)
                .padding(2)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GracePeriodBorder: View {
    let deadline: Date

    var body: some View {
        TimelineView(.animation) { context in
            let overdue = context.date.timeIntervalSince(deadline)
            if overdue >= 0, overdue <= 5.2 {
                let pulse = (sin(context.date.timeIntervalSinceReferenceDate * .pi * 3) + 1) / 2
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color.red.opacity(0.32 + pulse * 0.68),
                        lineWidth: 5
                    )
                    .shadow(color: Color.red.opacity(0.25 + pulse * 0.55), radius: 12)
                    .padding(2)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
