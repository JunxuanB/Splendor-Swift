import SwiftUI

struct TutorialSelectionView: View {
    let profile: AccountProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("tutorial.selection.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                NavigationLink {
                    TutorialFlowView(profile: profile)
                } label: {
                    tutorialCard(
                        title: "tutorial.standard.title",
                        subtitle: "tutorial.standard.subtitle",
                        image: "square.grid.2x2.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DuelTutorialFlowView(profile: profile)
                } label: {
                    tutorialCard(
                        title: "tutorial.duel.title",
                        subtitle: "tutorial.duel.subtitle",
                        image: "person.2.fill",
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("tutorial.entry.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tutorialCard(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        image: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: image)
                .font(.title2.bold())
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
