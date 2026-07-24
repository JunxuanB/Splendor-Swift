import Combine
import Foundation
import SwiftUI

/// Local, fake-data driven state for the Splendor Duel UI demo. Mirrors the
/// interaction surface of `DemoGameState` (selection, buy/reserve, feedback,
/// flight animations) but for Duel's board: a 5×5 token grid with line-based
/// gem taking, privileges, a paged card pyramid and three win tracks.
@MainActor
final class DuelGameState: ObservableObject {
    // Board
    @Published private(set) var board: [DuelBoardCell]
    @Published private(set) var selection: [Int] = []      // ordered board indices
    @Published private(set) var privilegeMode = false
    @Published private(set) var privilegesOnBoard: Int

    // Cards
    @Published private(set) var market: [Int: [DuelCard]]   // tier 1...3
    @Published private(set) var deckCounts: [Int: Int]
    @Published private(set) var royals: [DuelRoyal]
    @Published private(set) var reservedCards: [DuelCard]
    @Published private(set) var opponentReservedCards: [DuelCard]

    // Players
    @Published private(set) var player: DuelPlayerSnapshot
    @Published private(set) var opponent: DuelPlayerSnapshot
    @Published private(set) var isLocalTurn = true

    /// How many royal cards the player may currently choose (earned by crossing
    /// the 3- and 6-crown thresholds). Selection is manual.
    @Published private(set) var pendingRoyalPicks = 0

    // Presentation
    @Published var activeSheet: DuelSheet?
    @Published var feedbackMessage: String?
    @Published var flights: [DuelFlight] = []
    @Published var bursts: [DuelBurst] = []

    init() {
        board = Self.makeBoard()
        privilegesOnBoard = 1
        market = Self.makeMarket()
        deckCounts = [1: 25, 2: 21, 3: 15]
        royals = Self.makeRoyals()
        reservedCards = [
            DuelCard(id: "reserved-seed", level: 2, bonus: .black, isWildBonus: false, points: 1, crowns: 1,
                     cost: [.blue: 3, .white: 2], ability: nil),
        ]
        opponentReservedCards = [
            DuelCard(id: "opp-reserved-1", level: 1, bonus: .green, isWildBonus: false, points: 0, crowns: 1,
                     cost: [.red: 2, .black: 1], ability: nil),
            DuelCard(id: "opp-reserved-2", level: 3, bonus: .blue, isWildBonus: false, points: 3, crowns: 1,
                     cost: [.white: 3, .green: 3, .pearl: 2], ability: .again),
        ]
        player = Self.makeLocalPlayer()
        opponent = Self.makeOpponent()
    }

    // MARK: - Derived

    var hasSelection: Bool { !selection.isEmpty }

    var selectedColors: [DuelColor] { selection.compactMap { board[$0].token } }

    var canConfirmTake: Bool { hasSelection && isLocalTurn }

    var pointsProgress: Int { player.points }
    var crownsProgress: Int { player.crowns }
    var colorProgress: Int { player.topColorPoints }

    // MARK: - Board coordinates & line validation

    private func coord(_ index: Int) -> (r: Int, c: Int) { (index / 5, index % 5) }

    /// A set of board spaces is takeable when every space holds a non-gold token
    /// and (for 2–3 tokens) they sit contiguously along one straight orientation
    /// — horizontal, vertical, or either diagonal.
    func isValidLine(_ indices: [Int]) -> Bool {
        guard !indices.isEmpty, indices.count <= 3 else { return false }
        for i in indices {
            guard let token = board[i].token, token != .gold else { return false }
        }
        if indices.count == 1 { return true }

        let points = indices.map(coord)
        let orientations = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dr, dc) in orientations {
            let sorted = points.sorted { ($0.r * dr + $0.c * dc) < ($1.r * dr + $1.c * dc) }
            var contiguous = true
            for k in 1 ..< sorted.count where sorted[k].r - sorted[k - 1].r != dr || sorted[k].c - sorted[k - 1].c != dc {
                contiguous = false
                break
            }
            if contiguous { return true }
        }
        return false
    }

    /// Whether `index` may extend the current selection into a still-valid line.
    func canAdd(_ index: Int) -> Bool {
        guard board[index].token != nil, board[index].token != .gold else { return false }
        guard !selection.contains(index) else { return false }
        return isValidLine(selection + [index])
    }

    func isSelected(_ index: Int) -> Bool { selection.contains(index) }

    // MARK: - Board interaction

    func tapCell(_ index: Int) {
        guard isLocalTurn else { return }
        guard let token = board[index].token else { return }

        if privilegeMode {
            guard token != .gold else {
                showFeedback("权杖不能拿取黄金")
                return
            }
            takeSingleWithPrivilege(index)
            return
        }

        guard token != .gold else {
            showFeedback("黄金只能通过预留发展卡获得")
            return
        }

        if selection.contains(index) {
            var next = selection
            next.removeAll { $0 == index }
            selection = isValidLine(next) ? next : []
        } else if canAdd(index) {
            selection.append(index)
        } else {
            // Start a fresh line from the tapped space.
            selection = [index]
        }
    }

    func cancelSelection() {
        selection = []
    }

    func confirmTake() {
        guard canConfirmTake else { return }
        let taken = selection
        let colors = selectedColors
        selection = []

        var index = 0
        for boardIndex in taken {
            guard let color = board[boardIndex].token else { continue }
            board[boardIndex].token = nil
            flights.append(
                DuelFlight(
                    kind: .gem(color),
                    from: .boardCell(boardIndex),
                    to: .playerToken(color),
                    delay: Double(index) * 0.08
                )
            )
            index += 1
        }

        let sameColor = Set(colors).count == 1 && colors.count == 3
        let pearlCount = colors.filter { $0 == .pearl }.count
        if sameColor {
            grantOpponentPrivilege()
            showFeedback("拿取 3 枚同色，对手获得 1 个权杖")
        } else if pearlCount >= 2 {
            grantOpponentPrivilege()
            showFeedback("拿取 \(pearlCount) 枚珍珠，对手获得 1 个权杖")
        } else {
            showFeedback("已拿取 \(colors.count) 枚宝石")
        }
        scheduleFlightCleanup()
    }

    // MARK: - Privileges

    func togglePrivilegeMode() {
        guard isLocalTurn else { return }
        if privilegeMode {
            privilegeMode = false
            return
        }
        guard player.privileges > 0 else {
            showFeedback("暂无可用权杖")
            return
        }
        selection = []
        privilegeMode = true
    }

    private func takeSingleWithPrivilege(_ index: Int) {
        guard let color = board[index].token else { return }
        board[index].token = nil
        player.privileges -= 1
        privilegesOnBoard += 1
        privilegeMode = false
        flights.append(DuelFlight(kind: .gem(color), from: .boardCell(index), to: .playerToken(color)))
        showFeedback("使用权杖，取得 1 枚\(color.displayName)")
        scheduleFlightCleanup()
    }

    private func grantOpponentPrivilege() {
        if privilegesOnBoard > 0 {
            privilegesOnBoard -= 1
            opponent.privileges += 1
        }
    }

    // MARK: - Refill

    /// Center-out spiral order of the 25 spaces — the route the board refills along
    /// per the real Duel rules. Empty spaces are filled following this sequence.
    static let spiralOrder: [Int] = computeSpiralOrder()

    private static func computeSpiralOrder() -> [Int] {
        let n = DuelRules.boardSize
        var result: [Int] = []
        var seen = Set<Int>()
        var r = n / 2, c = n / 2
        func place(_ rr: Int, _ cc: Int) {
            guard rr >= 0, rr < n, cc >= 0, cc < n else { return }
            let idx = rr * n + cc
            if seen.insert(idx).inserted { result.append(idx) }
        }
        place(r, c)
        let dirs = [(1, 0), (0, -1), (-1, 0), (0, 1)] // down, left, up, right
        var d = 0
        var step = 1
        while result.count < n * n {
            for _ in 0 ..< 2 {
                let (dr, dc) = dirs[d % 4]
                for _ in 0 ..< step {
                    r += dr; c += dc
                    place(r, c)
                }
                d += 1
            }
            step += 1
        }
        return result
    }

    /// Tokens currently on the board.
    var onBoardCount: Int { board.reduce(0) { $0 + ($1.token == nil ? 0 : 1) } }

    /// The bag holds every token not on the board and not held by a player —
    /// mostly gems spent buying cards, which return to the bag. Conservation:
    /// board + both players' tokens + bag == 25.
    func bagContents() -> [DuelColor] {
        var remaining = DuelRules.tokenSupply
        for cell in board {
            if let token = cell.token { remaining[token, default: 0] -= 1 }
        }
        for (color, count) in player.tokens { remaining[color, default: 0] -= count }
        for (color, count) in opponent.tokens { remaining[color, default: 0] -= count }
        return DuelColor.resourceOrder.flatMap { color in
            Array(repeating: color, count: max(0, remaining[color, default: 0]))
        }
    }

    var bagRemaining: Int { bagContents().count }

    /// Spaces that a refill would actually fill — empties along the spiral, but no
    /// more than the bag holds. The board won't always fill (players hold the rest).
    func refillPlan() -> [Int] {
        let empties = Self.spiralOrder.filter { board[$0].token == nil }
        return Array(empties.prefix(bagRemaining))
    }

    func refillBoard() {
        guard isLocalTurn else { return }
        guard board.contains(where: { $0.token == nil }) else {
            showFeedback("版图已满，无需补充")
            return
        }
        let plan = refillPlan()
        guard !plan.isEmpty else {
            showFeedback("袋子已空，无法补充")
            return
        }

        // Refilling hands the opponent a privilege (from the central pool).
        if privilegesOnBoard > 0 {
            privilegesOnBoard -= 1
            opponent.privileges += 1
            showFeedback("补充版图，对手获得 1 个权杖")
        } else {
            showFeedback("已补充版图")
        }

        // Drop tokens in one-by-one along the spiral route.
        let colors = bagContents()
        for (i, slot) in plan.enumerated() {
            let color = colors[i]
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.10) { [weak self] in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
                    self?.board[slot].token = color
                }
            }
        }
    }

    // MARK: - Cards

    func open(_ card: DuelCard) { activeSheet = .card(card) }
    func open(_ royal: DuelRoyal) { activeSheet = .royal(royal) }

    func openReservedCards() {
        activeSheet = .reserved(title: "预留的发展卡", cards: reservedCards, allowsPurchase: true)
    }

    func openOpponentReservedCards() {
        activeSheet = .reserved(
            title: "\(opponent.name)的预留牌",
            cards: opponentReservedCards,
            allowsPurchase: false
        )
    }

    func canPurchase(_ card: DuelCard) -> Bool {
        var gold = player.tokens[.gold, default: 0]
        for (color, required) in card.cost {
            let bonus = color == .pearl ? 0 : player.bonuses[color, default: 0]
            let available = bonus + player.tokens[color, default: 0]
            gold -= max(0, required - available)
            if gold < 0 { return false }
        }
        return true
    }

    func buy(_ card: DuelCard) {
        activeSheet = nil
        removeFromMarket(card)
        showFeedback("已购买发展卡（演示）")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.flights.append(
                DuelFlight(
                    kind: .cardBuy(card),
                    from: .marketCard(card.id),
                    to: card.isWildBonus ? .playerScore : .playerToken(card.bonus ?? .white)
                )
            )
            self?.scheduleFlightCleanup()
        }
    }

    func reserve(_ card: DuelCard) {
        activeSheet = nil
        guard reservedCards.count < DuelRules.maxReserved else {
            showFeedback("预留已满（最多 3 张）")
            return
        }
        removeFromMarket(card)
        showFeedback("已预留，并获得 1 枚黄金")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.flights.append(
                DuelFlight(kind: .cardReserve(card), from: .marketCard(card.id), to: .reservedArea)
            )
            self?.scheduleFlightCleanup()
        }
    }

    func reserveFromDeck(level: Int) {
        guard isLocalTurn else { return }
        guard reservedCards.count < DuelRules.maxReserved else {
            showFeedback("预留已满（最多 3 张）")
            return
        }
        guard let card = drawReplacement(level: level) else {
            showFeedback("该牌库已空")
            return
        }
        reservedCards.append(card)
        player.tokens[.gold, default: 0] += 1
        showFeedback("已从牌库顶预留，并获得 1 枚黄金")
    }

    private func removeFromMarket(_ card: DuelCard) {
        guard var row = market[card.level], let slot = row.firstIndex(of: card) else { return }
        if let replacement = drawReplacement(level: card.level) {
            row[slot] = replacement
        } else {
            row.remove(at: slot)
        }
        market[card.level] = row
    }

    private func drawReplacement(level: Int) -> DuelCard? {
        guard deckCounts[level, default: 0] > 0 else { return nil }
        deckCounts[level, default: 0] -= 1
        let n = deckCounts[level, default: 0]
        return DuelCard(
            id: "\(level)-refill-\(n)",
            level: level,
            bonus: DuelColor.gemColors[n % DuelColor.gemColors.count],
            isWildBonus: false,
            points: level,
            crowns: level == 3 ? 1 : 0,
            cost: [DuelColor.gemColors[(n + 1) % 5]: level + 1, .pearl: level == 3 ? 1 : 0].filter { $0.value > 0 },
            ability: nil
        )
    }

    // MARK: - Flight resolution

    func land(_ flight: DuelFlight) {
        switch flight.kind {
        case let .gem(color):
            player.tokens[color, default: 0] += 1
        case let .cardBuy(card):
            applyPurchase(card)
        case let .cardReserve(card):
            reservedCards.append(card)
            player.tokens[.gold, default: 0] += 1
        }
        flights.removeAll { $0.id == flight.id }
    }

    private func applyPurchase(_ card: DuelCard) {
        if let bonus = card.bonus, !card.isWildBonus {
            player.bonuses[bonus, default: 0] += 1
            if card.points > 0 { player.colorPoints[bonus, default: 0] += card.points }
        }
        if card.points > 0 {
            player.points += card.points
            bursts.append(DuelBurst(at: .playerScore))
        }
        if card.crowns > 0 {
            let before = player.crowns
            player.crowns += card.crowns
            registerCrownGain(crownsBefore: before)
        }
        evaluateWin()
    }

    /// Crossing 3 or 6 crowns earns the right to *choose* a royal card — the player
    /// picks manually rather than the game auto-assigning one.
    private func registerCrownGain(crownsBefore: Int) {
        for threshold in [3, 6] where crownsBefore < threshold && player.crowns >= threshold {
            guard !royals.isEmpty else { continue }
            pendingRoyalPicks += 1
            showFeedback("达到 \(threshold) 王冠，可选择 1 张皇室卡")
        }
    }

    func claimRoyal(_ royal: DuelRoyal) {
        guard pendingRoyalPicks > 0, let index = royals.firstIndex(of: royal) else { return }
        royals.remove(at: index)
        pendingRoyalPicks -= 1
        activeSheet = nil
        player.points += royal.points
        bursts.append(DuelBurst(at: .playerScore))
        showFeedback("已选择皇室卡 +\(royal.points) 分")
        evaluateWin()
    }

    private func evaluateWin() {
        if player.points >= DuelRules.targetPoints
            || player.crowns >= DuelRules.targetCrowns
            || player.topColorPoints >= DuelRules.targetColorPoints {
            showFeedback("达成胜利条件（演示）")
        }
    }

    func endBurst(_ burst: DuelBurst) {
        bursts.removeAll { $0.id == burst.id }
    }

    private func scheduleFlightCleanup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.flights.removeAll()
        }
    }

    // MARK: - Feedback

    func showFeedback(_ message: String) { feedbackMessage = message }

    func clearFeedback(ifMatching message: String) {
        if feedbackMessage == message { feedbackMessage = nil }
    }

    // MARK: - Debug

    func debugTakeLine() { selection = [6, 7, 8]; confirmTake() }
    func debugBuy() { if let card = market[2]?.first { buy(card) } }
    func debugCrown() {
        let before = player.crowns
        player.crowns += 1
        bursts.append(DuelBurst(at: .playerScore))
        registerCrownGain(crownsBefore: before)
    }
}

// MARK: - Fake data

private extension DuelGameState {
    // Token counts conserve the 25-token supply: on-board (18) + held (5) + bag (2).
    // Several empty spaces plus a small bag means a refill can't fully fill the board.
    static func makeBoard() -> [DuelBoardCell] {
        let layout: [DuelColor?] = [
            .white, .blue, nil, .red, .black,
            .white, .blue, .green, .red, .black,
            .white, .blue, .green, .red, nil,
            .white, .blue, .green, nil, nil,
            nil, nil, .pearl, .gold, nil,
        ]
        return layout.enumerated().map { DuelBoardCell(index: $0.offset, token: $0.element) }
    }

    static func makeMarket() -> [Int: [DuelCard]] {
        [
            1: [
                DuelCard(id: "l1-1", level: 1, bonus: .white, isWildBonus: false, points: 0, crowns: 0,
                         cost: [.blue: 2, .white: 1], ability: nil),
                DuelCard(id: "l1-2", level: 1, bonus: .green, isWildBonus: false, points: 0, crowns: 1,
                         cost: [.red: 3], ability: nil),
                DuelCard(id: "l1-3", level: 1, bonus: .red, isWildBonus: false, points: 1, crowns: 0,
                         cost: [.black: 2, .pearl: 1], ability: nil),
                DuelCard(id: "l1-4", level: 1, bonus: .blue, isWildBonus: false, points: 0, crowns: 0,
                         cost: [.green: 2, .white: 1], ability: .takeMatchingGem),
                DuelCard(id: "l1-5", level: 1, bonus: .black, isWildBonus: false, points: 0, crowns: 0,
                         cost: [.white: 2, .red: 1], ability: .takePrivilege),
            ],
            2: [
                DuelCard(id: "l2-1", level: 2, bonus: .blue, isWildBonus: false, points: 1, crowns: 1,
                         cost: [.green: 3, .black: 2], ability: nil),
                DuelCard(id: "l2-2", level: 2, bonus: .red, isWildBonus: false, points: 2, crowns: 0,
                         cost: [.white: 4, .pearl: 1], ability: nil),
                DuelCard(id: "l2-3", level: 2, bonus: nil, isWildBonus: true, points: 0, crowns: 1,
                         cost: [.blue: 3, .red: 2], ability: .again),
                DuelCard(id: "l2-4", level: 2, bonus: .green, isWildBonus: false, points: 1, crowns: 0,
                         cost: [.black: 4, .pearl: 2], ability: .stealGem),
            ],
            3: [
                DuelCard(id: "l3-1", level: 3, bonus: .black, isWildBonus: false, points: 3, crowns: 2,
                         cost: [.white: 5, .red: 3, .pearl: 1], ability: nil),
                DuelCard(id: "l3-2", level: 3, bonus: .white, isWildBonus: false, points: 4, crowns: 0,
                         cost: [.green: 6, .pearl: 2], ability: nil),
                DuelCard(id: "l3-3", level: 3, bonus: .red, isWildBonus: false, points: 2, crowns: 2,
                         cost: [.blue: 4, .black: 4], ability: .again),
            ],
        ]
    }

    // Each royal is either "2 分 + 技能" or a flat "3 分" — 3 with skills, 1 without.
    static func makeRoyals() -> [DuelRoyal] {
        [
            DuelRoyal(id: "r1", name: "再度加冕", points: 2, ability: .again),
            DuelRoyal(id: "r2", name: "掠夺者", points: 2, ability: .stealGem),
            DuelRoyal(id: "r3", name: "召集权杖", points: 2, ability: .takePrivilege),
            DuelRoyal(id: "r4", name: "庄严盛典", points: 3, ability: nil),
        ]
    }

    static func makeLocalPlayer() -> DuelPlayerSnapshot {
        DuelPlayerSnapshot(
            id: "local",
            name: "你",
            isBot: false,
            points: 6,
            crowns: 2,
            bonuses: [.white: 1, .blue: 2, .green: 1, .black: 0, .red: 1],
            colorPoints: [.blue: 3, .red: 3],
            tokens: [.white: 0, .blue: 0, .green: 0, .black: 1, .red: 0, .pearl: 1, .gold: 1],
            privileges: 1,
            reservedCount: 1
        )
    }

    static func makeOpponent() -> DuelPlayerSnapshot {
        DuelPlayerSnapshot(
            id: "rival",
            name: "对手 · 罗宾",
            isBot: false,
            points: 5,
            crowns: 3,
            bonuses: [.white: 0, .blue: 1, .green: 2, .black: 1, .red: 0],
            colorPoints: [.green: 4],
            tokens: [.white: 0, .blue: 0, .green: 0, .black: 1, .red: 1, .pearl: 0, .gold: 0],
            privileges: 1,
            reservedCount: 2
        )
    }
}
