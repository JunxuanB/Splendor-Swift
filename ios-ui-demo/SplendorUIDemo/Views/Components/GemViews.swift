import SwiftUI

extension GemColor {
    var tint: Color {
        switch self {
        case .diamond: Color.gray.opacity(0.22)
        case .sapphire: .blue
        case .emerald: .green
        case .ruby: .red
        case .onyx: Color.black.opacity(0.78)
        case .gold: .yellow
        }
    }

    var foreground: Color {
        switch self {
        case .diamond, .gold: .black
        default: .white
        }
    }

    var iconName: String {
        switch self {
        case .diamond: "diamond.fill"
        case .sapphire: "drop.fill"
        case .emerald: "leaf.fill"
        case .ruby: "flame.fill"
        case .onyx: "moon.fill"
        case .gold: "seal.fill"
        }
    }
}

struct GemTokenView: View {
    let gem: GemColor
    let count: Int
    var diameter: CGFloat = 44
    var selectionCount = 0
    var disabled = false

    private var isSelected: Bool { selectionCount > 0 }

    var body: some View {
        ZStack {
            Circle()
                .fill(gem.tint.gradient)
            Circle()
                .strokeBorder(isSelected ? Color.accentColor : .primary.opacity(0.14), lineWidth: isSelected ? 4 : 1)

            VStack(spacing: 0) {
                Image(systemName: gem.iconName)
                    .font(.system(size: diameter * 0.25, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: diameter * 0.34, weight: .bold, design: .rounded))
            }
            .foregroundStyle(gem.foreground)

            if isSelected {
                Text("×\(selectionCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.accentColor, in: Circle())
                    .offset(x: diameter * 0.36, y: -diameter * 0.36)
            }
        }
        .frame(width: diameter, height: diameter)
        .opacity(disabled ? 0.58 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gem.displayName)，\(count) 枚")
        .accessibilityValue(isSelected ? "已选择 \(selectionCount) 枚" : "未选择")
    }
}

struct ResourceStackView: View {
    let gem: GemColor
    let permanent: Int
    let tokens: Int
    var compact = false

    var body: some View {
        if gem == .gold {
            GemTokenView(gem: .gold, count: tokens, diameter: compact ? 31 : 36)
                .frame(width: compact ? 35 : 40, height: compact ? 42 : 54, alignment: .bottom)
        } else {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(gem.tint.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                            .strokeBorder(.primary.opacity(0.12))
                    }
                    .frame(width: compact ? 31 : 38, height: compact ? 39 : 50)
                    .overlay {
                        Text("\(permanent)")
                            .font(.system(size: compact ? 15 : 19, weight: .bold, design: .rounded))
                            .foregroundStyle(gem.foreground)
                    }

                Circle()
                    .fill(gem.tint)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .overlay {
                        Text("\(tokens)")
                            .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(gem.foreground)
                    }
                    .frame(width: compact ? 20 : 23, height: compact ? 20 : 23)
                    .offset(x: 4, y: 4)
            }
            .frame(width: compact ? 36 : 43, height: compact ? 44 : 55, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(gem.displayName)，发展卡 \(permanent) 张，筹码 \(tokens) 枚")
        }
    }
}

struct CostBadge: View {
    let gem: GemColor
    let value: Int
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(gem.tint)
            .overlay(Circle().strokeBorder(.primary.opacity(0.16)))
            .overlay {
                Text("\(value)")
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(gem.foreground)
            }
            .frame(width: size, height: size)
            .accessibilityLabel("\(gem.displayName) \(value)")
    }
}

struct CardCostGrid: View {
    let costs: [GemColor: Int]
    var badgeSize: CGFloat = 18

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(badgeSize), spacing: 3), count: 3)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
            ForEach(GemColor.allCases) { gem in
                if let value = costs[gem], value > 0 {
                    CostBadge(gem: gem, value: value, size: badgeSize)
                } else {
                    Color.clear
                        .frame(width: badgeSize, height: badgeSize)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct NobleRequirementBadge: View {
    let gem: GemColor
    let value: Int
    var height: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
            .fill(gem.tint)
            .overlay {
                Text("\(value)")
                    .font(.system(size: height * 0.62, weight: .bold, design: .rounded))
                    .foregroundStyle(gem.foreground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
                    .strokeBorder(.primary.opacity(0.14))
            }
            .frame(width: height * 1.3, height: height)
            .accessibilityLabel("\(gem.displayName) \(value)")
    }
}
