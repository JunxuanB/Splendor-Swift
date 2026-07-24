import Foundation

/// Splendor Duel uses a wider palette than the base game: the five gem colors
/// plus **pearl** (a cost/token resource with no bonus) and **gold** (the wild
/// joker). Kept entirely separate from the base demo's `GemColor` so the base
/// board — and its tests — stay untouched.
enum DuelColor: String, CaseIterable, Identifiable, Codable {
    case white   // 钻石
    case blue    // 蓝宝石
    case green   // 祖母绿
    case black   // 黑玛瑙
    case red     // 红宝石
    case pearl   // 珍珠
    case gold    // 黄金（万能）

    var id: String { rawValue }

    /// The five colors a card can use as its permanent bonus / discount.
    static let gemColors: [DuelColor] = [.white, .blue, .green, .black, .red]

    /// Display order for a player's resource row (gems, then pearl, then gold).
    static let resourceOrder: [DuelColor] = [.white, .blue, .green, .black, .red, .pearl, .gold]

    var displayName: String {
        switch self {
        case .white: "钻石"
        case .blue: "蓝宝石"
        case .green: "祖母绿"
        case .black: "黑玛瑙"
        case .red: "红宝石"
        case .pearl: "珍珠"
        case .gold: "黄金"
        }
    }

    var shortName: String {
        switch self {
        case .white: "白"
        case .blue: "蓝"
        case .green: "绿"
        case .black: "黑"
        case .red: "红"
        case .pearl: "珠"
        case .gold: "金"
        }
    }
}

/// The special one-shot power printed on some development / royal cards.
enum DuelAbility: String, Equatable {
    case again            // 额外一个回合
    case takeMatchingGem  // 从版图取 1 枚同色宝石
    case takePrivilege    // 获得 1 张特权
    case stealGem         // 从对手处夺取 1 枚宝石

    var displayName: String {
        switch self {
        case .again: "再行动一次"
        case .takeMatchingGem: "取 1 枚同色宝石"
        case .takePrivilege: "获得 1 张特权"
        case .stealGem: "夺取对手 1 枚宝石"
        }
    }

    var iconName: String {
        switch self {
        case .again: "arrow.clockwise"
        case .takeMatchingGem: "hand.point.up.left.fill"
        case .takePrivilege: "scroll.fill"
        case .stealGem: "arrow.left.arrow.right"
        }
    }
}

struct DuelCard: Identifiable, Equatable {
    let id: String
    let level: Int              // 1, 2, 3
    /// The permanent bonus color, or `nil` when the card grants a wild bonus.
    let bonus: DuelColor?
    let isWildBonus: Bool
    let points: Int
    let crowns: Int             // 0...2
    let cost: [DuelColor: Int]  // may include .pearl
    let ability: DuelAbility?

    var bonusDescription: String {
        if isWildBonus { return "任意色" }
        return bonus?.displayName ?? "无"
    }
}

struct DuelRoyal: Identifiable, Equatable {
    let id: String
    let name: String
    let points: Int
    let ability: DuelAbility?
}

/// A single space on the 5×5 gem board. `token == nil` means the space is empty.
struct DuelBoardCell: Identifiable, Equatable {
    let index: Int          // 0...24
    var token: DuelColor?

    var id: Int { index }
    var row: Int { index / 5 }
    var col: Int { index % 5 }
}

struct DuelPlayerSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let isBot: Bool
    var points: Int
    var crowns: Int
    var bonuses: [DuelColor: Int]      // permanent discounts, gem colors only
    var colorPoints: [DuelColor: Int]  // prestige earned per color (single-color win)
    var tokens: [DuelColor: Int]       // includes .pearl and .gold
    var privileges: Int
    var reservedCount: Int

    var developmentCardCount: Int { bonuses.values.reduce(0, +) }
    var tokenCount: Int { tokens.values.reduce(0, +) }

    /// Highest prestige concentrated in a single color — one of the three win tracks.
    var topColorPoints: Int { colorPoints.values.max() ?? 0 }
}

enum DuelSheet: Identifiable {
    case card(DuelCard)
    case royal(DuelRoyal)
    case reserved(title: String, cards: [DuelCard], allowsPurchase: Bool)

    var id: String {
        switch self {
        case let .card(card): "card-\(card.id)"
        case let .royal(royal): "royal-\(royal.id)"
        case let .reserved(title, _, _): "reserved-\(title)"
        }
    }
}

enum DuelRules {
    static let targetPoints = 20
    static let targetCrowns = 10
    static let targetColorPoints = 10
    static let maxTokens = 10
    static let maxReserved = 3
    static let boardSize = 5   // 5×5
    static let totalPrivileges = 3
    static let totalTokens = 25

    /// The full token supply: 4 of each gem, 3 pearls, 2 gold — 25 in total.
    static let tokenSupply: [DuelColor: Int] = [
        .white: 4, .blue: 4, .green: 4, .black: 4, .red: 4, .pearl: 3, .gold: 2,
    ]
}
