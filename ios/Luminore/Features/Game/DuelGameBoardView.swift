import LuminoreCore
import SwiftUI

private struct DuelCardSelection: Identifiable {
    let card: DuelJewelCard
    let source: DuelCardSource
    var id: String { card.id }
}

private struct DuelReserveSelection: Identifiable {
    let source: DuelCardSource
    let card: DuelJewelCard?
    let id = UUID()
}

private struct DuelReservedCardsRequest: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let cards: [DuelJewelCard]
    let purchasableCardIDs: Set<String>
    var isReadOnly = false
}

struct DuelGameBoardView: View {
    @ObservedObject var session: MatchSessionService
    var tutorial: TutorialController<DuelAnchorID>? = nil
    let onExit: () -> Void
    let onSaveAndSuspend: () -> Void

    @State private var page: DuelBoardPage = .tokens
    @State private var selectedIndices: [Int] = []
    @State private var privilegeMode = false
    @State private var selectedCard: DuelCardSelection?
    @State private var selectedRoyal: DuelRoyalCard?
    @State private var reserveSelection: DuelReserveSelection?
    @State private var returnDraft: DuelReturnDraft?
    @State private var reservedCardsRequest: DuelReservedCardsRequest?
    @State private var showsExitConfirmation = false
    @State private var showsSkipConfirmation = false
    @State private var duelNotice: DuelActionNotice?
    @State private var flights: [DuelFlight] = []
    @State private var bursts: [DuelBurst] = []
    @State private var lastDuel: DuelClientSnapshot?
    @State private var lastCurrentPlayerID: UUID?
    @State private var showsDeveloperGemEditor = false
    @State private var developerTokens: [DuelTokenColor: Int] = [:]

    private var snapshot: ClientGameSnapshot? { session.game }
    private var duel: DuelClientSnapshot? { snapshot?.duel }
    private var localPlayer: DuelPublicPlayerSnapshot? { duel?.players.first { $0.id == session.localID } }
    private var opponent: DuelPublicPlayerSnapshot? { duel?.players.first { $0.id != session.localID } }
    private var opponentIdentity: PublicPlayerSnapshot? { snapshot?.players.first { $0.id != session.localID } }
    private var isLocalTurn: Bool {
        !session.isOpeningTurnSelection && snapshot?.currentPlayerID == session.localID
    }

    var body: some View {
        VStack(spacing: 0) {
            GameNavigationBar(
                deadline: session.turnDeadline,
                hasTimer: snapshot?.configuration.turnDurationSeconds != nil,
                gracePeriodEnabled: snapshot?.configuration.turnGracePeriodEnabled == true,
                canPause: session.isHost && !session.isPaused && !session.isOpeningTurnSelection && tutorial == nil,
                onPause: { session.pauseGame() },
                onExit: { showsExitConfirmation = true }
            )

            if let localPlayer {
                DuelVictoryHeader(player: localPlayer)
                    .duelFlightAnchor(.victory(localPlayer.id))
            }
            Divider()

            GeometryReader { proxy in
                if let snapshot, let duel, let localPlayer, let opponent, let opponentIdentity {
                    let roomy = proxy.size.height >= 430
                    VStack(spacing: roomy ? 9 : 6) {
                        DuelOpponentPanel(
                            identity: opponentIdentity,
                            duelPlayer: opponent,
                            isCurrent: snapshot.currentPlayerID == opponent.id,
                            onOpenReservedCards: { openOpponentReservedCards(opponent, identity: opponentIdentity) }
                        )

                        pagePicker

                        TabView(selection: $page) {
                            DuelTokenBoardSection(
                                duel: duel,
                                player: localPlayer,
                                isLocalTurn: isLocalTurn,
                                selectableIndices: tutorialGuide.selectableBoardIndices,
                                canConfirmTake: tutorialGuide.canConfirmTake,
                                canUsePrivilege: tutorialGuide.canUsePrivilege,
                                canReplenish: tutorialGuide.canReplenish,
                                canSkipTurn: tutorialGuide.canSkipTurn,
                                selectedIndices: $selectedIndices,
                                privilegeMode: $privilegeMode,
                                onTapToken: tapBoardToken,
                                onConfirmTake: prepareTake,
                                onReplenish: {
                                    guard activeTutorialInteraction == nil
                                            || activeTutorialInteraction == .duelReplenish else { return }
                                    session.submit(.duel(.replenish))
                                },
                                onSkipTurn: { showsSkipConfirmation = true }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .tag(DuelBoardPage.tokens)

                            DuelCardBoardSection(
                                duel: duel,
                                player: localPlayer,
                                isLocalTurn: isLocalTurn,
                                showsHighlight: snapshot.configuration.affordableCardHighlightEnabled,
                                selectableCardIDs: tutorialGuide.selectableCardIDs,
                                selectableRoyalIDs: tutorialGuide.selectableRoyalIDs,
                                canReserveDeck: activeTutorialInteraction == nil,
                                onSelectCard: {
                                    guard tutorialGuide.allowsCard($0.id) else { return }
                                    selectedCard = DuelCardSelection(card: $0, source: $1)
                                },
                                onReserveDeck: { reserveSelection = DuelReserveSelection(source: .deck(tier: $0), card: nil) },
                                onSelectRoyal: { selectedRoyal = $0 }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .tag(DuelBoardPage.cards)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, roomy ? 9 : 5)
                }
            }
            .background(Color(.systemGroupedBackground))

            if let localPlayer {
                inventoryBar(for: localPlayer)
            }
        }
        .overlayPreferenceValue(DuelAnchorKey.self) { anchors in
            GeometryReader { proxy in
                DuelFlightLayer(
                    flights: flights,
                    bursts: bursts,
                    anchors: anchors,
                    proxy: proxy,
                    onFlightEnded: { id in flights.removeAll { $0.id == id } },
                    onFlightResolved: { id, start, end in
                        if let i = flights.firstIndex(where: { $0.id == id }) {
                            flights[i].resolvedStart = start
                            flights[i].resolvedEnd = end
                        }
                    },
                    onBurstEnded: { id in bursts.removeAll { $0.id == id } }
                )
            }
            .allowsHitTesting(false)
        }
        .overlayPreferenceValue(DuelAnchorKey.self) { anchors in
            if let tutorial {
                GeometryReader { proxy in
                    TutorialCoachOverlay(
                        controller: tutorial,
                        targetRects: tutorialGuide.highlights(default: tutorial.currentStep?.highlights ?? [])
                            .compactMap { anchors[$0].map { proxy[$0] } },
                        actionHintKey: tutorialGuide.actionHintKey,
                        onExit: onExit
                    )
                }
            }
        }
        .background {
            if let tutorial {
                DuelTutorialPageSynchronizer(controller: tutorial, page: $page)
            }
        }
        .overlay { if isLocalTurn { CurrentTurnBorder() } }
        .overlay {
            if isLocalTurn, snapshot?.configuration.turnGracePeriodEnabled == true, let deadline = session.turnDeadline {
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
                case .disconnect:
                    DisconnectPauseView(pause: pause)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("game.exit.title", isPresented: $showsExitConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("game.exit", role: .destructive, action: onExit)
        } message: { Text("game.exit.message") }
        .sheet(item: $returnDraft) { draft in
            DuelReturnTokensSheet(draft: draft) { returns in
                if case let .take(indices) = draft.kind {
                    session.submit(.duel(.take(boardIndices: indices, returning: returns)))
                }
            }
        }
        .sheet(item: $reserveSelection) { selection in reserveSheet(selection) }
        .sheet(item: $selectedCard) { selection in purchaseSheet(selection) }
        .sheet(item: $selectedRoyal) { royal in DuelRoyalDetailSheet(royal: royal) }
        .sheet(item: $reservedCardsRequest) { request in reservedSheet(request) }
        .sheet(isPresented: $showsDeveloperGemEditor) {
            DeveloperDuelGemEditor(tokens: $developerTokens) {
                session.developerSetLocalTokens(developerTokens)
            }
        }
        .onChange(of: snapshot?.revision) { _, _ in
            selectedIndices = []
            privilegeMode = false
            handleSnapshotChange()
            if let snapshot { tutorial?.handleSnapshot(snapshot) }
        }
        .onChange(of: snapshot?.currentPlayerID) { _, playerID in
            if playerID != session.localID {
                selectedCard = nil
                selectedRoyal = nil
                reserveSelection = nil
                returnDraft = nil
                reservedCardsRequest = nil
            }
        }
        .alert("duel.skipTurn.title", isPresented: $showsSkipConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("duel.skipTurn", role: .destructive) { session.submit(.pass) }
        } message: { Text("duel.skipTurn.message") }
        .overlay(alignment: .top) {
            if let notice = duelNotice {
                DuelActionNoticeBanner(notice: notice)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .animation(.snappy, value: duelNotice)
        .task(id: duelNotice) {
            guard duelNotice != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            duelNotice = nil
        }
        .sensoryFeedback(.impact, trigger: duelNotice) { _, new in new != nil }
    }

    /// Single entry point for reacting to a new authoritative snapshot: diff the
    /// previous Duel snapshot against the current one to drive both the ability
    /// banners and the flight animations. Duel actions carry no animation payload,
    /// so everything is derived client-side and therefore identical across transports.
    private func handleSnapshotChange() {
        guard let duel, let snapshot else { return }
        let current = snapshot.currentPlayerID
        let before = lastDuel
        defer {
            lastDuel = duel
            lastCurrentPlayerID = current
        }
        guard let before else { return } // seed only on the first snapshot
        let actorID = duelActor(before: before, after: duel)
        detectDuelNotices(before: before, after: duel, snapshot: snapshot, actorID: actorID)
        buildFlights(before: before, after: duel, actorID: actorID)
    }

    /// The player who acted: the one whose purchased-card count grew (a purchase),
    /// otherwise the player whose turn it just was (take / reserve / privilege /
    /// replenish). Reused by both notices and flights so they always agree.
    private func duelActor(before: DuelClientSnapshot, after: DuelClientSnapshot) -> UUID? {
        if let grew = after.players.first(where: { p in
            p.purchasedCards.count > (before.players.first { $0.id == p.id }?.purchasedCards.count ?? p.purchasedCards.count)
        }) {
            return grew.id
        }
        return lastCurrentPlayerID
    }

    /// Announces steal / 再来一回合 on every player's screen. Both only ever result
    /// from a purchase; a steal is unambiguous because during someone else's turn the
    /// victim can only lose tokens by being stolen from.
    private func detectDuelNotices(
        before: DuelClientSnapshot,
        after: DuelClientSnapshot,
        snapshot: ClientGameSnapshot,
        actorID: UUID?
    ) {
        guard let actorID,
              let beforeActor = before.players.first(where: { $0.id == actorID }),
              let afterActor = after.players.first(where: { $0.id == actorID }),
              afterActor.purchasedCards.count > beforeActor.purchasedCards.count
        else { return }
        let actorName = snapshot.players.first { $0.id == actorID }?.nickname ?? ""
        let isLocalActor = actorID == session.localID

        if let victim = after.players.first(where: { $0.id != actorID }),
           let victimBefore = before.players.first(where: { $0.id == victim.id }) {
            let stolen = DuelTokenColor.allCases.reduce(into: [DuelTokenColor: Int]()) { result, color in
                let delta = (victimBefore.tokens[color] ?? 0) - (victim.tokens[color] ?? 0)
                if delta > 0 { result[color] = delta }
            }
            if let top = stolen.max(by: { $0.value < $1.value }) {
                duelNotice = DuelActionNotice(
                    kind: .steal(color: top.key, count: stolen.values.reduce(0, +)),
                    actorName: actorName,
                    victimName: snapshot.players.first { $0.id == victim.id }?.nickname ?? "",
                    isLocalActor: isLocalActor
                )
                return
            }
        }

        if snapshot.currentPlayerID == actorID {
            duelNotice = DuelActionNotice(kind: .extraTurn, actorName: actorName, victimName: "", isLocalActor: isLocalActor)
        }
    }

    /// Builds ghost-token / card flights from the snapshot delta, mirroring the
    /// 4-player game's flight feel. Every endpoint is a persistent position so the
    /// flights resolve even though the board already shows the new state.
    private func buildFlights(before: DuelClientSnapshot, after: DuelClientSnapshot, actorID: UUID?) {
        guard before.board.count == after.board.count else { return }
        var newFlights: [DuelFlight] = []
        var newBursts: [DuelBurst] = []

        // Board cell deltas: replenished cells pop from the bag (staggered by spiral
        // order); emptied cells fly their gem to whoever took it.
        for i in after.board.indices {
            switch (before.board[i], after.board[i]) {
            case let (nil, .some(color)):
                let order = DuelRules.spiralOrder.firstIndex(of: i) ?? 0
                newFlights.append(DuelFlight(kind: .gem(color), from: .bag, to: .boardCell(i), delay: Double(order) * 0.045))
            case let (.some(color), nil):
                if let actorID {
                    newFlights.append(DuelFlight(kind: .gem(color), from: .boardCell(i), to: .token(actorID, color)))
                }
            default:
                break
            }
        }

        // Steal: the victim's lost tokens fly to the thief.
        if let actorID, let victim = after.players.first(where: { $0.id != actorID }),
           let victimBefore = before.players.first(where: { $0.id == victim.id }) {
            for color in DuelTokenColor.allCases {
                let delta = (victimBefore.tokens[color] ?? 0) - (victim.tokens[color] ?? 0)
                for _ in 0 ..< max(0, delta) {
                    newFlights.append(DuelFlight(kind: .gem(color), from: .token(victim.id, color), to: .token(actorID, color)))
                }
            }
        }

        // Card purchase / reserve: the card flies to the score / reserved area + sparkle.
        if let actorID,
           let beforeActor = before.players.first(where: { $0.id == actorID }),
           let afterActor = after.players.first(where: { $0.id == actorID }) {
            let beforePurchased = Set(beforeActor.purchasedCards.map(\.id))
            let boughtCard = afterActor.purchasedCards.first { !beforePurchased.contains($0.id) }?.card
            if let boughtCard {
                let source = marketSlotAnchor(cardID: boughtCard.id, in: before) ?? .reserved(actorID)
                newFlights.append(DuelFlight(kind: .card(boughtCard), from: source, to: .score(actorID), delay: 0.08))
                newBursts.append(DuelBurst(at: .score(actorID)))
            }
            if afterActor.reservedCardCount > beforeActor.reservedCardCount {
                if let vanished = vanishedMarketCard(before: before, after: after, excluding: boughtCard?.id) {
                    newFlights.append(DuelFlight(kind: .card(vanished.card), from: .marketSlot(vanished.tier, vanished.index), to: .reserved(actorID), delay: 0.08))
                }
                newBursts.append(DuelBurst(at: .reserved(actorID)))
            }
        }

        guard !newFlights.isEmpty || !newBursts.isEmpty else { return }
        let addedFlights = newFlights.map(\.id)
        let addedBursts = newBursts.map(\.id)
        flights.append(contentsOf: newFlights)
        bursts.append(contentsOf: newBursts)
        // Belt-and-suspenders: drop this batch even if an endpoint never resolved
        // (e.g. the card page wasn't on screen when the flight was queued).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            flights.removeAll { addedFlights.contains($0.id) }
            bursts.removeAll { addedBursts.contains($0.id) }
        }
    }

    private func marketSlotAnchor(cardID: String, in snap: DuelClientSnapshot) -> DuelAnchorID? {
        for tier in [1, 2, 3] {
            if let index = snap.market[tier]?.firstIndex(where: { $0.id == cardID }) {
                return .marketSlot(tier, index)
            }
        }
        return nil
    }

    private func vanishedMarketCard(
        before: DuelClientSnapshot,
        after: DuelClientSnapshot,
        excluding: String?
    ) -> (card: DuelJewelCard, tier: Int, index: Int)? {
        let afterIDs = Set([1, 2, 3].flatMap { after.market[$0] ?? [] }.map(\.id))
        for tier in [1, 2, 3] {
            for (index, card) in (before.market[tier] ?? []).enumerated()
            where !afterIDs.contains(card.id) && card.id != excluding {
                return (card, tier, index)
            }
        }
        return nil
    }

    private var pagePicker: some View {
        Picker("duel.page.picker", selection: $page) {
            ForEach(DuelBoardPage.allCases) { boardPage in
                Text(boardPage.titleKey).tag(boardPage)
            }
        }
        .pickerStyle(.segmented)
        .disabled(activeTutorialInteraction != nil)
    }

    private var activeTutorialInteraction: TutorialInteraction? {
        guard tutorial?.phase == .guiding else { return nil }
        return tutorial?.currentStep?.interaction
    }

    private var tutorialGuide: DuelTutorialInteractionGuide {
        DuelTutorialInteractionGuide(
            interaction: activeTutorialInteraction,
            selectedIndices: selectedIndices,
            privilegeMode: privilegeMode
        )
    }

    private func inventoryBar(for player: DuelPublicPlayerSnapshot) -> some View {
        DuelPlayerInventoryBar(
            player: player,
            isCurrent: isLocalTurn,
            deadline: session.turnDeadline,
            turnDurationSeconds: snapshot?.configuration.turnDurationSeconds
        ) { openLocalReservedCards(player) }
            .simultaneousGesture(
                TapGesture(count: DeveloperTools.unlockTapCount)
                    .onEnded {
                        guard tutorial == nil, DeveloperTools.isEnabledForCurrentBuild, session.isHost else { return }
                        developerTokens = player.tokens
                        showsDeveloperGemEditor = true
                    }
            )
    }

    @ViewBuilder private func reserveSheet(_ selection: DuelReserveSelection) -> some View {
        if let duel, let localPlayer {
            DuelReserveSheet(
                source: selection.source,
                card: selection.card,
                duel: duel,
                player: localPlayer,
                selectableGoldIndices: tutorialGuide.selectableGoldIndices
            ) { goldIndex, returns in
                guard tutorialGuide.allowsReserve(selection.card?.id, goldBoardIndex: goldIndex) else { return }
                session.submit(.duel(.reserve(
                    goldBoardIndex: goldIndex,
                    source: selection.source,
                    returning: returns
                )))
            }
        }
    }

    @ViewBuilder private func purchaseSheet(_ selection: DuelCardSelection) -> some View {
        if let duel, let localPlayer, let opponent {
            DuelPurchaseSheet(
                card: selection.card,
                source: selection.source,
                duel: duel,
                player: localPlayer,
                opponent: opponent,
                allowsPurchase: isLocalTurn
                    && duelCanPurchase(selection.card, player: localPlayer)
                    && tutorialGuide.allowsPurchase(selection.card.id),
                onPurchase: { payment, choices, returns in
                    guard tutorialGuide.allowsPurchase(selection.card.id) else { return }
                    session.submit(.duel(.purchase(
                        source: selection.source,
                        payment: payment,
                        choices: choices,
                        returning: returns
                    )))
                },
                onReserve: reserveClosure(for: selection)
            )
        }
    }

    private func openLocalReservedCards(_ player: DuelPublicPlayerSnapshot) {
        guard let duel else { return }
        var tutorialTargetID: String?
        if let interaction = activeTutorialInteraction {
            guard case let .duelPurchaseReserved(cardID) = interaction else { return }
            tutorialTargetID = cardID
        }
        let purchasableIDs = Set(duel.localReservedCards.filter { card in
            duelCanPurchase(card, player: player)
                && tutorialTargetID.map { $0 == card.id } != false
        }.map(\.id))
        reservedCardsRequest = DuelReservedCardsRequest(
            title: "duel.reserved.title",
            cards: duel.localReservedCards,
            purchasableCardIDs: isLocalTurn ? purchasableIDs : []
        )
    }

    private func openOpponentReservedCards(
        _ opponent: DuelPublicPlayerSnapshot,
        identity: PublicPlayerSnapshot
    ) {
        guard activeTutorialInteraction == nil else { return }
        reservedCardsRequest = DuelReservedCardsRequest(
            title: "game.opponent.reserved.title \(identity.nickname)",
            cards: opponent.reservedCards,
            purchasableCardIDs: [],
            isReadOnly: true
        )
    }

    @ViewBuilder private func reservedSheet(_ request: DuelReservedCardsRequest) -> some View {
        DuelReservedCardsSheet(
            title: request.title,
            cards: request.cards,
            purchasableCardIDs: request.purchasableCardIDs,
            isReadOnly: request.isReadOnly,
            showsPurchaseHighlight: snapshot?.configuration.affordableCardHighlightEnabled ?? true
        ) { card in
            guard tutorialGuide.allowsCard(card.id) else { return }
            reservedCardsRequest = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                selectedCard = DuelCardSelection(card: card, source: .reserved(cardID: card.id))
            }
        }
    }

    private func reserveClosure(for selection: DuelCardSelection) -> (() -> Void)? {
        guard isLocalTurn else { return nil }
        if case .reserved = selection.source { return nil }
        if let interaction = activeTutorialInteraction {
            guard case let .duelReserve(cardID, _) = interaction,
                  cardID == selection.card.id else { return nil }
        }
        return {
            selectedCard = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                reserveSelection = DuelReserveSelection(source: selection.source, card: selection.card)
            }
        }
    }

    private func tapBoardToken(_ index: Int) {
        guard isLocalTurn, let duel, let color = duel.board[index] else { return }
        if let selectable = tutorialGuide.selectableBoardIndices, !selectable.contains(index) { return }
        if privilegeMode {
            guard color != .gold, duel.turnStage == .privilegesAvailable else { return }
            session.submit(.duel(.spendPrivilege(boardIndex: index)))
            return
        }
        guard color != .gold else { return }
        if selectedIndices.contains(index) {
            selectedIndices.removeAll { $0 == index }
        } else {
            let candidate = selectedIndices + [index]
            selectedIndices = isValidLine(candidate) ? candidate : [index]
        }
    }

    private func prepareTake() {
        guard tutorialGuide.canConfirmTake,
              let duel, let localPlayer, !selectedIndices.isEmpty else { return }
        var available = localPlayer.tokens
        for index in selectedIndices {
            if let color = duel.board[index] { available[color, default: 0] += 1 }
        }
        let excess = max(0, available.values.reduce(0, +) - DuelRules.tokenLimit)
        if excess > 0 {
            returnDraft = DuelReturnDraft(kind: .take(selectedIndices), available: available, required: excess)
        } else {
            session.submit(.duel(.take(boardIndices: selectedIndices, returning: [:])))
        }
    }

    private func isValidLine(_ indices: [Int]) -> Bool {
        guard (1 ... 3).contains(indices.count), Set(indices).count == indices.count else { return false }
        if indices.count == 1 { return true }
        let points = indices.map { ($0 / 5, $0 % 5) }
        return [(0, 1), (1, 0), (1, 1), (1, -1)].contains { dr, dc in
            points.contains { start in
                (0 ..< points.count).allSatisfy { step in
                    let expected = (start.0 + step * dr, start.1 + step * dc)
                    return points.contains(where: { $0 == expected })
                }
            }
        }
    }
}

private struct DuelTutorialPageSynchronizer: View {
    @ObservedObject var controller: TutorialController<DuelAnchorID>
    @Binding var page: DuelBoardPage

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: synchronize)
            .onChange(of: controller.currentIndex) { _, _ in synchronize() }
    }

    private func synchronize() {
        let target: DuelBoardPage?
        switch controller.currentStep?.surface {
        case .duelTokens: target = .tokens
        case .duelCards: target = .cards
        case nil: target = nil
        }
        if let target, page != target {
            withAnimation(.snappy) { page = target }
        }
    }
}

struct DuelActionNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case extraTurn
        case steal(color: DuelTokenColor, count: Int)
    }

    let id = UUID()
    let kind: Kind
    let actorName: String
    let victimName: String
    let isLocalActor: Bool
}

/// Transient banner announcing an ability trigger (steal / 再来一回合) to every player.
struct DuelActionNoticeBanner: View {
    let notice: DuelActionNotice

    var body: some View {
        Label { Text(message) } icon: { Image(systemName: iconName) }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(background, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .accessibilityAddTraits(.isStaticText)
    }

    private var message: LocalizedStringKey {
        switch notice.kind {
        case .extraTurn:
            return notice.isLocalActor ? "duel.extraTurn.you" : "duel.extraTurn.player \(notice.actorName)"
        case let .steal(color, _):
            let gem = color.localizedName
            return notice.isLocalActor
                ? "duel.notice.stealByYou \(notice.victimName) \(gem)"
                : "duel.notice.stealFromYou \(notice.actorName) \(gem)"
        }
    }

    private var iconName: String {
        switch notice.kind {
        case .extraTurn: "arrow.clockwise.circle.fill"
        case .steal: "arrow.left.arrow.right.circle.fill"
        }
    }

    private var background: Color {
        switch notice.kind {
        case .extraTurn: .accentColor
        case .steal: Color(red: 0.82, green: 0.22, blue: 0.28)
        }
    }
}
