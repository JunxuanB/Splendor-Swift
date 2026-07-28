import Foundation
import LuminoreCore

// Tutorials run fully host-authoritative local games
// on top of a `LoopbackTransport`. It bypasses the create/lobby/configure flow and
// injects a hand-authored `GameState` (see `TutorialScenario`) directly, so the
// board renders immediately with a designed layout. Learner actions flow through
// the normal `submit()` → `apply()` path, so rules validation, animations, and the
// finish/win handling are exactly the real game's — only the transport is inert.
extension MatchSessionService {
    /// Start a designed local tutorial game. Requires the service to have
    /// been created with a `LoopbackTransport`.
    func startTutorial(_ setup: TutorialMatchSetup) {
        leave()
        isLeaving = false
        isHost = true

        let state = setup.state
        tutorialOpponentID = setup.scriptedOpponentID
        tutorialOpponentActions = setup.scriptedOpponentActions

        let descriptor = RoomDescriptor(
            id: UUID(),
            name: "tutorial",
            hostNickname: nickname,
            playerCount: setup.participants.count,
            maximumPlayers: state.configuration.mode == .duel ? 2 : 7,
            isPasswordProtected: false,
            stage: .playing
        )
        room = RoomSnapshot(
            descriptor: descriptor,
            participants: setup.participants,
            configuration: state.configuration
        )

        authoritativeGame = state
        openingTurnSelection = nil
        turnDeadline = nil
        clearPauseState()
        broadcastGame()
    }

    /// Stop consuming the designed opponent queue and let the existing bot driver
    /// handle the same seat. Used after completing or skipping guided steps.
    func releaseTutorialOpponent() {
        botTask?.cancel()
        tutorialOpponentID = nil
        tutorialOpponentActions.removeAll()
        scheduleBotTurnIfNeeded()
    }
}
