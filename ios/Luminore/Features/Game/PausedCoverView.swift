import SwiftUI

/// Full-screen cover shown while the host has paused the match. Blocks the board and
/// offers host controls (resume / save & exit).
struct PausedCoverView: View {
    let isHost: Bool
    let onResume: () -> Void
    let onSaveAndSuspend: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.secondary)

                Text("game.paused.title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(isHost ? "game.paused.host.hint" : "game.paused.client.hint")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if isHost {
                    VStack(spacing: 12) {
                        Button(action: onResume) {
                            Label("game.paused.resume", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(role: .destructive, action: onSaveAndSuspend) {
                            Label("game.paused.saveExit", systemImage: "tray.and.arrow.down")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .accessibilityAddTraits(.isModal)
    }
}
