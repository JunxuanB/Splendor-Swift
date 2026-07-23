import Combine
import Foundation

@MainActor
final class DemoGameState: ObservableObject {
    @Published private(set) var opponentIndex = 0
    @Published private(set) var bank: [GemColor: Int]
    @Published private(set) var playerTokens: [GemColor: Int]
    @Published private(set) var selectedGems: [GemColor: Int] = [:]
    @Published var activeSheet: DemoSheet?
    @Published var feedbackMessage: String?

    let targetPrestige = 15
    let playerPrestige = 7
    let playerBonuses: [GemColor: Int]
    let reservedCards: [DevelopmentCard]
    let opponents: [PlayerSnapshot]
    let opponentReservedCards: [String: [DevelopmentCard]]
    let nobles: [NobleTile]
    let market: [[DevelopmentCard]]
    let deckRemaining = [1: 30, 2: 22, 3: 14]

    init() {
        bank = [
            .diamond: 5, .sapphire: 4, .emerald: 5,
            .ruby: 3, .onyx: 4, .gold: 5
        ]
        playerTokens = [
            .diamond: 1, .sapphire: 0, .emerald: 2,
            .ruby: 1, .onyx: 0, .gold: 1
        ]
        playerBonuses = [
            .diamond: 2, .sapphire: 1, .emerald: 3,
            .ruby: 1, .onyx: 2
        ]
        let demoMarket = Self.makeMarket()
        market = demoMarket
        reservedCards = [demoMarket[0][1], demoMarket[1][0]]
        let demoOpponents = Self.makeOpponents()
        opponents = demoOpponents
        opponentReservedCards = Dictionary(uniqueKeysWithValues: demoOpponents.enumerated().map { index, opponent in
            let cards = (0..<opponent.reservedCards).map { offset in
                let level = (index + offset) % demoMarket.count
                let card = (index * 2 + offset) % demoMarket[level].count
                return demoMarket[level][card]
            }
            return (opponent.id, cards)
        })
        nobles = Self.makeNobles()
    }

    var currentOpponent: PlayerSnapshot {
        opponents[opponentIndex]
    }

    var hasGemSelection: Bool {
        !selectedGems.isEmpty
    }

    var selectedGemTotal: Int {
        selectedGems.values.reduce(0, +)
    }

    var playerReservedCards: Int {
        reservedCards.count
    }

    func showNextOpponent() {
        guard !opponents.isEmpty else { return }
        opponentIndex = (opponentIndex + 1) % opponents.count
    }

    func showPreviousOpponent() {
        guard !opponents.isEmpty else { return }
        opponentIndex = (opponentIndex - 1 + opponents.count) % opponents.count
    }

    func toggleGem(_ gem: GemColor) {
        guard gem != .gold, bank[gem, default: 0] > 0 else { return }
        let current = selectedGems[gem, default: 0]
        let maximum = min(2, bank[gem, default: 0])
        if current < maximum {
            selectedGems[gem] = current + 1
        } else {
            selectedGems.removeValue(forKey: gem)
        }
    }

    func cancelGemSelection() {
        selectedGems.removeAll()
    }

    func confirmGemSelection() {
        guard hasGemSelection else { return }
        for (gem, amount) in selectedGems where bank[gem, default: 0] >= amount {
            bank[gem, default: 0] -= amount
            playerTokens[gem, default: 0] += amount
        }
        let amount = selectedGemTotal
        selectedGems.removeAll()
        showFeedback("已拿取 \(amount) 枚宝石")
    }

    func open(_ card: DevelopmentCard) {
        activeSheet = .developmentCard(card)
    }

    func open(_ noble: NobleTile) {
        activeSheet = .noble(noble)
    }

    func openReservedCards() {
        activeSheet = .reservedCards(
            title: "预留的发展卡",
            cards: reservedCards,
            allowsPurchase: true
        )
    }

    func openReservedCards(for opponent: PlayerSnapshot) {
        activeSheet = .reservedCards(
            title: "\(opponent.name)的预留牌",
            cards: opponentReservedCards[opponent.id, default: []],
            allowsPurchase: false
        )
    }

    func canPurchase(_ card: DevelopmentCard) -> Bool {
        var availableGold = playerTokens[.gold, default: 0]
        for gem in GemColor.allCases where gem != .gold {
            let required = card.costs[gem, default: 0]
            let available = playerBonuses[gem, default: 0] + playerTokens[gem, default: 0]
            availableGold -= max(0, required - available)
            if availableGold < 0 { return false }
        }
        return true
    }

    func performCardAction(_ action: String) {
        activeSheet = nil
        showFeedback(action)
    }

    func showFeedback(_ message: String) {
        feedbackMessage = message
    }

    func clearFeedback(ifMatching message: String) {
        if feedbackMessage == message {
            feedbackMessage = nil
        }
    }
}

private extension DemoGameState {
    static func makeOpponents() -> [PlayerSnapshot] {
        let names = ["林墨", "小满", "Aurora", "阿澈", "Nova", "棋手六号"]
        return names.enumerated().map { index, name in
            PlayerSnapshot(
                id: "opponent-\(index)",
                name: name,
                kind: index == 5 ? .bot : .human,
                prestige: [9, 5, 11, 6, 3, 8][index],
                reservedCards: [1, 0, 2, 0, 1, 1][index],
                permanentBonuses: [
                    .diamond: (index + 2) % 4,
                    .sapphire: (index + 1) % 3,
                    .emerald: (index + 3) % 4,
                    .ruby: index % 3,
                    .onyx: (index + 2) % 3
                ],
                tokens: [
                    .diamond: index % 2,
                    .sapphire: (index + 1) % 2,
                    .emerald: index % 3 == 0 ? 2 : 0,
                    .ruby: (index + 1) % 3 == 0 ? 2 : 1,
                    .onyx: index % 2,
                    .gold: index % 3 == 0 ? 1 : 0
                ]
            )
        }
    }

    static func makeNobles() -> [NobleTile] {
        [
            NobleTile(id: "n1", name: "佛罗伦萨的贵族", prestige: 3, requirements: [.diamond: 4, .sapphire: 4]),
            NobleTile(id: "n2", name: "威尼斯的贵族", prestige: 3, requirements: [.sapphire: 3, .emerald: 3, .ruby: 3]),
            NobleTile(id: "n3", name: "东方的贵族", prestige: 3, requirements: [.diamond: 3, .onyx: 3, .ruby: 3]),
            NobleTile(id: "n4", name: "宫廷的贵族", prestige: 3, requirements: [.emerald: 4, .onyx: 4]),
            NobleTile(id: "n5", name: "王室的贵族", prestige: 3, requirements: [.diamond: 3, .sapphire: 3, .onyx: 3])
        ]
    }

    static func makeMarket() -> [[DevelopmentCard]] {
        [
            [
                DevelopmentCard(id: "l1-1", level: 1, prestige: 0, bonus: .diamond, costs: [.sapphire: 1, .emerald: 2, .ruby: 1, .onyx: 1]),
                DevelopmentCard(id: "l1-2", level: 1, prestige: 0, bonus: .sapphire, costs: [.diamond: 1, .emerald: 1, .ruby: 2, .onyx: 1]),
                DevelopmentCard(id: "l1-3", level: 1, prestige: 1, bonus: .emerald, costs: [.onyx: 4]),
                DevelopmentCard(id: "l1-4", level: 1, prestige: 0, bonus: .ruby, costs: [.diamond: 2, .sapphire: 1, .onyx: 2])
            ],
            [
                DevelopmentCard(id: "l2-1", level: 2, prestige: 2, bonus: .onyx, costs: [.diamond: 5, .sapphire: 3]),
                DevelopmentCard(id: "l2-2", level: 2, prestige: 1, bonus: .diamond, costs: [.sapphire: 2, .emerald: 3, .ruby: 2]),
                DevelopmentCard(id: "l2-3", level: 2, prestige: 3, bonus: .sapphire, costs: [.diamond: 6]),
                DevelopmentCard(id: "l2-4", level: 2, prestige: 2, bonus: .emerald, costs: [.sapphire: 4, .ruby: 2, .onyx: 1])
            ],
            [
                DevelopmentCard(id: "l3-1", level: 3, prestige: 4, bonus: .ruby, costs: [.diamond: 3, .ruby: 3, .onyx: 6]),
                DevelopmentCard(id: "l3-2", level: 3, prestige: 5, bonus: .onyx, costs: [.emerald: 7, .ruby: 3]),
                DevelopmentCard(id: "l3-3", level: 3, prestige: 4, bonus: .diamond, costs: [.sapphire: 6, .emerald: 3, .onyx: 3]),
                DevelopmentCard(id: "l3-4", level: 3, prestige: 3, bonus: .sapphire, costs: [.diamond: 3, .emerald: 5, .ruby: 3, .onyx: 3])
            ]
        ]
    }
}
