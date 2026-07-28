import LuminoreCore
import SwiftUI

/// A local two-seat Duel teaching match. The scripted opponent exists only for
/// the guided milestones; free play hands the same seat to the normal Duel bot.
struct DuelTutorialFlowView: View {
    let profile: AccountProfile
    private let setup: TutorialMatchSetup

    @StateObject private var session: MatchSessionService
    @StateObject private var controller: TutorialController<DuelAnchorID>
    @Environment(\.dismiss) private var dismiss
    @State private var showIntro = true

    init(profile: AccountProfile) {
        self.profile = profile
        let setup = TutorialScenario.duel(
            playerID: profile.uuid,
            nickname: profile.nickname,
            opponentNickname: String(localized: "tutorial.duel.botName")
        )
        self.setup = setup
        _session = StateObject(wrappedValue: MatchSessionService(
            localID: profile.uuid,
            nickname: profile.nickname,
            transport: LoopbackTransport()
        ))
        _controller = StateObject(wrappedValue: TutorialController(
            localID: profile.uuid,
            steps: TutorialScript.duel(
                localID: profile.uuid,
                opponentID: setup.scriptedOpponentID!
            ),
            freePlayBannerKey: "tutorial.duel.freePlay.banner"
        ))
    }

    var body: some View {
        Group {
            if showIntro {
                TutorialIntroView(mode: .duel, onStart: start, onCancel: exit)
            } else {
                switch session.phase {
                case .game:
                    DuelGameBoardView(
                        session: session,
                        tutorial: controller,
                        onExit: exit,
                        onSaveAndSuspend: {}
                    )
                case .results:
                    TutorialCompletionView(onDone: exit)
                default:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarBackButtonHidden(!showIntro)
        .onChange(of: controller.phase) { _, phase in
            if phase == .freePlay { session.releaseTutorialOpponent() }
        }
        .onDisappear {
            if session.phase != .game { session.leave() }
        }
    }

    private func start() {
        showIntro = false
        session.startTutorial(setup)
    }

    private func exit() {
        session.leave()
        dismiss()
    }
}
