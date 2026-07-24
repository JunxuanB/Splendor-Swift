import SwiftUI

/// Shared SF Symbol names for Duel-specific concepts.
enum DuelSymbol {
    static let privilege = "wand.and.stars"  // 权杖
    static let crown = "crown.fill"
    static let bag = "bag.fill"
}

extension DuelColor {
    /// Single source of truth for every Duel color. The five gems match the base
    /// game's jewel tones; pearl is a soft iridescent white; gold is the wild joker.
    var tint: Color {
        switch self {
        case .white: Color(red: 0.93, green: 0.95, blue: 0.99)
        case .blue: Color(red: 0.11, green: 0.44, blue: 0.93)
        case .green: Color(red: 0.05, green: 0.67, blue: 0.44)
        case .black: Color(red: 0.20, green: 0.22, blue: 0.29)
        case .red: Color(red: 0.88, green: 0.18, blue: 0.31)
        case .pearl: Color(red: 0.90, green: 0.86, blue: 0.94)
        case .gold: Color(red: 0.98, green: 0.72, blue: 0.16)
        }
    }

    var foreground: Color {
        switch self {
        case .blue, .green, .black, .red: .white
        case .white, .pearl, .gold: .black
        }
    }

    var iconName: String {
        switch self {
        case .white: "diamond.fill"
        case .blue: "drop.fill"
        case .green: "leaf.fill"
        case .black: "moon.fill"
        case .red: "flame.fill"
        case .pearl: "circle.circle.fill"
        case .gold: "seal.fill"
        }
    }
}

/// A single gem token as it appears on the 5×5 board.
struct DuelBoardToken: View {
    let color: DuelColor
    var diameter: CGFloat = 40
    var isSelected = false
    var isSelectable = true

    var body: some View {
        ZStack {
            Circle().fill(color.tint)
            Circle()
                .strokeBorder(isSelected ? Color.accentColor : .black.opacity(0.12),
                              lineWidth: isSelected ? 4 : 1)
            Image(systemName: color.iconName)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(color.foreground)
        }
        .frame(width: diameter, height: diameter)
        .opacity(isSelectable ? 1 : 0.5)
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        .accessibilityLabel("\(color.displayName)宝石")
        .accessibilityValue(isSelected ? "已选择" : "")
    }
}

/// A player's held resource: permanent bonus count (square) + loose tokens (dot).
/// Pearl and gold have no permanent bonus, so they render as a single token.
struct DuelResourceStack: View {
    let color: DuelColor
    let permanent: Int
    let tokens: Int
    var compact = false

    var body: some View {
        if color == .pearl || color == .gold {
            ZStack {
                Circle()
                    .fill(color.tint)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                Text("\(tokens)")
                    .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
                    .foregroundStyle(color.foreground)
            }
            .frame(width: compact ? 31 : 36, height: compact ? 31 : 36)
            .frame(width: compact ? 36 : 43, height: compact ? 44 : 55, alignment: .bottom)
            .accessibilityLabel("\(color.displayName)，\(tokens) 枚")
        } else {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(color.tint)
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                            .strokeBorder(.black.opacity(0.10))
                    }
                    .frame(width: compact ? 31 : 38, height: compact ? 39 : 50)
                    .overlay {
                        Text("\(permanent)")
                            .font(.system(size: compact ? 15 : 19, weight: .bold, design: .rounded))
                            .foregroundStyle(color.foreground)
                    }

                Circle()
                    .fill(color.tint)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .overlay {
                        Text("\(tokens)")
                            .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(color.foreground)
                    }
                    .frame(width: compact ? 20 : 23, height: compact ? 20 : 23)
                    .offset(x: 4, y: 4)
            }
            .frame(width: compact ? 36 : 43, height: compact ? 44 : 55, alignment: .topLeading)
            .accessibilityLabel("\(color.displayName)，发展卡 \(permanent) 张，筹码 \(tokens) 枚")
        }
    }
}

struct DuelCostBadge: View {
    let color: DuelColor
    let value: Int
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(color.tint)
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.75))
            .overlay {
                Text("\(value)")
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(color.foreground)
            }
            .frame(width: size, height: size)
            .accessibilityLabel("\(color.displayName) \(value)")
    }
}

struct DuelCostRow: View {
    let cost: [DuelColor: Int]
    var badgeSize: CGFloat = 18
    var perRow = 3

    private var entries: [(color: DuelColor, value: Int)] {
        DuelColor.resourceOrder.compactMap { color in
            guard let value = cost[color], value > 0 else { return nil }
            return (color, value)
        }
    }

    private var rows: [[(color: DuelColor, value: Int)]] {
        stride(from: 0, to: entries.count, by: perRow).map { start in
            Array(entries[start ..< min(start + perRow, entries.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.color) { entry in
                        DuelCostBadge(color: entry.color, value: entry.value, size: badgeSize)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Small crown pip used on cards and the crown win-track.
struct DuelCrownBadge: View {
    let count: Int
    var size: CGFloat = 16

    private let crownColor = Color(red: 0.86, green: 0.66, blue: 0.20)

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.72, weight: .semibold))
            Text("\(count)")
                .font(.system(size: size * 0.72, weight: .bold, design: .rounded))
        }
        .foregroundStyle(crownColor)
        .accessibilityLabel("\(count) 王冠")
    }
}

/// Crowns on a development card, shown as repeated crown icons (max 3): 👑👑👑.
struct DuelCardCrowns: View {
    let count: Int
    var size: CGFloat = 11

    private let crownColor = Color(red: 0.86, green: 0.66, blue: 0.20)

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< max(0, count), id: \.self) { _ in
                Image(systemName: "crown.fill").font(.system(size: size))
            }
        }
        .foregroundStyle(crownColor)
        .accessibilityLabel("\(count) 王冠")
    }
}

/// A slowly rotating iridescent border used to highlight affordable Duel cards.
struct DuelShimmerBorder: View {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 2

    private let colors: [Color] = [
        Color(red: 0.40, green: 0.80, blue: 1.00),
        Color(red: 0.60, green: 0.55, blue: 1.00),
        Color(red: 0.90, green: 0.50, blue: 0.95),
        Color(red: 1.00, green: 0.55, blue: 0.75),
        Color(red: 1.00, green: 0.82, blue: 0.45),
        Color(red: 0.50, green: 1.00, blue: 0.75),
        Color(red: 0.40, green: 0.80, blue: 1.00),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((seconds * 70).truncatingRemainder(dividingBy: 360))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(gradient: Gradient(colors: colors), center: .center, angle: angle),
                    lineWidth: lineWidth
                )
        }
        .allowsHitTesting(false)
    }
}
