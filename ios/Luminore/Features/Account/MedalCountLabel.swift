import SwiftUI

struct MedalCountLabel: View {
    let count: Int
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            Image(systemName: "medal.fill")
                .foregroundStyle(.orange)
            Text("\(max(0, count))")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(compact ? .caption2 : .caption)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("medal.count.accessibility \(max(0, count))"))
    }
}
