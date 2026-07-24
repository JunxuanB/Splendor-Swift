import SwiftUI

/// Detail sheet for a tapped development card, royal card, or the reserved list.
struct DuelDetailSheet: View {
    let sheet: DuelSheet
    @ObservedObject var state: DuelGameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch sheet {
                case let .card(card):
                    cardContent(card)
                case let .royal(royal):
                    royalContent(royal)
                case let .reserved(title, cards, allowsPurchase):
                    reservedContent(title: title, cards: cards, allowsPurchase: allowsPurchase)
                }
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func cardContent(_ card: DuelCard) -> some View {
        VStack(spacing: 18) {
            DuelCardView(card: card, enlarged: true, isPurchasable: state.canPurchase(card))
                .frame(width: 200)

            HStack(spacing: 7) {
                Image(systemName: card.isWildBonus ? "sparkles" : (card.bonus?.iconName ?? "questionmark"))
                Text("永久获得 1 枚\(card.bonusDescription)奖励")
                if card.crowns > 0 {
                    DuelCardCrowns(count: card.crowns, size: 13)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.purple.opacity(0.12), in: Capsule())

            if let ability = card.ability {
                Label(ability.displayName, systemImage: ability.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
            }

            HStack(spacing: 12) {
                Button("预留") { state.reserve(card) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(state.reservedCards.count >= DuelRules.maxReserved)

                Button("购买") { state.buy(card) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!state.canPurchase(card))
            }
            .controlSize(.large)
        }
        .navigationTitle("选择操作")
        .duelInlineNavigationBar()
    }

    private func royalContent(_ royal: DuelRoyal) -> some View {
        VStack(spacing: 18) {
            DuelRoyalView(royal: royal, enlarged: true)
                .frame(width: 220)

            if state.pendingRoyalPicks > 0 {
                Button {
                    state.claimRoyal(royal)
                    dismiss()
                } label: {
                    Label("选择这张皇室卡", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("累计 3 枚王冠可选择 1 张皇室卡，累计 6 枚可再选 1 张（需手动选择）。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .navigationTitle("皇室卡")
        .duelInlineNavigationBar()
    }

    private func reservedContent(title: String, cards: [DuelCard], allowsPurchase: Bool) -> some View {
        VStack(spacing: 18) {
            if cards.isEmpty {
                ContentUnavailableView(
                    "暂无预留牌",
                    systemImage: "rectangle.stack",
                    description: Text("预留的发展卡会显示在这里。")
                )
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(cards) { card in
                        VStack(spacing: 8) {
                            DuelCardView(card: card, isPurchasable: allowsPurchase && state.canPurchase(card))
                            if allowsPurchase {
                                Button {
                                    state.buy(card)
                                    dismiss()
                                } label: {
                                    Label("购买", systemImage: "cart.fill")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!state.canPurchase(card))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Text(allowsPurchase ? "最多可以预留 3 张发展卡" : "对手预留的发展卡不可购买")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle(title)
        .duelInlineNavigationBar()
    }
}

private extension View {
    @ViewBuilder
    func duelInlineNavigationBar() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}
