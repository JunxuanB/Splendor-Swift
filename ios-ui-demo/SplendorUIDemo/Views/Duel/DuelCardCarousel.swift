import SwiftUI

/// 发展卡版图 — the full development-card page. Shows the three tiers (each with a
/// deck pile to reserve from) plus the royal cards. Every card is the same size
/// regardless of level.
struct DuelCardBoard: View {
    @ObservedObject var state: DuelGameState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach([3, 2, 1], id: \.self) { tier in
                    tierRow(tier)
                }
                royalRow
            }
            .padding(.vertical, 2)
        }
    }

    private func tierRow(_ tier: Int) -> some View {
        HStack(spacing: 4) {
            DuelDeckPile(level: tier, remaining: state.deckCounts[tier, default: 0]) {
                state.reserveFromDeck(level: tier)
            }
            .disabled(state.deckCounts[tier, default: 0] == 0 || state.reservedCards.count >= DuelRules.maxReserved)

            ForEach(state.market[tier, default: []]) { card in
                Button {
                    state.open(card)
                } label: {
                    DuelCardView(card: card, isPurchasable: state.canPurchase(card))
                        .duelFlightAnchor(.marketCard(card.id))
                }
                .buttonStyle(DuelCardPressStyle())
            }

            Spacer(minLength: 0)
        }
    }

    private var royalRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill").font(.caption2)
                    .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 0.20))
                Text("皇室卡").font(.caption2.bold())
                    .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 0.20))
                Spacer()
                if state.pendingRoyalPicks > 0 {
                    Text("可选择 \(state.pendingRoyalPicks) 张")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("累计 3/6 个皇冠可选择一张")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            if state.royals.isEmpty {
                Text("皇室卡已全部领取")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    ForEach(state.royals) { royal in
                        Button {
                            state.open(royal)
                        } label: {
                            DuelRoyalView(royal: royal, isPickable: state.pendingRoyalPicks > 0)
                        }
                        .buttonStyle(DuelCardPressStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

enum DuelCardMetrics {
    static let width: CGFloat = 62
    static let height: CGFloat = 98
    static let deckWidth: CGFloat = 28
    static let royalHeight: CGFloat = 78
}

struct DuelCardView: View {
    let card: DuelCard
    var enlarged = false
    var isPurchasable = false

    private var cornerRadius: CGFloat { enlarged ? 24 : 13 }
    private var bandColor: Color { card.isWildBonus ? Color.purple : (card.bonus?.tint ?? .gray) }
    private var bandHeight: CGFloat { enlarged ? 118 : 44 }

    var body: some View {
        VStack(spacing: 0) {
            // Colored header band — contains points, bonus and crowns together so
            // the crown never straddles the color boundary.
            ZStack {
                bandColor.opacity(0.22)
                HStack(alignment: .top, spacing: 4) {
                    if card.points > 0 {
                        Text("\(card.points)")
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

            // Body — cost and ability on the uncolored area.
            VStack(alignment: .leading, spacing: enlarged ? 10 : 3) {
                if let ability = card.ability {
                    abilityLabel(ability, enlarged: enlarged)
                }
                Spacer(minLength: 0)
                DuelCostRow(cost: card.cost, badgeSize: enlarged ? 28 : 15)
            }
            .padding(enlarged ? 16 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(
            width: enlarged ? nil : DuelCardMetrics.width,
            height: enlarged ? 232 : DuelCardMetrics.height
        )
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if isPurchasable {
                DuelShimmerBorder(cornerRadius: cornerRadius, lineWidth: enlarged ? 2.5 : 1.75)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("等级 \(card.level) 发展卡，\(card.points) 分，\(card.crowns) 王冠，奖励\(card.bonusDescription)")
        .accessibilityValue(isPurchasable ? "当前可购买" : "当前不可购买")
    }

    @ViewBuilder
    private func abilityLabel(_ ability: DuelAbility, enlarged: Bool) -> some View {
        if enlarged {
            Label(ability.displayName, systemImage: ability.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.purple)
        } else {
            Image(systemName: ability.iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.purple)
        }
    }

    private var bonusBadge: some View {
        Image(systemName: card.isWildBonus ? "sparkles" : (card.bonus?.iconName ?? "questionmark"))
            .font(enlarged ? .title : .caption)
            .foregroundStyle(card.isWildBonus ? Color.white : (card.bonus?.foreground ?? .white))
            .padding(enlarged ? 10 : 4)
            .background(bandColor, in: Circle())
    }
}

struct DuelRoyalView: View {
    let royal: DuelRoyal
    var enlarged = false
    var isPickable = false

    private var cornerRadius: CGFloat { enlarged ? 22 : 13 }
    private let royalColor = Color(red: 0.72, green: 0.53, blue: 0.20)

    var body: some View {
        if enlarged {
            enlargedBody
        } else {
            compactBody
        }
    }

    // Compact card: points top-left, skill top-right, and the two claim
    // thresholds (3 / 6 crowns) bottom-left and bottom-right.
    private var compactBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text("\(royal.points)")
                    .font(.title3.bold())
                Spacer(minLength: 0)
                skillCorner
            }
            Spacer(minLength: 0)
            HStack {
                crownThreshold
                Spacer(minLength: 0)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .frame(height: DuelCardMetrics.royalHeight)
        .background(royalColor.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if isPickable {
                DuelShimmerBorder(cornerRadius: cornerRadius, lineWidth: 2)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(royalColor.opacity(0.28), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("皇室卡，\(royal.points) 分\(royal.ability != nil ? "，含技能" : "")")
    }

    @ViewBuilder
    private var skillCorner: some View {
        if let ability = royal.ability {
            Image(systemName: ability.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.purple)
        }
    }

    /// The two claim thresholds shown compactly as "👑 3/6".
    private var crownThreshold: some View {
        HStack(spacing: 2) {
            Image(systemName: "crown.fill").font(.system(size: 9))
            Text("3/6").font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(royalColor)
    }

    private var enlargedBody: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(royal.points)").font(.largeTitle.bold())
                    Text("分").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "crown.fill").font(.title2).foregroundStyle(royalColor)
            }

            Text(royal.name).font(.headline)

            if let ability = royal.ability {
                Label(ability.displayName, systemImage: ability.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
            } else {
                Text("3 分 · 无技能限时").font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                crownThreshold
                Text("王冠可选择").font(.caption).foregroundStyle(.secondary)
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
}

struct DuelDeckPile: View {
    let level: Int
    let remaining: Int
    let onReserve: () -> Void

    var body: some View {
        Button(action: onReserve) {
            VStack(spacing: 2) {
                Text(levelText).font(.caption.bold())
                Image(systemName: "rectangle.stack.fill").font(.callout)
                Text("\(remaining)").font(.caption2.bold().monospacedDigit())
                Text("预留").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .frame(width: DuelCardMetrics.deckWidth, height: DuelCardMetrics.height)
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("等级 \(level) 牌库，剩余 \(remaining) 张")
        .accessibilityHint("轻点从牌库顶预留一张")
    }

    private var levelText: String {
        switch level {
        case 1: "Ⅰ"
        case 2: "Ⅱ"
        default: "Ⅲ"
        }
    }
}

struct DuelCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
