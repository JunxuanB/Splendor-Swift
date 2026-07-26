import SwiftUI

enum SilkRoadPalette {
    static let accent = Color(red: 0.50, green: 0.30, blue: 0.68)
    static let gold = Color(red: 0.78, green: 0.56, blue: 0.15)
}

struct SilkRoadOpponentCarousel: View {
    @ObservedObject var state: SilkRoadGameState

    var body: some View {
        HStack(spacing: 5) {
            arrow("chevron.left", label: "上一位对手") {
                withAnimation(.snappy) { state.showPreviousOpponent() }
            }

            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: state.currentOpponent.kind == .bot ? "cpu" : "person.crop.circle.fill")
                        .foregroundStyle(.tint)
                    Text(state.currentOpponent.name).font(.headline)
                    Text("\(state.opponentIndex + 1)/\(state.opponents.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    stat(state.currentOpponent.prestige, label: "分")
                    stat(state.currentOpponent.developmentCardCount, label: "卡")
                    stat(state.currentOpponent.reservedCards, label: "预留")
                }

                HStack(spacing: 5) {
                    ForEach(GemColor.allCases) { gem in
                        ResourceStackView(
                            gem: gem,
                            permanent: state.currentOpponent.permanentBonuses[gem, default: 0],
                            tokens: state.currentOpponent.tokens[gem, default: 0],
                            compact: true
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
            .id(state.currentOpponent.id)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > 40 else { return }
                        withAnimation(.snappy) {
                            value.translation.width < 0
                                ? state.showNextOpponent()
                                : state.showPreviousOpponent()
                        }
                    }
            )

            arrow("chevron.right", label: "下一位对手") {
                withAnimation(.snappy) { state.showNextOpponent() }
            }
        }
        .sensoryFeedback(.selection, trigger: state.opponentIndex)
    }

    private func stat(_ value: Int, label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)").font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func arrow(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.caption.bold()).frame(width: 22, height: 64)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }
}

struct SilkRoadGemBank: View {
    @ObservedObject var state: SilkRoadGameState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GemColor.allCases) { gem in
                Button {
                    withAnimation(.bouncy) { state.toggleGem(gem) }
                } label: {
                    VStack(spacing: 2) {
                        GemTokenView(
                            gem: gem,
                            count: state.bank[gem, default: 0],
                            diameter: 37,
                            selectionCount: state.selectedGems[gem, default: 0],
                            disabled: gem == .gold
                        )
                        Text(gem.shortName).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(gem == .gold)
            }

            VStack(spacing: 3) {
                if state.hasGemSelection {
                    Button("拿取") { state.confirmGemSelection() }.buttonStyle(.borderedProminent)
                    Button("取消") { state.cancelGemSelection() }.buttonStyle(.bordered)
                } else {
                    Image(systemName: "hand.tap").foregroundStyle(.tertiary)
                    Text("选宝石").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .font(.caption2.bold())
            .controlSize(.mini)
            .frame(width: 52)
        }
    }
}

struct SilkRoadNobleStrip: View {
    let nobles: [NobleTile]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(nobles) { noble in
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(SilkRoadPalette.gold)
                    Text("\(noble.prestige)").font(.caption.bold())
                    HStack(spacing: 2) {
                        ForEach(requirements(noble), id: \.key) { gem, value in
                            NobleRequirementBadge(gem: gem, value: value, height: 17)
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(SilkRoadPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(noble.name)，\(noble.prestige) 分")
            }
        }
    }

    private func requirements(_ noble: NobleTile) -> [(key: GemColor, value: Int)] {
        GemColor.allCases.compactMap { gem in noble.requirements[gem].map { (gem, $0) } }
    }
}

struct SilkRoadMarket: View {
    @ObservedObject var state: SilkRoadGameState

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Label("基础市场 4", systemImage: "rectangle.stack")
                Spacer()
                Label("丝绸之路 +1", systemImage: "sparkles")
                    .foregroundStyle(SilkRoadPalette.accent)
            }
            .font(.caption.bold())
            .padding(.horizontal, 27)

            ForEach(Array(state.market.reversed()), id: \.level) { row in
                HStack(spacing: 5) {
                    SilkRoadDeckPile(level: row.level, remaining: state.baseDeckCounts[row.level, default: 0])

                    ForEach(row.baseCards) { card in cardButton(card) }

                    Rectangle()
                        .fill(SilkRoadPalette.accent.opacity(0.28))
                        .frame(width: 1, height: 68)

                    cardButton(row.silkRoadCard)
                }
            }
        }
    }

    private func cardButton(_ card: SilkRoadCard) -> some View {
        Button { state.open(card) } label: {
            SilkRoadCardView(card: card, isPurchasable: state.canPurchase(card))
        }
        .buttonStyle(SilkRoadCardPressStyle())
        .frame(maxWidth: .infinity)
    }
}

struct SilkRoadCardView: View {
    let card: SilkRoadCard
    var isPurchasable = false
    var enlarged = false

    private var radius: CGFloat { enlarged ? 24 : 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: enlarged ? 10 : 2) {
            HStack(alignment: .top, spacing: 2) {
                if card.prestige > 0 {
                    Text("\(card.prestige)")
                        .font(enlarged ? .largeTitle.bold() : .caption.bold())
                }
                Spacer(minLength: 0)
                bonusBadge
            }
            .padding(enlarged ? 14 : 5)
            .frame(maxWidth: .infinity, minHeight: enlarged ? 105 : 29, alignment: .top)
            .background((card.bonus?.tint ?? SilkRoadPalette.accent).opacity(0.19))

            if let effect = card.effect {
                HStack(spacing: 5) {
                    Image(systemName: effect.iconName)
                    if enlarged { Text(effect.title) }
                }
                .font(enlarged ? .subheadline.bold() : .system(size: 9, weight: .semibold))
                .foregroundStyle(SilkRoadPalette.accent)
                .padding(.horizontal, enlarged ? 12 : 5)
            }

            Spacer(minLength: 0)
            HStack(spacing: enlarged ? 5 : 2) {
                ForEach(sortedCosts.prefix(enlarged ? 5 : 3), id: \.key) { gem, value in
                    CostBadge(gem: gem, value: value, size: enlarged ? 28 : 13)
                }
            }
            .padding(.horizontal, enlarged ? 12 : 5)
            .padding(.bottom, enlarged ? 12 : 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: enlarged ? 238 : 74)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isPurchasable ? 2 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var bonusBadge: some View {
        if let bonus = card.bonus {
            Image(systemName: bonus.iconName)
                .font(enlarged ? .title2 : .system(size: 9, weight: .bold))
                .foregroundStyle(bonus.foreground)
                .padding(enlarged ? 8 : 3)
                .background(bonus.tint, in: Circle())
        } else {
            Image(systemName: "sparkles")
                .font(enlarged ? .title2 : .system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(enlarged ? 8 : 3)
                .background(SilkRoadPalette.accent, in: Circle())
        }
    }

    private var sortedCosts: [(key: GemColor, value: Int)] {
        GemColor.allCases.compactMap { gem in card.costs[gem].map { (gem, $0) } }
    }

    private var borderColor: Color {
        if isPurchasable { return .green }
        return card.source == .silkRoad ? SilkRoadPalette.accent.opacity(0.75) : .primary.opacity(0.10)
    }

    private var accessibilityText: String {
        var text = "\(card.level) 级\(card.source.displayName)，\(card.prestige) 分"
        if let effect = card.effect { text += "，\(effect.title)" }
        return text
    }
}

private struct SilkRoadDeckPile: View {
    let level: Int
    let remaining: Int

    var body: some View {
        VStack(spacing: 1) {
            Text(levelText).font(.system(size: 8, weight: .bold))
            Image(systemName: "rectangle.stack.fill").font(.system(size: 11))
            Text("\(remaining)").font(.system(size: 8, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .frame(width: 23, height: 74)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.10)) }
    }

    private var levelText: String {
        switch level {
        case 1: "Ⅰ"
        case 2: "Ⅱ"
        default: "Ⅲ"
        }
    }
}

struct SilkRoadCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

