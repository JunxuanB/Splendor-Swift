import LuminoreCore
import SwiftUI

struct DeveloperStandardGemEditor: View {
    @Binding var tokens: [GemColor: Int]
    let onSave: () -> Void

    var body: some View {
        DeveloperGemEditorContainer(onSave: onSave) {
            ForEach(GemColor.allCases) { color in
                DeveloperTokenStepper(
                    title: color.localizedKey,
                    tint: color.tint,
                    iconName: color.iconName,
                    foreground: color.foreground,
                    value: binding(for: color)
                )
            }
        }
    }

    private func binding(for color: GemColor) -> Binding<Int> {
        Binding(
            get: { tokens[color, default: 0] },
            set: { tokens[color] = $0 }
        )
    }
}

struct DeveloperDuelGemEditor: View {
    @Binding var tokens: [DuelTokenColor: Int]
    let onSave: () -> Void

    var body: some View {
        DeveloperGemEditorContainer(onSave: onSave) {
            ForEach(DuelTokenColor.allCases) { color in
                DeveloperTokenStepper(
                    title: color.localizedKey,
                    tint: color.tint,
                    iconName: color.iconName,
                    foreground: color.foreground,
                    value: binding(for: color)
                )
            }
        }
    }

    private func binding(for color: DuelTokenColor) -> Binding<Int> {
        Binding(
            get: { tokens[color, default: 0] },
            set: { tokens[color] = $0 }
        )
    }
}

private struct DeveloperGemEditorContainer<Rows: View>: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    rows()
                } footer: {
                    Text("developer.gems.footer")
                }
            }
            .navigationTitle("developer.gems.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DeveloperTokenStepper: View {
    let title: LocalizedStringKey
    let tint: Color
    let iconName: String
    let foreground: Color
    @Binding var value: Int

    var body: some View {
        Stepper(value: $value, in: 0 ... 99) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.caption.bold())
                    .foregroundStyle(foreground)
                    .frame(width: 30, height: 30)
                    .background(tint, in: Circle())

                Text(title)
                Spacer()
                Text("\(value)")
                    .font(.body.bold().monospacedDigit())
                    .contentTransition(.numericText())
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
    }
}
