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

struct DuelGameBoardView: View {
    @ObservedObject var session: MatchSessionService
    let onExit: () -> Void
    let onSaveAndSuspend: () -> Void

    @State private var page: DuelBoardPage = .tokens
    @State private var selectedIndices: [Int] = []
    @State private var privilegeMode = false
    @State private var selectedCard: DuelCardSelection?
    @State private var reserveSelection: DuelReserveSelection?
    @State private var returnDraft: DuelReturnDraft?
    @State private var showsReserved = false
    @State private var showsExitConfirmation = false

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
                canPause: session.isHost && !session.isPaused && !session.isOpeningTurnSelection,
                onPause: { session.pauseGame() },
                onExit: { showsExitConfirmation = true }
            )

            if let localPlayer { DuelVictoryHeader(player: localPlayer) }
            Divider()

            GeometryReader { proxy in
                if let snapshot, let duel, let localPlayer, let opponent, let opponentIdentity {
                    let roomy = proxy.size.height >= 430
                    VStack(spacing: roomy ? 9 : 6) {
                        DuelOpponentPanel(
                            identity: opponentIdentity,
                            duelPlayer: opponent,
                            isCurrent: snapshot.currentPlayerID == opponent.id
                        )

                        Picker("duel.page.picker", selection: $page) {
                            ForEach(DuelBoardPage.allCases) { Text($0.titleKey).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        TabView(selection: $page) {
                            DuelTokenBoardSection(
                                duel: duel,
                                player: localPlayer,
                                isLocalTurn: isLocalTurn,
                                selectedIndices: $selectedIndices,
                                privilegeMode: $privilegeMode,
                                onTapToken: tapBoardToken,
                                onConfirmTake: prepareTake,
                                onReplenish: { session.submit(.duel(.replenish)) }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .tag(DuelBoardPage.tokens)

                            DuelCardBoardSection(
                                duel: duel,
                                player: localPlayer,
                                isLocalTurn: isLocalTurn,
                                showsHighlight: snapshot.configuration.affordableCardHighlightEnabled,
                                onSelectCard: { selectedCard = DuelCardSelection(card: $0, source: $1) },
                                onReserveDeck: { reserveSelection = DuelReserveSelection(source: .deck(tier: $0), card: nil) }
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
                DuelPlayerInventoryBar(player: localPlayer, isCurrent: isLocalTurn) { showsReserved = true }
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
        .sheet(isPresented: $showsReserved) { reservedSheet }
        .onChange(of: snapshot?.revision) { _, _ in
            selectedIndices = []
            privilegeMode = false
        }
        .onChange(of: snapshot?.currentPlayerID) { _, playerID in
            if playerID != session.localID {
                selectedCard = nil
                reserveSelection = nil
                returnDraft = nil
                showsReserved = false
            }
        }
        .sensoryFeedback(trigger: isLocalTurn) { old, new in !old && new ? .success : nil }
    }

    @ViewBuilder private func reserveSheet(_ selection: DuelReserveSelection) -> some View {
        if let duel, let localPlayer {
            DuelReserveSheet(
                source: selection.source,
                card: selection.card,
                duel: duel,
                player: localPlayer
            ) { goldIndex, returns in
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
                allowsPurchase: isLocalTurn && duelCanPurchase(selection.card, player: localPlayer),
                onPurchase: { payment, choices, returns in
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

    @ViewBuilder private var reservedSheet: some View {
        if let duel, let localPlayer {
            DuelReservedCardsSheet(cards: duel.localReservedCards, player: localPlayer) { card in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    selectedCard = DuelCardSelection(card: card, source: .reserved(cardID: card.id))
                }
            }
        }
    }

    private func reserveClosure(for selection: DuelCardSelection) -> (() -> Void)? {
        guard isLocalTurn else { return nil }
        if case .reserved = selection.source { return nil }
        return {
            selectedCard = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                reserveSelection = DuelReserveSelection(source: selection.source, card: selection.card)
            }
        }
    }

    private func tapBoardToken(_ index: Int) {
        guard isLocalTurn, let duel, let color = duel.board[index] else { return }
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
        guard let duel, let localPlayer, !selectedIndices.isEmpty else { return }
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
