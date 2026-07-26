import XCTest
@testable import LuminoreCore

/// Verifies the AI's core guarantee: every action a bot emits is accepted by the
/// real ruleset (never throws), and bot-only games always terminate.
final class BotControllerTests: XCTestCase {
    private let engine = RulesEngine()

    // MARK: - Participant model

    func testHumanParticipantNeverCarriesDifficulty() {
        let human = Participant(id: UUID(), nickname: "A", kind: .human, difficulty: .hard)
        XCTAssertNil(human.difficulty)
        let bot = Participant(id: UUID(), nickname: "B", kind: .bot, difficulty: .hard)
        XCTAssertEqual(bot.difficulty, .hard)
    }

    func testDifficultySurvivesCodableRoundTrip() throws {
        let bot = Participant(id: UUID(), nickname: "B", kind: .bot, difficulty: .easy)
        let data = try JSONEncoder().encode(bot)
        let decoded = try JSONDecoder().decode(Participant.self, from: data)
        XCTAssertEqual(decoded.difficulty, .easy)
    }

    // MARK: - Standard

    func testStandardBotMovesAreAlwaysLegal() {
        for difficulty in BotDifficulty.allCases {
            let outcome = playStandard(playerCount: 3, difficulty: difficulty, seed: 42)
            XCTAssertTrue(outcome.finished, "standard \(difficulty) game did not finish")
            XCTAssertGreaterThan(outcome.actions, 5)
        }
    }

    func testStandardBotDrivesTwoPlayerHardGameToAWinner() {
        let outcome = playStandard(playerCount: 2, difficulty: .hard, seed: 7)
        XCTAssertTrue(outcome.finished)
        XCTAssertFalse(outcome.winnerIDs.isEmpty)
    }

    /// Hard (look-ahead, no noise) should beat Easy (noisy, blunders) clearly over
    /// a handful of seeds. Guards against evaluation regressions like over-reserving.
    func testHardBeatsEasyInStandard() {
        var hardWins = 0
        let games = 6
        for seed in 0 ..< games {
            // Alternate seats so neither difficulty benefits from going first.
            let hardFirst = seed % 2 == 0
            let difficulties: [BotDifficulty] = hardFirst ? [.hard, .easy] : [.easy, .hard]
            let ids = [UUID(), UUID()]
            let participants = zip(ids, difficulties).map { id, d in
                Participant(id: id, nickname: "P", kind: .bot, difficulty: d)
            }
            let hardID = ids[hardFirst ? 0 : 1]
            let config = GameConfiguration(mode: .standard, targetPrestige: 15, turnDurationSeconds: nil)
            let outcome = play(participants: participants, configuration: config, seed: UInt64(seed + 1), actionCap: 4000)
            if outcome.winnerIDs == [hardID] { hardWins += 1 }
        }
        XCTAssertGreaterThanOrEqual(hardWins, 4, "hard only won \(hardWins)/\(games) vs easy")
    }

    /// A bot that over-reserves in the opening would leave the early game with many
    /// held cards and few purchases. Sanity-check the opening favours building.
    func testStandardBotDoesNotHoardReservesEarly() {
        let participants = (0 ..< 2).map {
            Participant(id: UUID(), nickname: "Bot\($0)", kind: .bot, difficulty: .hard)
        }
        let config = GameConfiguration(mode: .standard, targetPrestige: 15, turnDurationSeconds: nil)
        guard var state = try? engine.makeGame(participants: participants, configuration: config, seed: 3) else {
            return XCTFail("could not build game")
        }
        let controller = BotFactory.make(for: .standard)
        // Play the opening ~16 plies (≈8 turns each).
        for _ in 0 ..< 16 where state.status == .playing {
            let action = controller.chooseAction(state: state, playerID: state.currentPlayer.id, difficulty: .hard)
            try? engine.apply(action, playerID: state.currentPlayer.id, to: &state)
        }
        for player in state.players {
            XCTAssertLessThanOrEqual(player.reservedCards.count, 2,
                "bot hoarded \(player.reservedCards.count) reserves in the opening")
        }
    }

    // MARK: - Duel

    func testDuelBotMovesAreAlwaysLegal() {
        for difficulty in BotDifficulty.allCases {
            let outcome = playDuel(difficulty: difficulty, seed: 99)
            XCTAssertTrue(outcome.finished, "duel \(difficulty) game did not finish")
            XCTAssertFalse(outcome.winnerIDs.isEmpty)
        }
    }

    func testDuelBotReplenishesTheBoard() {
        // Across a few full games the board depletes while the bag fills from
        // purchases, so a competent bot must refill the board at least once.
        var replenishes = 0
        for seed in 1 ... 3 {
            replenishes += countDuelReplenishes(difficulty: .hard, seed: UInt64(seed))
        }
        XCTAssertGreaterThan(replenishes, 0, "duel bot never replenished across 3 games")
    }

    private func countDuelReplenishes(difficulty: BotDifficulty, seed: UInt64) -> Int {
        let participants = (0 ..< 2).map {
            Participant(id: UUID(), nickname: "Bot\($0)", kind: .bot, difficulty: difficulty)
        }
        let config = GameConfiguration(mode: .duel, turnDurationSeconds: nil)
        guard var state = try? engine.makeGame(participants: participants, configuration: config, seed: seed) else {
            return 0
        }
        let controller = BotFactory.make(for: .duel)
        var count = 0
        var actions = 0
        while state.status == .playing, actions < 6000 {
            let action = controller.chooseAction(state: state, playerID: state.currentPlayer.id, difficulty: difficulty)
            if case .duel(.replenish) = action { count += 1 }
            try? engine.apply(action, playerID: state.currentPlayer.id, to: &state)
            actions += 1
        }
        return count
    }

    // MARK: - Harness

    private struct Outcome {
        var finished: Bool
        var actions: Int
        var winnerIDs: [UUID]
    }

    private func playStandard(playerCount: Int, difficulty: BotDifficulty, seed: UInt64) -> Outcome {
        let participants = (0 ..< playerCount).map {
            Participant(id: UUID(), nickname: "Bot\($0)", kind: .bot, difficulty: difficulty)
        }
        let config = GameConfiguration(mode: .standard, targetPrestige: 15, turnDurationSeconds: nil)
        return play(participants: participants, configuration: config, seed: seed, actionCap: 4000)
    }

    private func playDuel(difficulty: BotDifficulty, seed: UInt64) -> Outcome {
        let participants = (0 ..< 2).map {
            Participant(id: UUID(), nickname: "Bot\($0)", kind: .bot, difficulty: difficulty)
        }
        let config = GameConfiguration(mode: .duel, turnDurationSeconds: nil)
        return play(participants: participants, configuration: config, seed: seed, actionCap: 6000)
    }

    private func play(
        participants: [Participant],
        configuration: GameConfiguration,
        seed: UInt64,
        actionCap: Int
    ) -> Outcome {
        guard var state = try? engine.makeGame(participants: participants, configuration: configuration, seed: seed) else {
            return Outcome(finished: false, actions: 0, winnerIDs: [])
        }
        let controller = BotFactory.make(for: configuration.mode)
        var actions = 0
        while state.status == .playing, actions < actionCap {
            let difficulty = participants.first { $0.id == state.currentPlayer.id }?.difficulty ?? .normal
            let action = controller.chooseAction(state: state, playerID: state.currentPlayer.id, difficulty: difficulty)
            do {
                try engine.apply(action, playerID: state.currentPlayer.id, to: &state)
            } catch {
                XCTFail("bot produced an illegal action \(action): \(error)")
                break
            }
            actions += 1
        }
        return Outcome(
            finished: state.status == .finished,
            actions: actions,
            winnerIDs: state.result?.winnerIDs ?? []
        )
    }
}
