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
                        Text("基础版 · UI DEMO")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    NavigationLink {
                        GameBoardView()
                    } label: {
                        Label("进入演示对局", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))

                    Text("所有数据仅用于界面演示")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
    }
}

struct EntryView_Previews: PreviewProvider {
    static var previews: some View {
        EntryView()
            .previewDisplayName("入口")
            .previewDevice("iPhone 14")
    }
}
