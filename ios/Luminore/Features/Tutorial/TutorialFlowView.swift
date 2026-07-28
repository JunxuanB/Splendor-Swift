import LuminoreCore
import SwiftUI

/// Standalone entry for the standard-mode tutorial. Shows the intro pages, then
/// runs a designed single-player game (host-local over a `LoopbackTransport`) with
/// the guided coach overlay. No presence claims, persistence, or match records —
/// this is a throwaway teaching session.
struct TutorialFlowView: View {
    let profile: AccountProfile

    @StateObject private var session: MatchSessionService
    @StateObject private var controller: TutorialController<GameAnchorID>
    @Environment(\.dismiss) private var dismiss
    @State private var showIntro = true

    init(profile: AccountProfile) {
        self.profile = profile
        _session = StateObject(wrappedValue: MatchSessionService(
            localID: profile.uuid,
            nickname: profile.nickname,
            transport: LoopbackTransport()
        ))
        _controller = StateObject(wrappedValue: TutorialController(
            localID: profile.uuid,
            steps: TutorialScript.standard(localID: profile.uuid),
            freePlayBannerKey: "tutorial.freePlay.banner"
        ))
    }

    var body: some View {
        Group {
            if showIntro {
                TutorialIntroView(mode: .standard, onStart: start, onCancel: exit)
            } else {
                switch session.phase {
                case .game:
                    GameBoardView(
                        session: session,
                        tutorial: controller,
                        onExit: exit,
                        onSaveAndSuspend: {}
                    )
                case .results:
                    TutorialCompletionView(onDone: exit)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarBackButtonHidden(!showIntro)
        .onDisappear {
            if session.phase != .game { session.leave() }
        }
    }

    private func start() {
        showIntro = false
        session.startTutorial(
            TutorialScenario.standard(playerID: profile.uuid, nickname: profile.nickname)
        )
    }

    private func exit() {
        session.leave()
        dismiss()
    }
}

struct TutorialCompletionView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.orange)
            Text("tutorial.done.title")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("tutorial.done.body")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Button(action: onDone) {
                Text("tutorial.done.button")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
    }
}
