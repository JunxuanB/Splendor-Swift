import SwiftUI

/// A few paged explanation screens shown before the guided tutorial game begins.
struct TutorialIntroView: View {
    enum Mode {
        case standard
        case duel
    }

    let mode: Mode
    let onStart: () -> Void
    let onCancel: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let systemImage: String
        let tint: Color
        let titleKey: LocalizedStringKey
        let bodyKey: LocalizedStringKey
    }

    private var pages: [Page] {
        switch mode {
        case .standard:
            return [
                Page(id: 0, systemImage: "graduationcap.fill", tint: .accentColor,
                     titleKey: "tutorial.intro.1.title", bodyKey: "tutorial.intro.1.body"),
                Page(id: 1, systemImage: "crown.fill", tint: .orange,
                     titleKey: "tutorial.intro.2.title", bodyKey: "tutorial.intro.2.body"),
                Page(id: 2, systemImage: "square.grid.2x2.fill", tint: .purple,
                     titleKey: "tutorial.intro.3.title", bodyKey: "tutorial.intro.3.body"),
            ]
        case .duel:
            return [
                Page(id: 0, systemImage: "person.2.fill", tint: .accentColor,
                     titleKey: "tutorial.duel.intro.1.title", bodyKey: "tutorial.duel.intro.1.body"),
                Page(id: 1, systemImage: "chart.bar.fill", tint: .orange,
                     titleKey: "tutorial.duel.intro.2.title", bodyKey: "tutorial.duel.intro.2.body"),
                Page(id: 2, systemImage: "circle.grid.3x3.fill", tint: .purple,
                     titleKey: "tutorial.duel.intro.3.title", bodyKey: "tutorial.duel.intro.3.body"),
            ]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages) { item in
                    VStack(spacing: 24) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(item.tint)
                            .padding(.bottom, 4)
                        Text(item.titleKey)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(item.bodyKey)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if page == pages.count - 1 {
                    Button(action: onStart) {
                        Text("tutorial.intro.start")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("tutorial.intro.next")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(mode == .standard ? "tutorial.standard.title" : "tutorial.duel.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("common.cancel", action: onCancel)
            }
        }
    }
}
