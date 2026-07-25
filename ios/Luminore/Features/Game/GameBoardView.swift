import LuminoreCore
import SwiftUI

struct GameBoardView: View {
    @ObservedObject var session: MatchSessionService
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
    @State private var isShowingDeveloperGemEditor = false
    @State private var developerTokens: [GemColor: Int] = [:]
    @State private var flights: [GameFlight] = []
    @State private var bursts: [GameBurst] = []

    private var snapshot: ClientGameSnapshot? { session.game }
    private var localPlayer: PublicPlayerSnapshot? {
        snapshot?.players.first { $0.id == session.localID }
    }
    private var isLocalTurn: Bool {
        !session.isOpeningTurnSelection && snapshot?.currentPlayerID == session.localID
    }

    var body: some View {
        VStack(spacing: 0) {
            GameNavigationBar(
                deadline: session.turnDeadline,
                hasTimer: snapshot?.configuration.turnDurationSeconds != nil,
                gracePeriodEnabled: snapshot?.configuration.turnGracePeriodEnabled == true,
                canPause: session.isHost && !session.isPaused && !session.isOpeningTurnSelection,
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
                .simultaneousGesture(
                    TapGesture(count: DeveloperTools.unlockTapCount)
                        .onEnded {
                            guard DeveloperTools.isEnabledForCurrentBuild, session.isHost else { return }
                            developerTokens = player.tokens
                            isShowingDeveloperGemEditor = true
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
                    onFlightResolved: resolveFlight,
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
            if isLocalTurn,
               snapshot?.configuration.turnGracePeriodEnabled == true,
               let deadline = session.turnDeadline {
                GracePeriodBorder(deadline: deadline)
            }
        }
        .overlay {
            if let snapshot, let selection = session.openingTurnSelection {
                OpeningTurnRouletteView(
                    players: snapshot.players,
                    startingPlayerID: snapshot.startingPlayerID,
                    selection: selection
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if let pause = session.matchPause {
                switch pause.reason {
                case .host:
                    PausedCoverView(
                        isHost: session.isHost,
                        onResume: { session.resumeGame() },
                        onSaveAndSuspend: onSaveAndSuspend
                    )
                    .transition(.opacity)
                case .disconnect:
                    DisconnectPauseView(pause: pause)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.matchPause)
        .animation(.easeInOut(duration: 0.25), value: session.openingTurnSelection)
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
                    session.submit(.take(tokens: tokens, returning: returns))
                case let .reserve(source, _):
                    session.submit(.reserve(source: source, returning: returns))
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
                    showsPurchaseHighlight: snapshot.configuration.affordableCardHighlightEnabled,
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
                        session.submit(
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
            ReservedCardsSheet(
                request: request,
                showsPurchaseHighlight: snapshot?.configuration.affordableCardHighlightEnabled ?? true
            ) { card in
                reservedSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedCard = SelectedCard(card: card, source: .reserved(cardID: card.id))
                }
            }
        }
        .sheet(isPresented: $isShowingDeveloperGemEditor) {
            DeveloperStandardGemEditor(tokens: $developerTokens) {
                session.developerSetLocalTokens(developerTokens)
            }
        }
        .onChange(of: snapshot?.revision) { _, _ in
            selectedGems = [:]
            let count = snapshot.map { opponents(in: $0).count } ?? 0
            opponentIndex = count == 0 ? 0 : min(opponentIndex, count - 1)
        }
        .onChange(of: session.gameAnimationEvent) { _, event in
            if let event { animate(event) }
        }
        .onChange(of: snapshot?.currentPlayerID) { _, currentPlayerID in
            if currentPlayerID != session.localID { closePendingTurnUI() }
        }
        .sensoryFeedback(trigger: isLocalTurn) { wasLocalTurn, isLocalTurn in
            !wasLocalTurn && isLocalTurn ? .success : nil
        }
    }

    private func opponents(in snapshot: ClientGameSnapshot) -> [PublicPlayerSnapshot] {
        snapshot.players.filter { $0.id != session.localID }
    }

    private func openOpponentReservedCards(_ opponent: PublicPlayerSnapshot) {
        reservedSheet = ReservedCardsSheetRequest(
            title: "game.opponent.reserved.title \(opponent.nickname)",
            cards: opponent.reservedCards,
            cardCount: opponent.reservedCardCount,
            purchasableCardIDs: [],
            isReadOnly: true
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
            session.submit(.take(tokens: selectedGems, returning: [:]))
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
            session.submit(.reserve(source: source, returning: [:]))
        }
    }

    private func animate(_ event: GameAnimationEvent) {
        let focusDelay = focusOnPlayer(event.playerID) ? 0.24 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
            switch event.kind {
            case let .take(tokens):
                animateGems(tokens, playerID: event.playerID)
            case let .reserve(source, card):
                if let card {
                    animateCard(card, source: source, isPurchase: false, playerID: event.playerID)
                }
            case let .purchase(source, card, noble):
                animateCard(card, source: source, isPurchase: true, playerID: event.playerID)
                if card.prestige > 0 {
                    scheduleBurst(at: .scoreLabel(event.playerID), after: 0.8)
                }
                if let noble {
                    animateNoble(noble, playerID: event.playerID)
                    scheduleBurst(at: .scoreLabel(event.playerID), after: 1.42)
                }
            case .pass:
                break
            }
        }
    }

    /// Makes a remote actor visible before resolving their destination anchors.
    @discardableResult
    private func focusOnPlayer(_ playerID: UUID) -> Bool {
        guard playerID != session.localID, let snapshot else { return false }
        let visibleOpponents = opponents(in: snapshot)
        guard let index = visibleOpponents.firstIndex(where: { $0.id == playerID }),
              index != opponentIndex
        else { return false }
        withAnimation(.snappy) { opponentIndex = index }
        return true
    }

    private func animateGems(_ gems: [GemColor: Int], playerID: UUID) {
        var index = 0
        for gem in GemColor.allCases {
            for _ in 0 ..< gems[gem, default: 0] {
                flights.append(
                    GameFlight(
                        kind: .gem(gem),
                        from: .bankGem(gem),
                        to: .playerStack(playerID, gem),
                        delay: Double(index) * 0.08
                    )
                )
                index += 1
            }
        }
        scheduleFlightCleanup()
    }

    private func animateCard(
        _ card: DevelopmentCard,
        source: CardSource,
        isPurchase: Bool,
        playerID: UUID
    ) {
        let from: GameAnchorID
        switch source {
        case .market: from = .marketCard(card.id)
        case .reserved: from = .reservedArea(playerID)
        case .deck: return
        }
        flights.append(
            GameFlight(
                kind: isPurchase ? .cardBuy(card) : .cardReserve(card),
                from: from,
                to: isPurchase
                    ? .playerStack(playerID, card.bonus)
                    : .reservedArea(playerID),
                delay: 0.28
            )
        )
        scheduleFlightCleanup()
    }

    private func animateNoble(_ noble: NobleTile, playerID: UUID) {
        flights.append(
            GameFlight(
                kind: .noble(noble),
                from: .nobleTile(noble.id),
                to: .scoreLabel(playerID),
                delay: 0.28
            )
        )
        scheduleFlightCleanup()
    }

    private func resolveFlight(_ id: UUID, start: CGRect, end: CGRect) {
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return }
        flights[index].resolvedStart = start
        flights[index].resolvedEnd = end
    }

    private func scheduleBurst(at anchor: GameAnchorID, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            bursts.append(GameBurst(at: anchor))
        }
    }

    private func scheduleFlightCleanup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { flights.removeAll() }
    }

    private func closePendingTurnUI() {
        selectedGems = [:]
        pendingReturn = nil
        selectedCard = nil
        reservedSheet = nil
        isShowingPassConfirmation = false
    }
}
