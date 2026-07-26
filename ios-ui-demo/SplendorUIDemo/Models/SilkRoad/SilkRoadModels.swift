import Foundation

enum SilkRoadCardSource: String, Codable {
    case base
    case silkRoad

    var displayName: String {
        switch self {
        case .base: "基础牌"
        case .silkRoad: "丝绸之路牌"
        }
    }
}

enum SilkRoadEffect: String, CaseIterable, Equatable {
    case virtualGold
    case doubleBonus
    case freeLowerCard

    var title: String {
        switch self {
        case .virtualGold: "虚拟黄金"
        case .doubleBonus: "双重奖励"
        case .freeLowerCard: "免费取得低阶牌"
        }
    }

    var iconName: String {
        switch self {
        case .virtualGold: "seal.fill"
        case .doubleBonus: "plus.square.on.square"
        case .freeLowerCard: "gift.fill"
        }
    }

    var ruleText: String {
        switch self {
        case .virtualGold:
            "此牌可以在之后的购买中作为 2 枚临时黄金使用。"
        case .doubleBonus:
            "此牌提供 2 枚所示颜色的永久奖励。"
        case .freeLowerCard:
            "购入后可以免费取得一张更低等级的发展卡。"
        }
    }
}

struct SilkRoadCard: Identifiable, Equatable {
    let id: String
    let level: Int
    let source: SilkRoadCardSource
    let prestige: Int
    let bonus: GemColor?
    let costs: [GemColor: Int]
    let effect: SilkRoadEffect?
}

struct SilkRoadMarketRow: Equatable {
    let level: Int
    let baseCards: [SilkRoadCard]
    let silkRoadCard: SilkRoadCard
}

enum SilkRoadSheet: Identifiable, Equatable {
    case card(SilkRoadCard)
    case reserved
    case rules

    var id: String {
        switch self {
        case let .card(card): "card-\(card.id)"
        case .reserved: "reserved"
        case .rules: "rules"
        }
    }
}

