import Foundation

/// A host-confirmed, presentation-only description of an accepted game action.
/// It is sent before the resulting snapshot so every transport can play the same
/// board animation while the source card, noble, or token is still visible.
public struct GameAnimationEvent: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case take(tokens: [GemColor: Int])
        case reserve(source: CardSource, card: DevelopmentCard?)
        case purchase(source: CardSource, card: DevelopmentCard, noble: NobleTile?)
        case pass
    }

    public let id: UUID
    public let revision: Int
    public let playerID: UUID
    public let kind: Kind

    public init(
        id: UUID = UUID(),
        revision: Int,
        playerID: UUID,
        kind: Kind
    ) {
        self.id = id
        self.revision = revision
        self.playerID = playerID
        self.kind = kind
    }

    /// Keep the old snapshot on screen until its ghosts have reached their
    /// destinations, matching the demo's mutate-on-landing presentation.
    public var snapshotDelay: TimeInterval {
        switch kind {
        case .take: 0.8
        case .reserve: 0.9
        case let .purchase(_, _, noble): noble == nil ? 0.9 : 1.5
        case .pass: 0
        }
    }
}
