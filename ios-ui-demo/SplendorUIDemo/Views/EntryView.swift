import SwiftUI

struct EntryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.gray.opacity(0.07)
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.blue.gradient)
                            .frame(width: 112, height: 112)

                        Image(systemName: "diamond.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .blue.opacity(0.25), radius: 20, y: 10)

                    VStack(spacing: 8) {
                        Text("璀璨宝石")
                            .font(.largeTitle.bold())
                        Text("UI DEMO")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(spacing: 14) {
                        NavigationLink {
                            GameBoardView()
                        } label: {
                            entryLabel(title: "进入基础版演示", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 16))

                        NavigationLink {
                            DuelGameBoardView()
                        } label: {
                            entryLabel(title: "进入双人版演示", systemImage: "person.2.fill")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 16))

                        NavigationLink {
                            SilkRoadGameBoardView()
                        } label: {
                            entryLabel(title: "进入丝绸之路演示", systemImage: "map.fill")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                    }

                    Text("所有数据仅用于界面演示")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
    }

    private func entryLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }
}

struct EntryView_Previews: PreviewProvider {
    static var previews: some View {
        EntryView()
            .previewDisplayName("入口")
            .previewDevice("iPhone 14")
    }
}
