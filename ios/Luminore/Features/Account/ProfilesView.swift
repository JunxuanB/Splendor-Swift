import SwiftData
import SwiftUI

/// Manages the profiles stored under one iCloud account. Multiple profiles let
/// people who share an Apple ID (a common family setup) each play as themselves,
/// which is also why the active profile — not the account UUID alone — drives
/// match identity and the presence lock.
struct ProfilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AccountProfile.createdAt) private var profiles: [AccountProfile]
    @AppStorage("activeProfileID") private var activeProfileID = ""
    @State private var isAddingProfile = false

    var body: some View {
        List {
            Section {
                ForEach(profiles) { profile in
                    Button {
                        activeProfileID = profile.uuid.uuidString
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.nickname).foregroundStyle(.primary)
                                Text(profile.uuid.uuidString.prefix(8))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.uuid.uuidString == activeProfileID {
                                Text("account.profiles.active")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteProfiles)
            } footer: {
                Text("account.profiles.hint")
            }

            Section {
                Button {
                    isAddingProfile = true
                } label: {
                    Label("account.profiles.add", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle("account.profiles")
        .toolbar { EditButton() }
        .sheet(isPresented: $isAddingProfile) {
            NewProfileSheet { nickname in
                let profile = AccountProfile(nickname: nickname)
                modelContext.insert(profile)
                try? modelContext.save()
                activeProfileID = profile.uuid.uuidString
            }
        }
    }

    private func deleteProfiles(at offsets: IndexSet) {
        // Keep at least one profile so the app never drops back to onboarding by
        // surprise.
        guard profiles.count > offsets.count else { return }
        let deletedIDs = Set(offsets.map { profiles[$0].uuid.uuidString })
        for index in offsets { modelContext.delete(profiles[index]) }
        try? modelContext.save()
        if deletedIDs.contains(activeProfileID) {
            activeProfileID = profiles.first { !deletedIDs.contains($0.uuid.uuidString) }?.uuid.uuidString ?? ""
        }
    }
}

private struct NewProfileSheet: View {
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @FocusState private var isFocused: Bool

    private var normalized: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("account.profiles.newTitle") {
                    TextField("onboarding.nickname.placeholder", text: $nickname)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(create)
                }
            }
            .navigationTitle("account.profiles.add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: create)
                        .disabled(normalized.isEmpty || normalized.count > 20)
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func create() {
        guard !normalized.isEmpty, normalized.count <= 20 else { return }
        onCreate(normalized)
        dismiss()
    }
}
