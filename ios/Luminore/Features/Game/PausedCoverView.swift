import LuminoreCore
import SwiftUI

/// Full-screen cover shown while the match is paused. In a normal pause it just
/// blocks the board and offers host controls; while resuming a saved game it also
/// hosts the seat-assignment panel.
struct PausedCoverView: View {
    let isHost: Bool
    let isAwaitingAssignment: Bool
    let participants: [Participant]
    let pendingSubstitutes: [PendingSubstitute]
    let localID: UUID
    let onResume: () -> Void
    let onSaveAndSuspend: () -> Void
    let onAssign: (_ seatID: UUID, _ substituteID: UUID) -> Void
    let onContinueResumed: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: isAwaitingAssignment ? "person.2.badge.gearshape" : "pause.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.secondary)

                Text(isAwaitingAssignment ? "game.resume.assign.title" : "game.paused.title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                if isAwaitingAssignment {
                    assignmentPanel
                } else {
                    Text(isHost ? "game.paused.host.hint" : "game.paused.client.hint")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if isHost { pauseControls }
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var pauseControls: some View {
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

    // MARK: Resume seat assignment (host only)

    @ViewBuilder private var assignmentPanel: some View {
        if isHost {
            Text("game.resume.assign.hint")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ForEach(participants) { participant in
                    seatRow(participant)
                }
            }

            Button(action: onContinueResumed) {
                Label("game.resume.continue", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        } else {
            Text("game.paused.client.hint")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func seatRow(_ participant: Participant) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(participant.isConnected ? Color.green : Color.gray)
                .frame(width: 9, height: 9)
            Text(participant.nickname)
                .font(.headline)
            if participant.isHost {
                Image(systemName: "crown.fill").foregroundStyle(.yellow).font(.caption)
            }
            Spacer()
            if participant.isConnected {
                Text("game.resume.seat.online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if pendingSubstitutes.isEmpty {
                Text("game.resume.seat.waiting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(pendingSubstitutes) { substitute in
                        Button(substitute.nickname) {
                            onAssign(participant.id, substitute.id)
                        }
                    }
                } label: {
                    Label("game.resume.seat.assign", systemImage: "person.fill.badge.plus")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
