import SwiftData
import SwiftUI

struct AccountView: View {
    @Query(sort: \AccountProfile.createdAt) private var profiles: [AccountProfile]
    @AppStorage("activeProfileID") private var activeProfileID = ""
    @AppStorage("languageOverride") private var languageOverride = "system"
    @State private var draftNickname = ""

    private var activeProfile: AccountProfile? {
        profiles.first { $0.uuid.uuidString == activeProfileID } ?? profiles.first
    }

    var body: some View {
        Form {
            if let profile = activeProfile {
                Section("account.profile") {
                    TextField("account.nickname", text: $draftNickname)
                        .onSubmit { saveNickname(into: profile) }
                    LabeledContent("account.uuid") {
                        Text(profile.uuid.uuidString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Button("common.save") { saveNickname(into: profile) }
                        .disabled(normalizedNickname.isEmpty
                            || normalizedNickname.count > 20
                            || normalizedNickname == profile.nickname)
                }
            }

            Section {
                NavigationLink {
                    ProfilesView()
                } label: {
                    LabeledContent("account.profiles", value: "\(profiles.count)")
                }
            } footer: {
                Text("account.profiles.hint")
            }

            Section("settings.language") {
                Picker("settings.language", selection: $languageOverride) {
                    Text("settings.language.system").tag("system")
                    Text("settings.language.chinese").tag("zh-Hans")
                    Text("settings.language.english").tag("en")
                }
            }

            Section("account.medals") {
                ContentUnavailableView(
                    "account.medals.empty",
                    systemImage: "medal",
                    description: Text("common.comingSoon")
                )
            }

            Section("account.history") {
                ContentUnavailableView(
                    "account.history.empty",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("common.comingSoon")
                )
            }
        }
        .navigationTitle("account.title")
        .onAppear { draftNickname = activeProfile?.nickname ?? "" }
        .onChange(of: activeProfileID) { _, _ in draftNickname = activeProfile?.nickname ?? "" }
    }

    private var normalizedNickname: String {
        draftNickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveNickname(into profile: AccountProfile) {
        guard !normalizedNickname.isEmpty, normalizedNickname.count <= 20 else { return }
        profile.nickname = normalizedNickname
        profile.updatedAt = Date()
    }
}
