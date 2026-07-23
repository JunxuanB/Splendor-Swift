import LuminoreCore
import SwiftUI

extension GemColor {
    var tint: Color {
        switch self {
        case .diamond: Color(red: 0.93, green: 0.95, blue: 0.99)
        case .sapphire: Color(red: 0.11, green: 0.44, blue: 0.93)
        case .emerald: Color(red: 0.05, green: 0.67, blue: 0.44)
        case .ruby: Color(red: 0.88, green: 0.18, blue: 0.31)
        case .onyx: Color(red: 0.20, green: 0.22, blue: 0.29)
        case .gold: Color(red: 0.98, green: 0.72, blue: 0.16)
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

    var localizedKey: LocalizedStringKey {
        switch self {
        case .diamond: "gem.diamond"
        case .sapphire: "gem.sapphire"
        case .emerald: "gem.emerald"
        case .ruby: "gem.ruby"
        case .onyx: "gem.onyx"
        case .gold: "gem.gold"
        }
    }

    var shortLocalizedKey: LocalizedStringKey {
        switch self {
        case .diamond: "gem.diamond.short"
        case .sapphire: "gem.sapphire.short"
        case .emerald: "gem.emerald.short"
        case .ruby: "gem.ruby.short"
        case .onyx: "gem.onyx.short"
        case .gold: "gem.gold.short"
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
            Circle().fill(gem.tint)
            Circle()
                .strokeBorder(
                    isSelected ? Color.accentColor : .black.opacity(0.10),
                    lineWidth: isSelected ? 4 : 1
                )

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
        .accessibilityLabel(Text(gem.localizedKey))
        .accessibilityValue(Text("game.gem.count \(count)"))
        .accessibilityHint(Text(isSelected ? "game.gem.selected \(selectionCount)" : "game.gem.notSelected"))
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
                    .fill(gem.tint)
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                            .strokeBorder(.black.opacity(0.10))
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
            .accessibilityLabel(Text(gem.localizedKey))
            .accessibilityValue(Text("game.resource.accessibility \(permanent) \(tokens)"))
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
            .overlay(Circle().strokeBorder(.black.opacity(0.10), lineWidth: 0.75))
            .overlay {
                Text("\(value)")
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(gem.foreground)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(Text(gem.localizedKey))
            .accessibilityValue("\(value)")
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

    private var cornerRadius: CGFloat { height * 0.30 }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(gem.tint)
            .overlay {
                Text("\(value)")
                    .font(.system(size: height * 0.58, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(gem.foreground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.black.opacity(0.10), lineWidth: 0.75)
            }
            .frame(width: height * 0.74, height: height)
            .accessibilityLabel(Text(gem.localizedKey))
            .accessibilityValue("\(value)")
    }
}

struct DevelopmentCardView: View {
    let card: DevelopmentCard
    var enlarged = false
    var compactHeight: CGFloat = 80
    var isPurchasable = false

    private var cornerRadius: CGFloat { enlarged ? 24 : 14 }
    private var cardHeight: CGFloat { enlarged ? 220 : compactHeight }
    private var headerHeight: CGFloat {
        enlarged ? 110 : max(30, min(compactHeight * 0.34, 46))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: enlarged ? 12 : 5) {
            HStack(alignment: .top) {
                if card.prestige > 0 {
                    Text("\(card.prestige)")
                        .font(enlarged ? .largeTitle.bold() : .headline.bold())
                }
                Spacer()
                Image(systemName: card.bonus.iconName)
                    .font(enlarged ? .title : .caption)
                    .foregroundStyle(card.bonus.foreground)
                    .padding(enlarged ? 10 : 4)
                    .background(card.bonus.tint, in: Circle())
            }

            Spacer(minLength: 0)

            CardCostGrid(costs: card.cost, badgeSize: enlarged ? 30 : 18)
        }
        .padding(enlarged ? 18 : 6)
        .frame(
            maxWidth: .infinity,
            minHeight: cardHeight,
            maxHeight: cardHeight,
            alignment: .leading
        )
        .background(alignment: .top) {
            card.bonus.tint.opacity(0.20)
                .frame(height: headerHeight)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(shape)
        .overlay {
            if isPurchasable {
                ShimmerBorder(cornerRadius: cornerRadius, lineWidth: enlarged ? 2.5 : 1.75)
            } else {
                shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("game.card.accessibility \(card.tier) \(card.prestige)"))
        .accessibilityValue(Text(isPurchasable ? "game.card.affordable" : "game.card.unaffordable"))
        .accessibilityHint(Text("game.card.hint"))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

struct NobleTileView: View {
    let noble: NobleTile
    var enlarged = false

    private var cornerRadius: CGFloat { enlarged ? 26 : 14 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "crown.fill")
                    .font(enlarged ? .title3 : .caption)
                    .foregroundStyle(Color(red: 0.86, green: 0.66, blue: 0.20))
                Spacer()
                Text("\(noble.prestige)")
                    .font(enlarged
                        ? .system(size: 30, weight: .bold, design: .rounded)
                        : .system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: enlarged ? 14 : 6)

            HStack(spacing: enlarged ? 10 : 3) {
                ForEach(requirements, id: \.key) { gem, value in
                    NobleRequirementBadge(gem: gem, value: value, height: enlarged ? 40 : 21)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(enlarged ? 20 : 8)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            Color(red: 0.48, green: 0.40, blue: 0.68).opacity(0.14),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(red: 0.48, green: 0.40, blue: 0.68).opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("game.noble.accessibility \(noble.prestige)"))
        .accessibilityHint(Text("game.noble.hint"))
    }

    private var requirements: [(key: GemColor, value: Int)] {
        GemColor.allCases.compactMap { gem in
            guard let value = noble.requirement[gem] else { return nil }
            return (gem, value)
        }
    }
}

struct ShimmerBorder: View {
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

private struct PopEffect: ViewModifier {
    let trigger: Int
    @State private var pop = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pop ? 1.35 : 1)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { pop = true }
                withAnimation(.spring(response: 0.30, dampingFraction: 0.70).delay(0.12)) { pop = false }
            }
    }
}

extension View {
    func popEffect(trigger: Int) -> some View {
        modifier(PopEffect(trigger: trigger))
    }
}

extension PublicPlayerSnapshot {
    var bonuses: [GemColor: Int] {
        Dictionary(grouping: purchasedCards, by: \DevelopmentCard.bonus).mapValues(\.count)
    }

    var developmentCardCount: Int { purchasedCards.count }
    var tokenCount: Int { tokens.values.reduce(0, +) }
}
