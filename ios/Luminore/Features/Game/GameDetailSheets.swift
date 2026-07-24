import LuminoreCore
import SwiftUI

struct SelectedCard: Identifiable {
    let id = UUID()
    let card: DevelopmentCard
    let source: CardSource
}

struct PendingReturn: Identifiable {
    enum Kind {
        case take([GemColor: Int])
        case reserve(CardSource, DevelopmentCard?)
    }

    let id = UUID()
    let kind: Kind
    let available: [GemColor: Int]
    let required: Int
}

struct ReservedCardsSheetRequest: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let cards: [DevelopmentCard]
    let cardCount: Int
    let purchasableCardIDs: Set<String>
    var isReadOnly = false
}

struct CardDetailSheet: View {
    let selection: SelectedCard
    let player: PublicPlayerSnapshot
    let nobles: [NobleTile]
    let allowsActions: Bool
    let showsPurchaseHighlight: Bool
    let onReserve: () -> Void
    let onPurchase: ([GemColor: Int], String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var purchaseDecision: PreferredPurchaseDecision? {
        PurchasePlanner.preferredDecision(
            for: selection.card,
            player: player,
            availableNobles: nobles
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                DevelopmentCardView(
                    card: selection.card,
                    enlarged: true,
                    isPurchasable: canPurchase(selection.card, player: player),
                    showsPurchaseHighlight: showsPurchaseHighlight
                )
                .frame(width: 190)

                HStack(spacing: 7) {
                    Image(systemName: selection.card.bonus.iconName)
                        .foregroundStyle(selection.card.bonus.tint)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("game.card.permanentBonus").font(.caption).foregroundStyle(.secondary)
                        Text(selection.card.bonus.localizedKey)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selection.card.bonus.tint.opacity(0.12), in: Capsule())

                HStack(spacing: 12) {
                    if case .market = selection.source {
                        Button("game.reserve") {
                            onReserve()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(!allowsActions || player.reservedCardCount >= 3)
                    }

                    Button("game.buy") {
                        guard let purchaseDecision else { return }
                        onPurchase(purchaseDecision.payment, purchaseDecision.nobleID)
                        dismiss()
                    }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(!allowsActions || purchaseDecision == nil)
                }
                .controlSize(.large)
            }
            .padding(20)
            .navigationTitle("game.card.actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct NobleDetailSheet: View {
    let noble: NobleTile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HStack(spacing: 22) {
                NobleTileView(noble: noble, enlarged: true)
                    .frame(width: 180)

                VStack(alignment: .leading, spacing: 10) {
                    Text("game.noble.generic").font(.title3.bold())
                    Text("game.noble.value \(noble.prestige)")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Text("game.noble.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .navigationTitle("game.noble.detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct ReservedCardsSheet: View {
    let request: ReservedCardsSheetRequest
    let showsPurchaseHighlight: Bool
    let onSelectCard: (DevelopmentCard) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if request.cards.isEmpty {
                    ContentUnavailableView(
                        "game.reserved.empty",
                        systemImage: "rectangle.stack",
                        description: Text("game.reserved.empty.description")
                    )
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                        alignment: .center,
                        spacing: 12
                    ) {
                        ForEach(request.cards) { card in
                            let isPurchasable = request.purchasableCardIDs.contains(card.id)
                            VStack(spacing: 8) {
                                DevelopmentCardView(
                                    card: card,
                                    compactHeight: 136,
                                    isPurchasable: isPurchasable,
                                    showsPurchaseHighlight: showsPurchaseHighlight
                                )

                                if isPurchasable {
                                    Button {
                                        dismiss()
                                        onSelectCard(card)
                                    } label: {
                                        Label("game.buy", systemImage: "cart.fill")
                                            .font(.caption.bold())
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    Text(request.isReadOnly ? "game.reserved.hidden.footer" : "game.reserved.maximum")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct ReturnTokensView: View {
    let available: [GemColor: Int]
    let required: Int
    let onConfirm: ([GemColor: Int]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var returning: [GemColor: Int] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section { Text("game.return.required \(required)") }
                Section("game.return.choose") {
                    ForEach(GemColor.allCases) { gem in
                        Stepper(value: binding(gem), in: 0 ... available[gem, default: 0]) {
                            HStack {
                                Circle().fill(gem.tint).frame(width: 22, height: 22)
                                Text(gem.localizedKey)
                                Spacer()
                                Text("\(returning[gem, default: 0]) / \(available[gem, default: 0])")
                            }
                        }
                    }
                }
            }
            .navigationTitle("game.return.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.confirm") {
                        onConfirm(returning.filter { $0.value > 0 })
                        dismiss()
                    }
                    .disabled(returning.values.reduce(0, +) != required)
                }
            }
        }
    }

    private func binding(_ gem: GemColor) -> Binding<Int> {
        Binding(get: { returning[gem, default: 0] }, set: { returning[gem] = $0 })
    }
}
