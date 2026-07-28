import LuminoreCore
import SwiftUI

struct OpponentCarousel: View {
    let opponents: [PublicPlayerSnapshot]
    let currentPlayerID: UUID
    @Binding var opponentIndex: Int
    let onOpenReservedCards: (PublicPlayerSnapshot) -> Void

    var body: some View {
        if let opponent = currentOpponent {
            HStack(spacing: 5) {
                carouselButton(systemName: "chevron.left", label: "game.opponent.previous") {
                    withAnimation(.snappy) { showPreviousOpponent() }
                }

                opponentCard(opponent)
                    .id(opponent.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                guard abs(value.translation.width) > 40 else { return }
                                withAnimation(.snappy) {
                                    value.translation.width < 0
                                        ? showNextOpponent()
                                        : showPreviousOpponent()
                                }
                            }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenReservedCards(opponent) }
                    .accessibilityHint(Text("game.opponent.reserved.hint"))

                carouselButton(systemName: "chevron.right", label: "game.opponent.next") {
                    withAnimation(.snappy) { showNextOpponent() }
                }
            }
            .sensoryFeedback(.selection, trigger: opponentIndex)
        }
    }

    private var currentOpponent: PublicPlayerSnapshot? {
        guard !opponents.isEmpty else { return nil }
        return opponents[min(opponentIndex, opponents.count - 1)]
    }

    private func opponentCard(_ opponent: PublicPlayerSnapshot) -> some View {
        VStack(spacing: 5) {
            HStack {
                Label {
                    Text(opponent.nickname).font(.headline)
                } icon: {
                    Image(systemName: opponent.kind == .bot ? "cpu" : "person.crop.circle.fill")
                        .foregroundStyle(.tint)
                }

                if opponent.kind == .human {
                    MedalCountLabel(count: opponent.medalCount, compact: true)
                }

                if !opponent.isConnected {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(Text("game.player.disconnected"))
                }

                Text("\(opponentIndex + 1)/\(opponents.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                stat("\(opponent.prestige)", label: "game.stat.score")
                    .gameFlightAnchor(.scoreLabel(opponent.id))
                Divider().frame(height: 22)
                stat("\(opponent.developmentCardCount)", label: "game.stat.cards")
                Divider().frame(height: 22)
                stat("\(opponent.reservedCardCount)/3", label: "game.stat.reserved")
                    .gameFlightAnchor(.reservedArea(opponent.id))
            }

            HStack(spacing: 5) {
                ForEach(GemColor.allCases) { gem in
                    ResourceStackView(
                        gem: gem,
                        permanent: opponent.bonuses[gem, default: 0],
                        tokens: opponent.tokens[gem, default: 0],
                        compact: true
                    )
                    .gameFlightAnchor(.playerStack(opponent.id, gem))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            if opponent.id == currentPlayerID {
                ShimmerBorder(cornerRadius: 18, lineWidth: 2.5)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
        }
    }

    private func stat(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func carouselButton(
        systemName: String,
        label: LocalizedStringKey,
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
        .accessibilityLabel(Text(label))
    }

    private func showNextOpponent() {
        guard !opponents.isEmpty else { return }
        opponentIndex = (opponentIndex + 1) % opponents.count
    }

    private func showPreviousOpponent() {
        guard !opponents.isEmpty else { return }
        opponentIndex = (opponentIndex - 1 + opponents.count) % opponents.count
    }
}

struct GemBankSection: View {
    let bank: [GemColor: Int]
    let isLocalTurn: Bool
    var selectableGems: Set<GemColor>? = nil
    var canTakeSelection = true
    var canPass = true
    @Binding var selectedGems: [GemColor: Int]
    let onToggle: (GemColor) -> Void
    let onTake: () -> Void
    let onPass: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                ForEach(GemColor.allCases) { gem in
                    Button {
                        withAnimation(.bouncy) { onToggle(gem) }
                    } label: {
                        VStack(spacing: 4) {
                            GemTokenView(
                                gem: gem,
                                count: bank[gem, default: 0],
                                diameter: 40,
                                selectionCount: selectedGems[gem, default: 0],
                                disabled: gem == .gold || !isLocalTurn
                            )
                            .gameFlightAnchor(.bankGem(gem))
                            Text(gem.shortLocalizedKey)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        !isLocalTurn
                            || gem == .gold
                            || bank[gem, default: 0] == 0
                            || selectableGems.map { !$0.contains(gem) } == true
                    )
                }
            }

            VStack(spacing: 4) {
                if !selectedGems.isEmpty {
                    Button("game.take", action: onTake)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canTakeSelection)
                        .gameFlightAnchor(.takeControl)
                    Button("common.cancel") { selectedGems = [:] }
                        .buttonStyle(.bordered)
                } else {
                    Image(systemName: "hand.tap")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("game.take.hint")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Button("game.pass", role: .destructive, action: onPass)
                        .font(.system(size: 9, weight: .semibold))
                        .disabled(!isLocalTurn || !canPass)
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
    var selectableNobleIDs: Set<String>? = nil
    let onSelect: (NobleTile) -> Void

    var body: some View {
        if nobles.count <= 5 {
            HStack(spacing: 7) {
                ForEach(nobles) { noble in
                    nobleButton(noble)
                        .frame(maxWidth: .infinity, maxHeight: 72)
                }
            }
            .frame(height: 72)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(nobles) { noble in
                        nobleButton(noble).frame(width: 66)
                    }
                }
            }
            .frame(height: 66)
        }
    }

    private func nobleButton(_ noble: NobleTile) -> some View {
        Button { onSelect(noble) } label: { NobleTileView(noble: noble) }
            .buttonStyle(.plain)
            .disabled(selectableNobleIDs.map { !$0.contains(noble.id) } == true)
            .gameFlightAnchor(.nobleTile(noble.id))
    }
}

struct MarketSection: View {
    let snapshot: ClientGameSnapshot
    let player: PublicPlayerSnapshot
    let isLocalTurn: Bool
    var selectableCardIDs: Set<String>? = nil
    var canReserveDeck = true
    let onSelectCard: (DevelopmentCard, CardSource) -> Void
    let onReserveDeck: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 4)

    var body: some View {
        VStack(spacing: 8) {
            ForEach([3, 2, 1], id: \.self) { tier in
                HStack(spacing: 6) {
                    Button { onReserveDeck(tier) } label: {
                        DeckPileView(level: tier, remaining: snapshot.deckCounts[tier, default: 0])
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        !isLocalTurn
                            || !canReserveDeck
                            || snapshot.deckCounts[tier, default: 0] == 0
                            || snapshot.localReservedCards.count >= 3
                            || snapshot.bank[.gold, default: 0] == 0
                    )

                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(snapshot.market[tier, default: []]) { card in
                            Button {
                                onSelectCard(card, .market(cardID: card.id))
                            } label: {
                                DevelopmentCardView(
                                    card: card,
                                    isPurchasable: canPurchase(card, player: player),
                                    showsPurchaseHighlight: snapshot.configuration.affordableCardHighlightEnabled
                                )
                                .gameFlightAnchor(.marketCard(card.id))
                            }
                            .buttonStyle(CardPressStyle())
                            .disabled(selectableCardIDs.map { !$0.contains(card.id) } == true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct DeckPileView: View {
    let level: Int
    let remaining: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(levelText).font(.caption2.bold())
            Image(systemName: "rectangle.stack.fill").font(.caption)
            Text("\(remaining)").font(.caption2.bold().monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .frame(width: 31, height: 78)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("game.deck.accessibility \(level) \(remaining)"))
        .accessibilityHint(Text("game.deck.hint"))
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

func canPurchase(_ card: DevelopmentCard, player: PublicPlayerSnapshot) -> Bool {
    var availableGold = player.tokens[.gold, default: 0]
    for gem in GemColor.purchasableColors {
        let required = card.cost[gem, default: 0]
        let available = player.bonuses[gem, default: 0] + player.tokens[gem, default: 0]
        availableGold -= max(0, required - available)
        if availableGold < 0 { return false }
    }
    return true
}
