import SwiftUI

struct SilkRoadGameBoardView: View {
    @StateObject private var state = SilkRoadGameState()
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingExitConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            navBar
            progressHeader
            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 9) {
                    SilkRoadOpponentCarousel(state: state)
                    SilkRoadGemBank(state: state)
                    SilkRoadNobleStrip(nobles: state.nobles)
                    SilkRoadMarket(state: state)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))

            playerBar
        }
        .silkRoadHideNavigationBar()
        .alert("退出丝绸之路演示？", isPresented: $isShowingExitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { dismiss() }
        } message: {
            Text("退出后，本局假数据会被重置。")
        }
        .sheet(item: $state.activeSheet) { sheet in
            SilkRoadDetailSheet(sheet: sheet, state: state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let message = state.feedbackMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.84), in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .animation(.snappy, value: state.feedbackMessage)
        .task(id: state.feedbackMessage) {
            guard let message = state.feedbackMessage else { return }
            try? await Task.sleep(for: .seconds(2))
            state.clearFeedback(ifMatching: message)
        }
    }

    private var navBar: some View {
        HStack(spacing: 8) {
            Label("30", systemImage: "timer")
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("丝绸之路")
                .font(.headline)
                .fixedSize()
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button { state.openRules() } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("查看简版规则")
                Button("退出", role: .destructive) { isShowingExitConfirmation = true }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 44)
        .padding(.horizontal, 14)
        .background { Rectangle().fill(.bar).ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var progressHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "map.fill").foregroundStyle(SilkRoadPalette.accent)
            ProgressView(value: Double(state.playerPrestige), total: Double(state.targetPrestige))
                .tint(SilkRoadPalette.accent)
            Text(String(format: "%02d / %02d", state.playerPrestige, state.targetPrestige))
                .font(.subheadline.bold().monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var playerBar: some View {
        HStack(spacing: 7) {
            Button { state.openReservedCards() } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.playerPrestige)").font(.title2.bold().monospacedDigit())
                    Text("总分").font(.caption2).foregroundStyle(.secondary)
                    Text("预留 \(state.reservedCards.count)/3").font(.caption2.bold())
                }
                .frame(width: 52, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 47)

            HStack(spacing: 3) {
                ForEach(GemColor.allCases) { gem in
                    ResourceStackView(
                        gem: gem,
                        permanent: state.playerBonuses[gem, default: 0],
                        tokens: state.playerTokens[gem, default: 0],
                        compact: true
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private extension View {
    @ViewBuilder
    func silkRoadHideNavigationBar() -> some View {
#if os(iOS)
        navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
#else
        self
#endif
    }
}

struct SilkRoadGameBoardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SilkRoadGameBoardView() }
            .previewDisplayName("iPhone 17 Pro")
            .previewDevice("iPhone 17 Pro")
    }
}

