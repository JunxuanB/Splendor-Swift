import LuminoreCore
import SwiftUI

struct DuelBagContentsPopover: View {
    let tokenCounts: [DuelTokenColor: Int]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("duel.bag.title", systemImage: "bag")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(DuelTokenColor.allCases) { color in
                    HStack(spacing: 8) {
                        DuelTokenChip(color: color, diameter: 30)
                        Text(color.localizedKey)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(tokenCounts[color, default: 0])")
                            .font(.body.bold().monospacedDigit())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(color.localizedKey))
                    .accessibilityValue(Text("\(tokenCounts[color, default: 0])"))
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
