import LuminoreCore
import SwiftUI

/// Full-screen cover shown while the whole match is frozen waiting for one or more
/// dropped players to reconnect. Purely informational — no one can act during the
/// grace window, so there are no buttons. When everyone returns (or the window
/// expires) the host clears the pause and play resumes.
struct DisconnectPauseView: View {
    let pause: MatchPause

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)

                Text("game.disconnect.title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                if !pause.waitingForNicknames.isEmpty {
                    Text("game.disconnect.waiting \(pause.waitingForNicknames.joined(separator: "、"))")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let deadline = pause.resumeDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                        Text("game.disconnect.countdown \(remaining)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .accessibilityAddTraits(.isModal)
    }
}
