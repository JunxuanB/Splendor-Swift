import SwiftUI

struct InternetServerSettingsView: View {
    private enum CheckState: Equatable {
        case idle
        case checking
        case compatible
        case failed(String)
    }

    let onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(InternetServerSettings.storageKey) private var storedValue = InternetServerSettings.defaultURL.absoluteString
    @State private var value = ""
    @State private var checkState: CheckState = .idle

    private var validatedURL: URL? {
        try? InternetServerSettings.normalizedURL(from: value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("internet.server.address") {
                    TextField("https://example.com", text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("internet.server.securityHint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        testServer()
                    } label: {
                        HStack {
                            Label("internet.server.test", systemImage: "waveform.path.ecg")
                            Spacer()
                            if checkState == .checking { ProgressView() }
                        }
                    }
                    .disabled(validatedURL == nil || checkState == .checking)

                    statusView

                    Button("internet.server.restoreDefault", role: .destructive) {
                        value = InternetServerSettings.defaultURL.absoluteString
                        checkState = .idle
                    }
                }
            }
            .navigationTitle("internet.server.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(validatedURL == nil)
                }
            }
            .onAppear { value = storedValue }
            .onChange(of: value) { _, _ in checkState = .idle }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch checkState {
        case .idle, .checking:
            EmptyView()
        case .compatible:
            Label("internet.server.compatible", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func testServer() {
        guard let url = validatedURL else { return }
        checkState = .checking
        Task {
            do {
                try await InternetServerSettings.healthCheck(url: url)
                checkState = .compatible
            } catch {
                checkState = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let url = validatedURL else { return }
        storedValue = url.absoluteString
        onSave(url)
        dismiss()
    }
}
