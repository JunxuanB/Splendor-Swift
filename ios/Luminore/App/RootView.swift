import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \AccountProfile.createdAt) private var profiles: [AccountProfile]
    @AppStorage("activeProfileID") private var activeProfileID = ""

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingView()
            } else if let profile = activeProfile {
                // Rebuild the whole home tree when the active profile changes so
                // that per-profile state (LAN session identity, greeting) resets.
                HomeView(profile: profile)
                    .id(profile.uuid)
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: normalizeActiveSelection)
        .onChange(of: profiles.map(\.uuid)) { _, _ in normalizeActiveSelection() }
    }

    private var activeProfile: AccountProfile? {
        profiles.first { $0.uuid.uuidString == activeProfileID } ?? profiles.first
    }

    /// Keep `activeProfileID` pointing at a real profile — e.g. after the selected
    /// profile is deleted, or when this device first syncs profiles from iCloud.
    private func normalizeActiveSelection() {
        guard let resolved = activeProfile else { return }
        if activeProfileID != resolved.uuid.uuidString {
            activeProfileID = resolved.uuid.uuidString
        }
    }
}

private struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("activeProfileID") private var activeProfileID = ""
    @State private var nickname = ""
    @FocusState private var isFocused: Bool

    private var normalizedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                AppMark(size: 116)
                VStack(spacing: 8) {
                    Text("onboarding.welcome")
                        .font(.largeTitle.bold())
                    Text("onboarding.subtitle")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                TextField("onboarding.nickname.placeholder", text: $nickname)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    .onSubmit(createProfile)
                Button(action: createProfile) {
                    Text("onboarding.continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(normalizedNickname.isEmpty || normalizedNickname.count > 20)
                Text("onboarding.nickname.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(28)
        }
        .onAppear { isFocused = true }
    }

    private func createProfile() {
        guard !normalizedNickname.isEmpty, normalizedNickname.count <= 20 else { return }
        let profile = AccountProfile(nickname: normalizedNickname)
        modelContext.insert(profile)
        try? modelContext.save()
        activeProfileID = profile.uuid.uuidString
    }
}

struct AppMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(.blue.gradient)
            Image(systemName: "diamond.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .blue.opacity(0.24), radius: size * 0.16, y: size * 0.08)
        .accessibilityHidden(true)
    }
}
