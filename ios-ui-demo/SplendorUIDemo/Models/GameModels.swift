import Foundation

enum GemColor: String, CaseIterable, Codable, Identifiable {
    case diamond
    case sapphire
    case emerald
    case ruby
    case onyx
    case gold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diamond: "钻石"
        case .sapphire: "蓝宝石"
        case .emerald: "祖母绿"
        case .ruby: "红宝石"
        case .onyx: "黑玛瑙"
        case .gold: "黄金"
        }
    }

    var shortName: String {
        switch self {
        case .diamond: "白"
        case .sapphire: "蓝"
        case .emerald: "绿"
        case .ruby: "红"
        case .onyx: "黑"
        case .gold: "金"
        }
    }
}

enum PlayerKind: String, Codable {
    case human
    case bot
}

struct DevelopmentCard: Identifiable, Equatable {
    let id: String
    let level: Int
    let prestige: Int
    let bonus: GemColor
    let costs: [GemColor: Int]
}

struct NobleTile: Identifiable, Equatable {
    let id: String
    let name: String
    let prestige: Int
    let requirements: [GemColor: Int]
}

struct PlayerSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: PlayerKind
    let prestige: Int
    let reservedCards: Int
    let permanentBonuses: [GemColor: Int]
    let tokens: [GemColor: Int]

    var developmentCardCount: Int {
        permanentBonuses.values.reduce(0, +)
    }

    var tokenCount: Int {
        tokens.values.reduce(0, +)
    }
}

enum DemoSheet: Identifiable, Equatable {
    case developmentCard(DevelopmentCard)
    case noble(NobleTile)
    case reservedCards(title: String, cards: [DevelopmentCard], allowsPurchase: Bool)

    var id: String {
        switch self {
        case let .developmentCard(card): "card-\(card.id)"
        case let .noble(noble): "noble-\(noble.id)"
        case let .reservedCards(title, _, _): "reserved-cards-\(title)"
        }
    }
}
