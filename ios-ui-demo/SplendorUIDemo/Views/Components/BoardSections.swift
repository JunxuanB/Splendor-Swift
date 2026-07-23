import SwiftUI

struct OpponentCarousel: View {
    @ObservedObject var state: DemoGameState

    var body: some View {
        HStack(spacing: 5) {
            carouselButton(systemName: "chevron.left", label: "上一位对手") {
                withAnimation(.snappy) { state.showPreviousOpponent() }
            }

            opponentCard(state.currentOpponent)
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
                .contentShape(Rectangle())
                .onTapGesture {
                    state.openReservedCards(for: state.currentOpponent)
                }
                .accessibilityHint("轻点查看对手预留的发展卡")

            carouselButton(systemName: "chevron.right", label: "下一位对手") {
                withAnimation(.snappy) { state.showNextOpponent() }
            }
        }
        .sensoryFeedback(.selection, trigger: state.opponentIndex)
    }

    private func opponentCard(_ opponent: PlayerSnapshot) -> some View {
        VStack(spacing: 5) {
            HStack {
                Label {
                    Text(opponent.name)
                        .font(.headline)
                } icon: {
                    Image(systemName: opponent.kind == .bot ? "cpu" : "person.crop.circle.fill")
                        .foregroundStyle(.tint)
                }

                Text("\(state.opponentIndex + 1)/\(state.opponents.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                stat("\(opponent.prestige)", label: "分")
                Divider().frame(height: 22)
                stat("\(opponent.developmentCardCount)", label: "卡")
                Divider().frame(height: 22)
                stat("\(opponent.reservedCards)/3", label: "预留")
            }

            HStack(spacing: 5) {
                ForEach(GemColor.allCases) { gem in
                    ResourceStackView(
                        gem: gem,
                        permanent: opponent.permanentBonuses[gem, default: 0],
                        tokens: opponent.tokens[gem, default: 0],
                        compact: true
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func carouselButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.bold())
                .frame(width: 23, height: 68)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }
}

struct GemBankSection: View {
    @ObservedObject var state: DemoGameState

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                ForEach(GemColor.allCases) { gem in
                    Button {
                        withAnimation(.bouncy) { state.toggleGem(gem) }
                    } label: {
                        VStack(spacing: 4) {
                            GemTokenView(
                                gem: gem,
                                count: state.bank[gem, default: 0],
                                diameter: 40,
                                selectionCount: state.selectedGems[gem, default: 0],
                                disabled: gem == .gold
                            )
                            Text(gem.shortName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(gem == .gold || state.bank[gem, default: 0] == 0)
                }
            }

            VStack(spacing: 4) {
                if state.hasGemSelection {
                    Button("拿取") { state.confirmGemSelection() }
                        .buttonStyle(.borderedProminent)
                    Button("取消") { state.cancelGemSelection() }
                        .buttonStyle(.bordered)
                } else {
                    Image(systemName: "hand.tap")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("可点两次")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption2.bold())
            .controlSize(.mini)
            .frame(width: 58)
        }
    }
}

struct NobleSection: View {
    let nobles: [NobleTile]
    let onSelect: (NobleTile) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(nobles.prefix(5)) { noble in
                Button {
                    onSelect(noble)
                } label: {
                    NobleTileView(noble: noble)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct NobleTileView: View {
    let noble: NobleTile
    var enlarged = false

    var body: some View {
        VStack(spacing: enlarged ? 12 : 5) {
            HStack {
                Image(systemName: "crown.fill")
                    .font(enlarged ? .title2 : .caption)
                    .foregroundStyle(.yellow)
                Spacer()
                Text("\(noble.prestige)")
                    .font(enlarged ? .title.bold() : .subheadline.bold())
            }

            HStack(spacing: enlarged ? 8 : 1) {
                ForEach(requirements, id: \.key) { gem, value in
                    NobleRequirementBadge(gem: gem, value: value, height: enlarged ? 30 : 14)
                }
            }
            .padding(.top, enlarged ? 8 : 1)

            Spacer(minLength: 0)
        }
        .padding(enlarged ? 18 : 5)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            LinearGradient(
                colors: [Color.secondary.opacity(0.10), Color.purple.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: enlarged ? 22 : 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: enlarged ? 22 : 12, style: .continuous)
                .strokeBorder(.purple.opacity(0.25))
        }
        .shadow(color: .black.opacity(enlarged ? 0.08 : 0.035), radius: enlarged ? 8 : 2, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(noble.name)，\(noble.prestige) 分")
        .accessibilityHint("轻点查看详情")
    }

    private var requirements: [(key: GemColor, value: Int)] {
        GemColor.allCases.compactMap { gem in
            guard let value = noble.requirements[gem] else { return nil }
            return (gem, value)
        }
    }
}

struct MarketSection: View {
    @ObservedObject var state: DemoGameState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 4)

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(state.market.enumerated()).reversed(), id: \.offset) { levelIndex, cards in
                HStack(spacing: 6) {
                    DeckPileView(
                        level: levelIndex + 1,
                        remaining: state.deckRemaining[levelIndex + 1, default: 0]
                    )

                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(cards) { card in
                            Button {
                                state.open(card)
                            } label: {
                                DevelopmentCardView(card: card, isPurchasable: state.canPurchase(card))
                            }
                            .buttonStyle(CardPressStyle())
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct DevelopmentCardView: View {
    let card: DevelopmentCard
    var enlarged = false
    var isPurchasable = false

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

            CardCostGrid(costs: card.costs, badgeSize: enlarged ? 30 : 18)
        }
        .padding(enlarged ? 18 : 6)
        .frame(
            maxWidth: .infinity,
            minHeight: enlarged ? 220 : 76,
            maxHeight: enlarged ? 220 : 80,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors: [card.bonus.tint.opacity(0.48), Color.secondary.opacity(0.10)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            in: RoundedRectangle(cornerRadius: enlarged ? 22 : 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: enlarged ? 22 : 12, style: .continuous)
                .strokeBorder(card.bonus.tint.opacity(0.42))
        }
        .overlay {
            if isPurchasable {
                RoundedRectangle(cornerRadius: enlarged ? 22 : 12, style: .continuous)
                    .strokeBorder(.green.opacity(0.72), lineWidth: enlarged ? 2 : 1.5)
            }
        }
        .shadow(color: .black.opacity(enlarged ? 0.08 : 0.04), radius: enlarged ? 8 : 2, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("等级 \(card.level) 发展卡，\(card.prestige) 分，奖励\(card.bonus.displayName)")
        .accessibilityValue(isPurchasable ? "当前可以购买" : "当前不可购买")
        .accessibilityHint("轻点选择购买或预留")
    }
}

private struct DeckPileView: View {
    let level: Int
    let remaining: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(levelText)
                .font(.caption2.bold())
            Image(systemName: "rectangle.stack.fill")
                .font(.caption)
            Text("\(remaining)")
                .font(.caption2.bold().monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .frame(width: 31, height: 78)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.quaternary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("等级 \(level) 牌库，剩余 \(remaining) 张")
    }

    private var levelText: String {
        switch level {
        case 1: "Ⅰ"
        case 2: "Ⅱ"
        default: "Ⅲ"
        }
    }
}

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
