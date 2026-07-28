import LuminoreCore
import SwiftUI

/// The guided-tutorial layer drawn on top of the real game board. During guiding it
/// dims the board, punches a spotlight around the current step's target(s), rings
/// them, and shows an instruction callout. The dim layer never blocks touches
/// (highlight-only guidance) so multi-tap flows and sheets work normally; action
/// steps advance from `TutorialController` observing the live snapshot.
struct TutorialCoachOverlay<AnchorID: Hashable>: View {
    @ObservedObject var controller: TutorialController<AnchorID>
    /// Screen-space rects of the current step's highlighted anchors, pre-resolved.
    let targetRects: [CGRect]
    let onExit: () -> Void

    private let holePadding: CGFloat = 8
    private let holeCornerRadius: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch controller.phase {
                case .guiding:
                    if let step = controller.currentStep {
                        guidingContent(step: step, size: geo.size)
                    }
                case .freePlay:
                    freePlayBanner(size: geo.size)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.currentIndex)
            .animation(.easeInOut(duration: 0.25), value: controller.phase)
        }
    }

    // MARK: - Guiding

    @ViewBuilder
    private func guidingContent(step: TutorialStep<AnchorID>, size: CGSize) -> some View {
        // Dimming with spotlight cut-outs — purely visual, taps pass through.
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .reverseMask {
                ForEach(Array(targetRects.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: holeCornerRadius, style: .continuous)
                        .frame(width: rect.width + holePadding * 2, height: rect.height + holePadding * 2)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .allowsHitTesting(false)

        ForEach(Array(targetRects.enumerated()), id: \.offset) { _, rect in
            ShimmerBorder(cornerRadius: holeCornerRadius, lineWidth: 3)
                .frame(width: rect.width + holePadding * 2, height: rect.height + holePadding * 2)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }

        calloutCard(step: step, size: size)
    }

    private func calloutCard(step: TutorialStep<AnchorID>, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(step.titleKey))
                .font(.headline)
            Text(LocalizedStringKey(step.bodyKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("tutorial.button.skip", action: controller.skipGuiding)
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                if step.isAction {
                    Label("tutorial.hint.action", systemImage: "hand.tap.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .labelStyle(.titleAndIcon)
                } else {
                    Button("tutorial.button.next", action: controller.next)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: calloutAtTop(size: size) ? .top : .bottom)
        .padding(.top, calloutAtTop(size: size) ? 64 : 0)
        .padding(.bottom, calloutAtTop(size: size) ? 0 : 40)
    }

    /// Place the callout on the opposite half from the highlighted target so it
    /// never covers what the learner needs to tap.
    private func calloutAtTop(size: CGSize) -> Bool {
        guard let union = unionRect else { return false }
        return union.midY > size.height * 0.5
    }

    private var unionRect: CGRect? {
        guard let first = targetRects.first else { return nil }
        return targetRects.dropFirst().reduce(first) { $0.union($1) }
    }

    // MARK: - Free play

    private func freePlayBanner(size: CGSize) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text(LocalizedStringKey(controller.freePlayBannerKey))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("tutorial.freePlay.end", action: onExit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 64)
    }
}

private extension View {
    /// Masks self to everything EXCEPT the supplied shapes (a spotlight cut-out).
    @ViewBuilder
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(mask().blendMode(.destinationOut))
                .compositingGroup()
        }
    }
}
