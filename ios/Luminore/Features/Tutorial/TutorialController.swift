import LuminoreCore
import SwiftUI

/// Drives the guided portion of the standard-mode tutorial: which step is active,
/// when to auto-advance (action steps), and the transition into free-play. It reads
/// live snapshots but never mutates game state — the learner's real actions do that.
@MainActor
final class TutorialController<AnchorID: Hashable>: ObservableObject {
    enum Phase: Equatable {
        /// Walking through the scripted steps.
        case guiding
        /// Steps done; the learner plays freely until they win or end the tutorial.
        case freePlay
    }

    @Published private(set) var phase: Phase = .guiding
    @Published private(set) var currentIndex = 0

    let localID: UUID
    let freePlayBannerKey: String
    private let steps: [TutorialStep<AnchorID>]

    init(localID: UUID, steps: [TutorialStep<AnchorID>], freePlayBannerKey: String) {
        self.localID = localID
        self.steps = steps
        self.freePlayBannerKey = freePlayBannerKey
    }

    var currentStep: TutorialStep<AnchorID>? {
        guard phase == .guiding, steps.indices.contains(currentIndex) else { return nil }
        return steps[currentIndex]
    }

    /// Called whenever a fresh snapshot arrives; auto-advances satisfied action steps.
    func handleSnapshot(_ snapshot: ClientGameSnapshot) {
        guard phase == .guiding, let step = currentStep, step.isAction else { return }
        if step.isSatisfied(by: snapshot, localID: localID) {
            advance()
        }
    }

    /// Advance an `explain` step (the "Next" button).
    func next() {
        guard phase == .guiding, let step = currentStep, !step.isAction else { return }
        advance()
    }

    /// Skip the remaining guided steps and go straight to free-play.
    func skipGuiding() {
        guard phase == .guiding else { return }
        phase = .freePlay
    }

    private func advance() {
        let next = currentIndex + 1
        if next >= steps.count {
            phase = .freePlay
        } else {
            currentIndex = next
        }
    }
}
