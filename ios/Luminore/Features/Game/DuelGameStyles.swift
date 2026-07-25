import LuminoreCore
import SwiftUI

extension DuelTokenColor {
    var tint: Color {
        switch self {
        case .diamond: Color(red: 0.93, green: 0.95, blue: 0.99)
        case .sapphire: Color(red: 0.11, green: 0.44, blue: 0.93)
        case .emerald: Color(red: 0.05, green: 0.67, blue: 0.44)
        case .ruby: Color(red: 0.88, green: 0.18, blue: 0.31)
        case .onyx: Color(red: 0.20, green: 0.22, blue: 0.29)
        case .pearl: Color(red: 0.94, green: 0.80, blue: 0.88)
        case .gold: Color(red: 0.98, green: 0.72, blue: 0.16)
        }
    }

    var foreground: Color {
        switch self {
        case .sapphire, .emerald, .ruby, .onyx: .white
        case .diamond, .pearl, .gold: .black
        }
    }

    /// Matches the standard board's restrained, outline-only icon language.
    var iconName: String {
        switch self {
        case .diamond: "diamond"
        case .sapphire: "drop"
        case .emerald: "leaf"
        case .ruby: "flame"
        case .onyx: "moon"
        case .pearl: "circle.circle"
        case .gold: "seal"
        }
    }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .diamond: "gem.diamond"
        case .sapphire: "gem.sapphire"
        case .emerald: "gem.emerald"
        case .ruby: "gem.ruby"
        case .onyx: "gem.onyx"
        case .pearl: "duel.gem.pearl"
        case .gold: "gem.gold"
        }
    }
}

extension DuelGemColor {
    var tokenColor: DuelTokenColor { DuelTokenColor(self) }
    var tint: Color { tokenColor.tint }
    var foreground: Color { tokenColor.foreground }
    var iconName: String { tokenColor.iconName }
    var localizedKey: LocalizedStringKey { tokenColor.localizedKey }
}

extension DuelCardAbility {
    var iconName: String {
        switch self {
        case .extraTurn: "arrow.clockwise"
        case .takeMatchingToken: "hand.point.up.left"
        case .takePrivilege: "wand.and.stars"
        case .stealToken: "arrow.left.arrow.right"
        }
    }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .extraTurn: "duel.ability.extraTurn"
        case .takeMatchingToken: "duel.ability.takeMatching"
        case .takePrivilege: "duel.ability.takePrivilege"
        case .stealToken: "duel.ability.steal"
        }
    }
}

struct DuelTokenChip: View {
    let color: DuelTokenColor
    var count: Int? = nil
    var diameter: CGFloat = 42
    var selected = false
    var dimmed = false

    var body: some View {
        ZStack {
            Circle().fill(color.tint)
            Circle().strokeBorder(selected ? Color.accentColor : .black.opacity(0.12), lineWidth: selected ? 4 : 1)
            VStack(spacing: 0) {
                Image(systemName: color.iconName)
                    .font(.system(size: diameter * (count == nil ? 0.38 : 0.24), weight: .semibold))
                if let count {
                    Text("\(count)")
                        .font(.system(size: diameter * 0.30, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(color.foreground)
        }
        .frame(width: diameter, height: diameter)
        .opacity(dimmed ? 0.48 : 1)
        .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(color.localizedKey))
        .accessibilityValue(count.map(String.init) ?? (selected ? String(localized: "duel.selected") : ""))
    }
}

struct DuelResourceStack: View {
    let color: DuelTokenColor
    let bonus: Int
    let tokens: Int

    var body: some View {
        if color.gemColor == nil {
            // Pearl and gold have no permanent bonus — render as a single token dot.
            ZStack {
                Circle().fill(color.tint)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                Text("\(tokens)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(color.foreground)
            }
            .frame(width: 31, height: 31)
            .frame(width: 36, height: 43, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(color.localizedKey))
            .accessibilityValue("\(tokens)")
        } else {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.tint)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(0.10)))
                    .frame(width: 31, height: 39)
                    .overlay {
                        Text("\(bonus)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(color.foreground)
                    }
                Circle().fill(color.tint)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .overlay {
                        Text("\(tokens)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(color.foreground)
                    }
                    .frame(width: 20, height: 20)
                    .offset(x: 4, y: 4)
            }
            .frame(width: 36, height: 43, alignment: .topLeading)
        }
    }
}

struct DuelCostRow: View {
    let cost: [DuelTokenColor: Int]
    var size: CGFloat = 16

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 2), count: 3), alignment: .leading, spacing: 2) {
            ForEach(DuelTokenColor.boardTakeable) { color in
                if let value = cost[color], value > 0 {
                    Circle().fill(color.tint)
                        .overlay(Circle().strokeBorder(.black.opacity(0.10)))
                        .overlay {
                            Text("\(value)")
                                .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                                .foregroundStyle(color.foreground)
                        }
                        .frame(width: size, height: size)
                }
            }
        }
    }
}

struct DuelJewelCardView: View {
    let card: DuelJewelCard
    var enlarged = false
    var affordable = false

    private var cornerRadius: CGFloat { enlarged ? 24 : 13 }
    private var bandColor: Color { card.isWildBonus ? .purple : (card.bonusColor?.tint ?? .gray) }
    private var bandHeight: CGFloat { enlarged ? 118 : 44 }

    var body: some View {
        VStack(spacing: 0) {
            // Colored header band — points, bonus and crowns grouped together so the
            // crown never straddles the color boundary.
            ZStack {
                bandColor.opacity(0.22)
                HStack(alignment: .top, spacing: 4) {
                    if card.prestige > 0 {
                        Text("\(card.prestige)")
                            .font(enlarged ? .largeTitle.bold() : .headline.bold())
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        bonusBadge
                        if card.crowns > 0 {
                            DuelCardCrowns(count: card.crowns, size: enlarged ? 18 : 10)
                                .fixedSize()
                        }
                    }
                }
                .padding(enlarged ? 14 : 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(height: bandHeight)

            // Body — ability and cost on the uncolored area.
            VStack(alignment: .leading, spacing: enlarged ? 10 : 3) {
                if let ability = card.ability {
                    if enlarged {
                        Label(ability.localizedKey, systemImage: ability.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.purple)
                    } else {
                        Image(systemName: ability.iconName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                }
                Spacer(minLength: 0)
                DuelCostRow(cost: card.cost, size: enlarged ? 28 : 15)
            }
            .padding(enlarged ? 16 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(width: enlarged ? nil : 62, height: enlarged ? 232 : 98)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if affordable {
                DuelShimmerBorder(cornerRadius: cornerRadius, lineWidth: enlarged ? 2.5 : 1.75)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("duel.card.accessibility \(card.tier) \(card.prestige) \(card.crowns)"))
    }

    private var bonusBadge: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: card.isWildBonus ? "sparkles" : (card.bonusColor?.iconName ?? "minus"))
                .font(.system(size: enlarged ? 18 : 9, weight: .semibold))
                .foregroundStyle(card.isWildBonus ? .white : (card.bonusColor?.foreground ?? .white))
                .padding(enlarged ? 10 : 5)
                .background(bandColor, in: Circle())
            if card.bonusAmount == 2 {
                Text("2")
                    .font(.system(size: enlarged ? 11 : 8, weight: .black))
                    .foregroundStyle(.white)
                    .padding(enlarged ? 3 : 2)
                    .background(.black.opacity(0.6), in: Circle())
                    .offset(x: enlarged ? 4 : 3, y: enlarged ? -4 : -3)
            }
        }
    }
}

struct DuelRoyalCardView: View {
    let royal: DuelRoyalCard
    var enlarged = false

    private var cornerRadius: CGFloat { enlarged ? 22 : 13 }
    private let royalColor = Color(red: 0.72, green: 0.53, blue: 0.20)

    var body: some View {
        if enlarged { enlargedBody } else { compactBody }
    }

    // Compact card: points top-left, skill top-right, and the claim threshold
    // (3 / 6 crowns) pinned bottom-left.
    private var compactBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text("\(royal.prestige)").font(.title3.bold())
                Spacer(minLength: 0)
                if let ability = royal.ability {
                    Image(systemName: ability.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple)
                }
            }
            Spacer(minLength: 0)
            HStack {
                crownThreshold
                Spacer(minLength: 0)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(royalColor.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(royalColor.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("duel.card.accessibility \(0) \(royal.prestige) \(0)"))
    }

    private var enlargedBody: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                Text("\(royal.prestige)").font(.largeTitle.bold())
                Spacer()
                Image(systemName: "crown.fill").font(.title2).foregroundStyle(royalColor)
            }
            if let ability = royal.ability {
                Label(ability.localizedKey, systemImage: ability.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            HStack(spacing: 6) {
                crownThreshold
                Text("duel.royal.hint").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
        .background(royalColor.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(royalColor.opacity(0.28), lineWidth: 1)
        }
    }

    private var crownThreshold: some View {
        HStack(spacing: 2) {
            Image(systemName: "crown.fill").font(.system(size: 9))
            Text("3/6").font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(royalColor)
    }
}

/// Crowns on a development card, shown as repeated crown icons (max 3): 👑👑👑.
struct DuelCardCrowns: View {
    let count: Int
    var size: CGFloat = 11

    private let crownColor = Color(red: 0.78, green: 0.58, blue: 0.17)

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< max(0, count), id: \.self) { _ in
                Image(systemName: "crown.fill").font(.system(size: size))
            }
        }
        .foregroundStyle(crownColor)
        .accessibilityHidden(true)
    }
}

/// Connects the centers of the board spaces in refill (spiral) order — center-out,
/// ending at the bottom-right corner. Drawn faintly behind the 5×5 gem grid.
struct DuelSpiralPath: Shape {
    let order: [Int]
    var columns = 5
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard columns > 0 else { return path }
        let cellWidth = (rect.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (rect.height - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        func center(_ index: Int) -> CGPoint {
            let row = index / columns, col = index % columns
            return CGPoint(
                x: CGFloat(col) * (cellWidth + spacing) + cellWidth / 2,
                y: CGFloat(row) * (cellHeight + spacing) + cellHeight / 2
            )
        }

        for (offset, index) in order.enumerated() {
            let point = center(index)
            if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// A compact 5×5 board used inside sheets to pick a specific board position
/// (a gold token to reserve, or a matching token to take) by tapping it in place —
/// far clearer than a list of "row,column" coordinates.
struct DuelMiniBoardPicker: View {
    let board: [DuelTokenColor?]
    let selectableIndices: [Int]
    @Binding var selection: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(board.indices, id: \.self) { index in
                if let color = board[index] {
                    let selectable = selectableIndices.contains(index)
                    Button {
                        if selectable { selection = index }
                    } label: {
                        DuelTokenChip(
                            color: color,
                            diameter: 34,
                            selected: selection == index,
                            dimmed: !selectable
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(!selectable)
                } else {
                    Circle()
                        .strokeBorder(.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: 34, height: 34)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
        }
        .background {
            DuelSpiralPath(order: DuelRules.spiralOrder, spacing: 5)
                .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2.5, 3.5]))
                .foregroundStyle(.primary.opacity(0.10))
                .allowsHitTesting(false)
        }
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
