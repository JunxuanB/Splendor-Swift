import LuminoreCore
import SwiftUI

struct GameBoardView: View {
    @ObservedObject var session: LANSessionService
    let onExit: () -> Void
    let onSaveAndSuspend: () -> Void

    @State private var opponentIndex = 0
    @State private var selectedGems: [GemColor: Int] = [:]
    @State private var pendingReturn: PendingReturn?
    @State private var selectedCard: SelectedCard?
    @State private var selectedNoble: NobleTile?
    @State private var reservedSheet: ReservedCardsSheetRequest?
    @State private var isShowingExitConfirmation = false
    @State private var isShowingPassConfirmation = false
    @State private var flights: [GameFlight] = []
    @State private var bursts: [GameBurst] = []
    @State private var lastPrestige: Int?

    private var snapshot: ClientGameSnapshot? { session.game }
    private var localPlayer: PublicPlayerSnapshot? {
        snapshot?.players.first { $0.id == session.localID }
    }
    private var isLocalTurn: Bool { snapshot?.currentPlayerID == session.localID }

    var body: some View {
        VStack(spacing: 0) {
            GameNavigationBar(
                deadline: session.turnDeadline,
                hasTimer: snapshot?.configuration.turnDurationSeconds != nil,
                gracePeriodEnabled: snapshot?.configuration.turnGracePeriodEnabled == true,
                canPause: session.isHost && !session.isPaused,
                onPause: { session.pauseGame() },
                onExit: { isShowingExitConfirmation = true }
            )

            if let player = localPlayer, let target = snapshot?.configuration.targetPrestige {
                VictoryProgressHeader(current: player.prestige, target: target)
            }

            Divider()

            GeometryReader { proxy in
                let roomy = proxy.size.height >= 430

                if let snapshot, let player = localPlayer {
                    VStack(spacing: roomy ? 10 : 6) {
                        OpponentCarousel(
                            opponents: opponents(in: snapshot),
                            currentPlayerID: snapshot.currentPlayerID,
                            opponentIndex: $opponentIndex,
                            onOpenReservedCards: openOpponentReservedCards
                        )

                        GemBankSection(
                            bank: snapshot.bank,
                            isLocalTurn: isLocalTurn,
                            selectedGems: $selectedGems,
                            onToggle: { toggleGem($0, bank: snapshot.bank) },
                            onTake: { prepareTake(player: player) },
                            onPass: { isShowingPassConfirmation = true }
                        )
                        .padding(.vertical, roomy ? 2 : 0)

                        NobleSection(
                            nobles: snapshot.availableNobles,
                            onSelect: { selectedNoble = $0 }
                        )
                        .padding(.vertical, roomy ? 2 : 0)

                        MarketSection(
                            snapshot: snapshot,
                            player: player,
                            isLocalTurn: isLocalTurn,
                            onSelectCard: { card, source in
                                selectedCard = SelectedCard(card: card, source: source)
                            },
                            onReserveDeck: {
                                prepareReserve(.deck(tier: $0), card: nil, player: player, bank: snapshot.bank)
                            }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, roomy ? 9 : 5)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .background(Color(.systemGroupedBackground))

            if let snapshot, let player = localPlayer {
                PlayerInventoryBar(
                    player: player,
                    reservedCardCount: snapshot.localReservedCards.count,
                    isCurrentPlayer: isLocalTurn,
                    deadline: session.turnDeadline,
                    turnDurationSeconds: snapshot.configuration.turnDurationSeconds,
                    onOpenReservedCards: {
                        reservedSheet = ReservedCardsSheetRequest(
                            title: "game.reserved.title",
                            cards: snapshot.localReservedCards,
                            cardCount: snapshot.localReservedCards.count,
                            purchasableCardIDs: isLocalTurn
                                ? Set(snapshot.localReservedCards.filter { canPurchase($0, player: player) }.map(\.id))
                                : []
                        )
                    }
                )
            }
        }
        .overlayPreferenceValue(GameAnchorKey.self) { anchors in
            GeometryReader { proxy in
                GameFlightLayer(
                    flights: flights,
                    bursts: bursts,
                    anchors: anchors,
                    proxy: proxy,
                    onFlightEnded: { id in flights.removeAll { $0.id == id } },
                    onBurstEnded: { id in bursts.removeAll { $0.id == id } }
                )
            }
            .allowsHitTesting(false)
        }
        .overlay {
            if isLocalTurn {
                CurrentTurnBorder()
            }
        }
        .overlay {
            if snapshot?.configuration.turnGracePeriodEnabled == true,
               let deadline = session.turnDeadline {
                GracePeriodBorder(deadline: deadline)
            }
        }
        .overlay {
            if session.isPaused {
                PausedCoverView(
                    isHost: session.isHost,
                    isAwaitingAssignment: session.isAwaitingResumeAssignment,
                    participants: session.room?.participants ?? [],
                    pendingSubstitutes: session.pendingSubstitutes,
                    localID: session.localID,
                    onResume: { session.resumeGame() },
                    onSaveAndSuspend: onSaveAndSuspend,
                    onAssign: { session.assignSubstitute(seatID: $0, substituteID: $1) },
                    onContinueResumed: { session.continueResumedGame() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isPaused)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("game.exit.title", isPresented: $isShowingExitConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("game.exit", role: .destructive, action: onExit)
        } message: {
            Text("game.exit.message")
        }
        .confirmationDialog(
            "game.pass.confirm",
            isPresented: $isShowingPassConfirmation,
            titleVisibility: .visible
        ) {
            Button("game.pass", role: .destructive) { session.submit(.pass) }
            Button("common.cancel", role: .cancel) {}
        }
        .sheet(item: $pendingReturn) { pending in
            ReturnTokensView(available: pending.available, required: pending.required) { returns in
                guard isLocalTurn else { return }
                switch pending.kind {
                case let .take(tokens):
                    animateGems(tokens)
                    submitAfterAnimation(.take(tokens: tokens, returning: returns))
                case let .reserve(source, card):
                    if let card { animateCard(card, source: source, isPurchase: false) }
                    submitAfterAnimation(.reserve(source: source, returning: returns))
                }
                selectedGems = [:]
            }
        }
        .sheet(item: $selectedCard) { selection in
            if let snapshot, let player = localPlayer {
                CardDetailSheet(
                    selection: selection,
                    player: player,
                    nobles: snapshot.availableNobles,
                    allowsActions: isLocalTurn,
                    onReserve: {
                        guard isLocalTurn else { return }
                        prepareReserve(
                            selection.source,
                            card: selection.card,
                            player: player,
                            bank: snapshot.bank
                        )
                        selectedCard = nil
                    },
                    onPurchase: { payment, nobleID in
                        guard isLocalTurn else { return }
                        animateCard(selection.card, source: selection.source, isPurchase: true)
                        submitAfterAnimation(
                            .purchase(source: selection.source, payment: payment, nobleID: nobleID)
                        )
                        selectedCard = nil
                    }
                )
            }
        }
        .sheet(item: $selectedNoble) { noble in
            NobleDetailSheet(noble: noble)
        }
        .sheet(item: $reservedSheet) { request in
            ReservedCardsSheet(request: request) { card in
                reservedSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedCard = SelectedCard(card: card, source: .reserved(cardID: card.id))
                }
            }
        }
        .onChange(of: snapshot?.revision) { _, _ in
            selectedGems = [:]
            let count = snapshot.map { opponents(in: $0).count } ?? 0
            opponentIndex = count == 0 ? 0 : min(opponentIndex, count - 1)
            if let prestige = localPlayer?.prestige {
                if let lastPrestige, prestige > lastPrestige {
                    bursts.append(GameBurst(at: .scoreLabel))
                }
                lastPrestige = prestige
            }
        }
        .onChange(of: snapshot?.currentPlayerID) { _, currentPlayerID in
            if currentPlayerID != session.localID { closePendingTurnUI() }
        }
        .onAppear { lastPrestige = localPlayer?.prestige }
    }

    private func opponents(in snapshot: ClientGameSnapshot) -> [PublicPlayerSnapshot] {
        snapshot.players.filter { $0.id != session.localID }
    }

    private func openOpponentReservedCards(_ opponent: PublicPlayerSnapshot) {
        reservedSheet = ReservedCardsSheetRequest(
            title: "game.opponent.reserved.title \(opponent.nickname)",
            cards: [],
            cardCount: opponent.reservedCardCount,
            purchasableCardIDs: [],
            hidesCards: true
        )
    }

    private func toggleGem(_ gem: GemColor, bank: [GemColor: Int]) {
        guard gem != .gold, bank[gem, default: 0] > 0 else { return }
        let current = selectedGems[gem, default: 0]
        if selectedGems.count == 1, current == 1, bank[gem, default: 0] >= 4 {
            selectedGems[gem] = 2
        } else if current > 0 {
            selectedGems.removeValue(forKey: gem)
        } else if selectedGems.values.reduce(0, +) < 3,
                  selectedGems.values.allSatisfy({ $0 == 1 }) {
            selectedGems[gem] = 1
        }
    }

    private func prepareTake(player: PublicPlayerSnapshot) {
        var available = player.tokens
        for (gem, count) in selectedGems { available[gem, default: 0] += count }
        let required = max(0, available.values.reduce(0, +) - 10)
        if required > 0 {
            pendingReturn = PendingReturn(kind: .take(selectedGems), available: available, required: required)
        } else {
            animateGems(selectedGems)
            submitAfterAnimation(.take(tokens: selectedGems, returning: [:]))
            selectedGems = [:]
        }
    }

    private func prepareReserve(
        _ source: CardSource,
        card: DevelopmentCard?,
        player: PublicPlayerSnapshot,
        bank: [GemColor: Int]
    ) {
        var available = player.tokens
        if bank[.gold, default: 0] > 0 { available[.gold, default: 0] += 1 }
        let required = max(0, available.values.reduce(0, +) - 10)
        if required > 0 {
            pendingReturn = PendingReturn(kind: .reserve(source, card), available: available, required: required)
        } else {
            if let card { animateCard(card, source: source, isPurchase: false) }
            submitAfterAnimation(.reserve(source: source, returning: [:]))
        }
    }

    private func animateGems(_ gems: [GemColor: Int]) {
        var index = 0
        for gem in GemColor.allCases {
            for _ in 0 ..< gems[gem, default: 0] {
                flights.append(
                    GameFlight(
                        kind: .gem(gem),
                        from: .bankGem(gem),
                        to: .playerStack(gem),
                        delay: Double(index) * 0.08
                    )
                )
                index += 1
            }
        }
        scheduleFlightCleanup()
    }

    private func animateCard(_ card: DevelopmentCard, source: CardSource, isPurchase: Bool) {
        let from: GameAnchorID
        switch source {
        case .market: from = .marketCard(card.id)
        case .reserved: from = .reservedArea
        case .deck: return
        }
        flights.append(
            GameFlight(
                kind: isPurchase ? .cardBuy(card) : .cardReserve(card),
                from: from,
                to: isPurchase ? .playerStack(card.bonus) : .reservedArea
            )
        )
        scheduleFlightCleanup()
    }

    private func submitAfterAnimation(_ action: GameAction) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { session.submit(action) }
    }

    private func scheduleFlightCleanup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { flights.removeAll() }
    }

    private func closePendingTurnUI() {
        selectedGems = [:]
        pendingReturn = nil
        selectedCard = nil
        reservedSheet = nil
        isShowingPassConfirmation = false
        flights.removeAll()
    }
}
