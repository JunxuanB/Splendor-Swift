import SwiftUI

struct GameBoardView: View {
    @StateObject private var state = DemoGameState()
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingExitConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            CustomNavBar(title: "对局") { isShowingExitConfirmation = true }

            VictoryProgressHeader(current: state.playerPrestige, target: state.targetPrestige)

            Divider()

            GeometryReader { proxy in
                let roomy = proxy.size.height >= 430

                VStack(spacing: roomy ? 10 : 6) {
                    OpponentCarousel(state: state)
                    GemBankSection(state: state)
                        .padding(.vertical, roomy ? 2 : 0)
                    NobleSection(nobles: state.nobles, onSelect: state.open)
                        .padding(.vertical, roomy ? 2 : 0)
                    MarketSection(state: state)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, roomy ? 9 : 5)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground))

            PlayerInventoryBar(state: state)
        }
        .demoHideNavigationBar()
        .alert("退出演示对局？", isPresented: $isShowingExitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { dismiss() }
        } message: {
            Text("退出后，本局的演示数据会被重置。")
        }
        .sheet(item: $state.activeSheet) { sheet in
            DetailSheet(sheet: sheet, state: state)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let message = state.feedbackMessage {
                FeedbackToast(message: message)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.snappy, value: state.feedbackMessage)
        .task(id: state.feedbackMessage) {
            guard let message = state.feedbackMessage else { return }
            try? await Task.sleep(for: .seconds(2))
            state.clearFeedback(ifMatching: message)
        }
    }
}

private struct VictoryProgressHeader: View {
    let current: Int
    let target: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.subheadline)
                .foregroundStyle(.blue)

            ProgressView(value: Double(current), total: Double(target))
                .tint(.blue)

            Text(String(format: "%02d / %02d", current, target))
                .font(.subheadline.bold().monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("胜利目标，当前 \(current) 分，共需 \(target) 分")
    }
}

private struct PlayerInventoryBar: View {
    @ObservedObject var state: DemoGameState

    var body: some View {
        HStack(spacing: 8) {
            Button {
                state.openReservedCards()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(state.playerPrestige)")
                            .font(.title.bold().monospacedDigit())
                        Text("总分")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 2) {
                            Text("\(state.playerReservedCards) / 3")
                                .font(.caption.bold().monospacedDigit())
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                        }
                        Text("预留")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 54, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("总分 \(state.playerPrestige)，预留牌 \(state.playerReservedCards) 张")
            .accessibilityHint("轻点查看预留的发展卡")

            Divider()
                .frame(height: 62)

            HStack(spacing: 5) {
                ForEach(GemColor.allCases) { gem in
                    ResourceStackView(
                        gem: gem,
                        permanent: state.playerBonuses[gem, default: 0],
                        tokens: state.playerTokens[gem, default: 0]
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }
}

private struct DetailSheet: View {
    let sheet: DemoSheet
    @ObservedObject var state: DemoGameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch sheet {
                case let .developmentCard(card):
                    cardContent(card)
                case let .noble(noble):
                    nobleContent(noble)
                case let .reservedCards(title, cards, allowsPurchase):
                    reservedCardsContent(title: title, cards: cards, allowsPurchase: allowsPurchase)
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

    private func cardContent(_ card: DevelopmentCard) -> some View {
        VStack(spacing: 18) {
            DevelopmentCardView(
                card: card,
                enlarged: true,
                isPurchasable: state.canPurchase(card)
            )
            .frame(width: 190)

            HStack(spacing: 7) {
                Image(systemName: card.bonus.iconName)
                    .foregroundStyle(card.bonus.tint)
                Text("永久获得 1 枚\(card.bonus.displayName)奖励")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(card.bonus.tint.opacity(0.12), in: Capsule())

            HStack(spacing: 12) {
                Button("预留") {
                    state.performCardAction("已预留该发展卡（演示）")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("购买") {
                    state.performCardAction("已购买该发展卡（演示）")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .navigationTitle("选择操作")
        .demoInlineNavigationBar()
    }

    private func nobleContent(_ noble: NobleTile) -> some View {
        HStack(spacing: 22) {
            NobleTileView(noble: noble, enlarged: true)
                .frame(width: 180)

            VStack(alignment: .leading, spacing: 10) {
                Text(noble.name)
                    .font(.title3.bold())
                Text("价值 \(noble.prestige) 分")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Text("满足卡面所示的永久宝石数量后，贵族会自动来访。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("贵族详情")
        .demoInlineNavigationBar()
    }

    private func reservedCardsContent(
        title: String,
        cards: [DevelopmentCard],
        allowsPurchase: Bool
    ) -> some View {
        VStack(spacing: 18) {
            if cards.isEmpty {
                ContentUnavailableView(
                    "暂无预留牌",
                    systemImage: "rectangle.stack",
                    description: Text("预留的发展卡会显示在这里。")
                )
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    alignment: .center,
                    spacing: 12
                ) {
                    ForEach(cards) { card in
                        VStack(spacing: 8) {
                            DevelopmentCardView(
                                card: card,
                                isPurchasable: allowsPurchase && state.canPurchase(card)
                            )

                            if allowsPurchase {
                                Button {
                                    state.performCardAction("已购买预留的发展卡（演示）")
                                } label: {
                                    Label("购买", systemImage: "cart.fill")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Text(allowsPurchase ? "最多可以预留 3 张发展卡" : "对手预留的发展卡不可购买")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle(title)
        .demoInlineNavigationBar()
    }
}

private struct CustomNavBar: View {
    let title: String
    var onExit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TurnCountdownView()
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(title)
                .font(.headline)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .center)

            Button("退出", role: .destructive, action: onExit)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct TurnCountdownView: View {
    var duration = 30
    @State private var remaining = 30

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isUrgent: Bool { remaining <= 5 }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.footnote.weight(.semibold))
            Text("\(remaining)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
        }
        .foregroundStyle(isUrgent ? Color.red : .primary)
        .padding(.horizontal, isUrgent ? 8 : 0)
        .padding(.vertical, 3)
        .background(
            isUrgent ? Color.red.opacity(0.14) : Color.clear,
            in: Capsule()
        )
        .animation(.snappy, value: isUrgent)
        .onReceive(timer) { _ in
            withAnimation(.snappy) {
                remaining = remaining > 1 ? remaining - 1 : duration
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("操作倒计时")
        .accessibilityValue("剩余 \(remaining) 秒")
    }
}

private struct FeedbackToast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.black.opacity(0.82), in: Capsule())
            .shadow(radius: 8, y: 3)
            .accessibilityAddTraits(.isStaticText)
    }
}

private extension View {
    @ViewBuilder
    func demoInlineNavigationBar(showsBackground: Bool = false) -> some View {
#if os(iOS)
        if showsBackground {
            navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            navigationBarTitleDisplayMode(.inline)
        }
#else
        self
#endif
    }

    @ViewBuilder
    func demoHideNavigationBar() -> some View {
#if os(iOS)
        navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
#else
        self
#endif
    }
}

struct GameBoardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack {
                GameBoardView()
            }
            .previewDisplayName("iPhone 14")
            .previewDevice("iPhone 14")

            NavigationStack {
                GameBoardView()
            }
            .previewDisplayName("iPhone 14 Pro Max")
            .previewDevice("iPhone 14 Pro Max")
        }
    }
}
