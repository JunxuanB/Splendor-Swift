import XCTest
@testable import Luminore
@testable import LuminoreCore

@MainActor
final class TutorialControllerTests: XCTestCase {
    func testExplainActionAndFreePlayTransitions() {
        let playerID = UUID()
        let steps: [TutorialStep<Int>] = [
            TutorialStep(
                id: 0,
                titleKey: "explain",
                bodyKey: "explain.body",
                highlights: [1],
                surface: .duelTokens,
                kind: .explain
            ),
            TutorialStep(
                id: 1,
                titleKey: "action",
                bodyKey: "action.body",
                highlights: [2],
                surface: .duelCards,
                kind: .action { $0.revision > 0 && $1 == playerID }
            ),
        ]
        let controller = TutorialController(
            localID: playerID,
            steps: steps,
            freePlayBannerKey: "free"
        )

        XCTAssertEqual(controller.currentStep?.surface, .duelTokens)
        controller.next()
        XCTAssertEqual(controller.currentIndex, 1)
        XCTAssertEqual(controller.currentStep?.surface, .duelCards)

        var state = TutorialScenario.standard(playerID: playerID, nickname: "Learner").state
        controller.handleSnapshot(state.snapshot(for: playerID))
        XCTAssertEqual(controller.phase, .guiding)
        state.revision = 1
        controller.handleSnapshot(state.snapshot(for: playerID))
        XCTAssertEqual(controller.phase, .freePlay)
    }

    func testSkipMovesDirectlyToFreePlay() {
        let playerID = UUID()
        let controller = TutorialController(
            localID: playerID,
            steps: [TutorialStep<Int>(
                id: 0,
                titleKey: "x",
                bodyKey: "y",
                highlights: [],
                kind: .explain
            )],
            freePlayBannerKey: "free"
        )
        controller.skipGuiding()
        XCTAssertEqual(controller.phase, .freePlay)
        XCTAssertNil(controller.currentStep)
    }
}
