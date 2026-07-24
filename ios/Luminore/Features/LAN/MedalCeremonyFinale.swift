import SwiftUI

struct MedalCeremonyFinale: View {
    let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBursting = false
    @State private var isFaded = false

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.42

            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(colors: [.clear, .yellow, .orange, .clear], center: .center),
                        lineWidth: 3
                    )
                    .frame(width: 86, height: 86)
                    .scaleEffect(isBursting ? 1.75 : 0.35)
                    .opacity(isFaded ? 0 : (isBursting ? 0.75 : 0))
                    .position(center)

                ForEach(0 ..< 18, id: \.self) { index in
                    let angle = Double(index) * (2 * .pi / 18) - .pi / 2
                    let distance = radius * (0.72 + CGFloat(index % 4) * 0.09)

                    Image(systemName: index.isMultiple(of: 3) ? "sparkle" : "circle.fill")
                        .font(.system(size: index.isMultiple(of: 3) ? 13 : 5, weight: .bold))
                        .foregroundStyle(index.isMultiple(of: 2) ? Color.yellow : Color.orange)
                        .shadow(color: .orange.opacity(0.35), radius: 3)
                        .position(center)
                        .offset(
                            x: isBursting && !reduceMotion ? CGFloat(cos(angle)) * distance : 0,
                            y: isBursting && !reduceMotion ? CGFloat(sin(angle)) * distance : 0
                        )
                        .scaleEffect(isBursting ? 1 : 0.15)
                        .opacity(isFaded ? 0 : (isBursting ? 0.95 : 0))
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: isPresented) {
            guard isPresented else {
                isBursting = false
                isFaded = false
                return
            }

            withAnimation(.easeOut(duration: reduceMotion ? 0.18 : 0.5)) {
                isBursting = true
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 560))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.34)) {
                isFaded = true
            }
        }
        .accessibilityHidden(true)
    }
}
