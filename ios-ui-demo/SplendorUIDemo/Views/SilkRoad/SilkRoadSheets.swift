import SwiftUI

struct SilkRoadDetailSheet: View {
    let sheet: SilkRoadSheet
    @ObservedObject var state: SilkRoadGameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch sheet {
                case let .card(card): cardContent(card)
                case .reserved: reservedContent
                case .rules: rulesContent
                }
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func cardContent(_ card: SilkRoadCard) -> some View {
        VStack(spacing: 16) {
            SilkRoadCardView(card: card, isPurchasable: state.canPurchase(card), enlarged: true)
                .frame(width: 190)

            Label(
                card.source.displayName,
                systemImage: card.source == .silkRoad ? "sparkles" : "rectangle"
            )
            .font(.subheadline.bold())
            .foregroundStyle(card.source == .silkRoad ? SilkRoadPalette.accent : .primary)

            if let effect = card.effect {
                VStack(alignment: .leading, spacing: 7) {
                    Label(effect.title, systemImage: effect.iconName).font(.headline)
                    Text(effect.ruleText).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SilkRoadPalette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 12) {
                Button("预留") { state.reserve(card) }
                    .buttonStyle(.bordered)
                Button("购买") { state.buy(card) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.canPurchase(card))
            }
            .controlSize(.large)
        }
        .navigationTitle("发展卡详情")
    }

    private var reservedContent: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(state.reservedCards) { card in
                    VStack(spacing: 8) {
                        SilkRoadCardView(card: card, isPurchasable: state.canPurchase(card))
                        Button("购买") { state.buy(card) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!state.canPurchase(card))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("最多可以预留 3 张发展卡")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .navigationTitle("预留的发展卡")
    }

    private var rulesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("最简丝绸之路版", systemImage: "map.fill")
                .font(.title3.bold())
                .foregroundStyle(SilkRoadPalette.accent)
            Text("沿用基础版的宝石、贵族、购买与预留规则。每个等级在原来的 4 张基础发展卡旁额外显示 1 张丝绸之路牌。")
                .font(.body)
            Text("紫色边框和牌效图标用于区分额外卡牌；本 Demo 不包含其他扩展模块。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle("规则说明")
    }
}
