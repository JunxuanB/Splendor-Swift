import SwiftUI

/// Root of the Splendor Duel UI demo. The opponent panel stays pinned at top;
/// the central area swipes between the two big boards — 宝石版图 and 发展卡版图.
struct DuelGameBoardView: View {
    @StateObject private var state = DuelGameState()
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingExitConfirmation = false
    @State private var page: DuelBoardPage = .gems

    var body: some View {
        VStack(spacing: 0) {
            DuelNavBar(title: "双人对局") { isShowingExitConfirmation = true }

            DuelWinHeader(state: state)

            Divider()

            GeometryReader { proxy in
                let roomy = proxy.size.height >= 430

                VStack(spacing: roomy ? 9 : 6) {
                    DuelOpponentPanel(state: state)

                    Picker("版图", selection: $page.animation(.snappy)) {
                        ForEach(DuelBoardPage.allCases) { page in
                            Text(page.title).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)

                    TabView(selection: $page) {
                        DuelTokenBoard(state: state)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .tag(DuelBoardPage.gems)

                        DuelCardBoard(state: state)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .tag(DuelBoardPage.cards)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, roomy ? 9 : 5)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground))

            DuelPlayerBar(state: state)
        }
        .overlayPreferenceValue(DuelAnchorKey.self) { anchors in
            GeometryReader { proxy in
                DuelFlightLayer(state: state, anchors: anchors, proxy: proxy)
            }
            .allowsHitTesting(false)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("退出演示对局？", isPresented: $isShowingExitConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { dismiss() }
        } message: {
            Text("退出后，本局的演示数据会被重置。")
        }
        .sheet(item: $state.activeSheet) { sheet in
            DuelDetailSheet(sheet: sheet, state: state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let message = state.feedbackMessage {
                DuelFeedbackToast(message: message)
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

enum DuelBoardPage: Int, CaseIterable, Identifiable, Hashable {
    case gems, cards

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .gems: "宝石版图"
        case .cards: "发展卡版图"
        }
    }
}

// MARK: - Win tracks

private struct DuelWinHeader: View {
    @ObservedObject var state: DuelGameState

    var body: some View {
        HStack(spacing: 10) {
            track(icon: "trophy.fill", tint: .blue, current: state.pointsProgress, target: DuelRules.targetPoints)
            Divider().frame(height: 26)
            track(icon: DuelSymbol.crown, tint: Color(red: 0.86, green: 0.66, blue: 0.20),
                  current: state.crownsProgress, target: DuelRules.targetCrowns)
            Divider().frame(height: 26)
            track(icon: "paintpalette.fill", tint: .purple, current: state.colorProgress, target: DuelRules.targetColorPoints)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func track(icon: String, tint: Color, current: Int, target: Int) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(tint)
                Text("\(current)/\(target)")
                    .font(.caption.bold().monospacedDigit())
                    .contentTransition(.numericText())
            }
            ProgressView(value: Double(min(current, target)), total: Double(target))
                .tint(tint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Opponent panel (2-player, styled like the base game's card)

private struct DuelOpponentPanel: View {
    @ObservedObject var state: DuelGameState

    private let goldTint = Color(red: 0.86, green: 0.66, blue: 0.20)
    private var opponent: DuelPlayerSnapshot { state.opponent }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Label {
                    Text(opponent.name).font(.headline)
                } icon: {
                    Image(systemName: opponent.isBot ? "cpu" : "person.crop.circle.fill")
                        .foregroundStyle(.tint)
                }

                Spacer(minLength: 0)

                // The three victory conditions, then reserved + privilege.
                iconStat(icon: "trophy.fill", tint: .blue, value: "\(opponent.points)")
                divider
                iconStat(icon: DuelSymbol.crown, tint: goldTint, value: "\(opponent.crowns)")
                divider
                iconStat(icon: "paintpalette.fill", tint: .purple, value: "\(opponent.topColorPoints)")
                divider
                textStat(value: "\(opponent.reservedCount)/3", label: "预留")
                divider
                privilegeStat
            }

            HStack(spacing: 4) {
                ForEach(DuelColor.resourceOrder) { color in
                    DuelResourceStack(
                        color: color,
                        permanent: opponent.bonuses[color, default: 0],
                        tokens: opponent.tokens[color, default: 0],
                        compact: true
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            DuelColorPointsRow(colorPoints: opponent.colorPoints)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            if !state.isLocalTurn {
                DuelShimmerBorder(cornerRadius: 18, lineWidth: 2.5)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.openOpponentReservedCards() }
        .accessibilityHint("轻点查看对手的预留牌")
    }

    private var divider: some View { Divider().frame(height: 24) }

    private func iconStat(icon: String, tint: Color, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.bold().monospacedDigit())
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tint)
        }
    }

    private func textStat(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var privilegeStat: some View {
        VStack(spacing: 1) {
            Text("\(opponent.privileges)").font(.subheadline.bold().monospacedDigit())
            Image(systemName: DuelSymbol.privilege)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.52, green: 0.36, blue: 0.72))
        }
    }
}

/// One chip per gem color showing prestige accumulated from that color's cards —
/// the basis for the single-color (10-point) victory track. Shared by both panels.
private struct DuelColorPointsRow: View {
    let colorPoints: [DuelColor: Int]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DuelColor.resourceOrder) { color in
                if DuelColor.gemColors.contains(color) {
                    let points = colorPoints[color, default: 0]
                    Text("\(points)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(points > 0 ? color.foreground : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 15)
                        .background(
                            color.tint.opacity(points > 0 ? 0.9 : 0.12),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                } else {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 15)
                }
            }
        }
        .accessibilityLabel("各颜色卡牌总分")
    }
}

// MARK: - Player resource bar (adds a per-color prestige row)

private struct DuelPlayerBar: View {
    @ObservedObject var state: DuelGameState

    private var player: DuelPlayerSnapshot { state.player }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                state.openReservedCards()
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(player.points)")
                            .font(.title2.bold().monospacedDigit())
                            .contentTransition(.numericText())
                            .popEffect(trigger: player.points)
                            .duelFlightAnchor(.playerScore)
                        Text("总分").font(.caption2).foregroundStyle(.secondary)
                    }

                    DuelCrownBadge(count: player.crowns, size: 14)
                        .popEffect(trigger: player.crowns)

                    HStack(spacing: 2) {
                        Text("\(state.reservedCards.count)/3")
                            .font(.caption.bold().monospacedDigit())
                        Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                    }
                    .popEffect(trigger: state.reservedCards.count)
                    .duelFlightAnchor(.reservedArea)
                }
                .frame(width: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("总分 \(player.points)，王冠 \(player.crowns)，预留 \(state.reservedCards.count) 张")

            Divider().frame(height: 74)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(DuelColor.resourceOrder) { color in
                        DuelResourceStack(
                            color: color,
                            permanent: player.bonuses[color, default: 0],
                            tokens: player.tokens[color, default: 0],
                            compact: true
                        )
                        .popEffect(trigger: player.bonuses[color, default: 0] + player.tokens[color, default: 0])
                        .duelFlightAnchor(.playerToken(color))
                        .frame(maxWidth: .infinity)
                    }
                }

                DuelColorPointsRow(colorPoints: player.colorPoints)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Chrome

private struct DuelNavBar: View {
    let title: String
    var onExit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            DuelTurnCountdown()
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
            Rectangle().fill(.bar).ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct DuelTurnCountdown: View {
    var duration = 30
    @State private var remaining = 30

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var isUrgent: Bool { remaining <= 5 }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "timer").font(.footnote.weight(.semibold))
            Text("\(remaining)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
        }
        .foregroundStyle(isUrgent ? Color.red : .primary)
        .padding(.horizontal, isUrgent ? 8 : 0)
        .padding(.vertical, 3)
        .background(isUrgent ? Color.red.opacity(0.14) : Color.clear, in: Capsule())
        .animation(.snappy, value: isUrgent)
        .onReceive(timer) { _ in
            withAnimation(.snappy) { remaining = remaining > 1 ? remaining - 1 : duration }
        }
        .accessibilityLabel("操作倒计时")
        .accessibilityValue("剩余 \(remaining) 秒")
    }
}

private struct DuelFeedbackToast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.black.opacity(0.82), in: Capsule())
            .shadow(radius: 8, y: 3)
    }
}

struct DuelGameBoardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DuelGameBoardView()
        }
        .previewDisplayName("Duel")
    }
}
