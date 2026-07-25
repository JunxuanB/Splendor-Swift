import LuminoreCore
import SwiftUI

struct DuelReturnDraft: Identifiable {
    enum Kind {
        case take([Int])
    }

    let id = UUID()
    let kind: Kind
    let available: [DuelTokenColor: Int]
    let required: Int
}

struct DuelReturnTokensSheet: View {
    let draft: DuelReturnDraft
    let onConfirm: ([DuelTokenColor: Int]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var returning: [DuelTokenColor: Int] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("duel.return.required \(draft.required)")
                        .font(.headline)
                }
                DuelReturnEditor(available: draft.available, required: draft.required, returning: $returning)
            }
            .navigationTitle("duel.return.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.confirm") {
                        onConfirm(returning.filter { $0.value > 0 })
                        dismiss()
                    }
                    .disabled(returning.values.reduce(0, +) != draft.required)
                }
            }
        }
    }
}

struct DuelReturnEditor: View {
    let available: [DuelTokenColor: Int]
    let required: Int
    @Binding var returning: [DuelTokenColor: Int]

    var body: some View {
        Section("duel.return.choose") {
            ForEach(DuelTokenColor.allCases) { color in
                let held = available[color, default: 0]
                if held > 0 {
                    Stepper(value: binding(color), in: 0 ... held) {
                        HStack {
                            DuelTokenChip(color: color, diameter: 25)
                            Text(color.localizedKey)
                            Spacer()
                            Text("\(returning[color, default: 0]) / \(held)").monospacedDigit()
                        }
                    }
                }
            }
            LabeledContent("duel.return.remaining", value: "\(max(0, required - returning.values.reduce(0, +)))")
        }
    }

    private func binding(_ color: DuelTokenColor) -> Binding<Int> {
        Binding(get: { returning[color, default: 0] }, set: { returning[color] = $0 })
    }
}

struct DuelReserveSheet: View {
    let source: DuelCardSource
    let card: DuelJewelCard?
    let duel: DuelClientSnapshot
    let player: DuelPublicPlayerSnapshot
    let onConfirm: (Int, [DuelTokenColor: Int]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGoldIndex: Int?
    @State private var returning: [DuelTokenColor: Int] = [:]

    private var goldIndices: [Int] { duel.board.indices.filter { duel.board[$0] == .gold } }
    private var availableAfterGold: [DuelTokenColor: Int] {
        var result = player.tokens
        result[.gold, default: 0] += 1
        return result
    }
    private var requiredReturns: Int { max(0, availableAfterGold.values.reduce(0, +) - DuelRules.tokenLimit) }

    var body: some View {
        NavigationStack {
            Form {
                if let card { DuelJewelCardView(card: card, enlarged: true).frame(maxWidth: .infinity) }
                Section("duel.reserve.chooseGold") {
                    HStack {
                        ForEach(goldIndices, id: \.self) { index in
                            Button {
                                selectedGoldIndex = index
                            } label: {
                                VStack(spacing: 3) {
                                    DuelTokenChip(color: .gold, diameter: 34, selected: selectedGoldIndex == index)
                                    Text("\(index / 5 + 1),\(index % 5 + 1)").font(.caption2.monospacedDigit())
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("duel.reserve.goldPositionHint").font(.footnote).foregroundStyle(.secondary)
                }
                if requiredReturns > 0 {
                    DuelReturnEditor(available: availableAfterGold, required: requiredReturns, returning: $returning)
                }
            }
            .navigationTitle("duel.reserve.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("duel.reserve") {
                        if let selectedGoldIndex {
                            onConfirm(selectedGoldIndex, returning.filter { $0.value > 0 })
                            dismiss()
                        }
                    }
                    .disabled(selectedGoldIndex == nil || returning.values.reduce(0, +) != requiredReturns)
                }
            }
        }
        .onAppear { selectedGoldIndex = goldIndices.first }
    }
}

struct DuelPurchaseSheet: View {
    let card: DuelJewelCard
    let source: DuelCardSource
    let duel: DuelClientSnapshot
    let player: DuelPublicPlayerSnapshot
    let opponent: DuelPublicPlayerSnapshot
    let allowsPurchase: Bool
    let onPurchase: ([DuelTokenColor: Int], DuelPurchaseChoices, [DuelTokenColor: Int]) -> Void
    let onReserve: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var coloredPayment: [DuelTokenColor: Int] = [:]
    @State private var wildColor: DuelGemColor?
    @State private var abilityBoardIndex: Int?
    @State private var stolenToken: DuelTokenColor?
    @State private var royalID: String?
    @State private var royalStolenToken: DuelTokenColor?
    @State private var returning: [DuelTokenColor: Int] = [:]

    private var earnedRoyal: Bool {
        let next = player.crowns + card.crowns
        return (player.crowns < 3 && next >= 3) || (player.crowns < 6 && next >= 6)
    }
    private var effectiveColor: DuelGemColor? { card.isWildBonus ? wildColor : card.bonusColor }
    private var matchingBoardIndices: [Int] {
        guard let effectiveColor else { return [] }
        let token = DuelTokenColor(effectiveColor)
        return duel.board.indices.filter { duel.board[$0] == token }
    }
    private var stealable: [DuelTokenColor] {
        DuelTokenColor.boardTakeable.filter { opponent.tokens[$0, default: 0] > 0 }
    }
    private var selectedRoyal: DuelRoyalCard? { duel.availableRoyals.first { $0.id == royalID } }

    private var payment: [DuelTokenColor: Int] {
        var result = coloredPayment.filter { $0.value > 0 }
        result[.gold] = goldRequired
        return result.filter { $0.value > 0 }
    }
    private var goldRequired: Int {
        DuelTokenColor.boardTakeable.reduce(0) { partial, token in
            let discount = token.gemColor.map { player.bonuses[$0, default: 0] } ?? 0
            let need = max(0, card.cost[token, default: 0] - discount)
            return partial + max(0, need - coloredPayment[token, default: 0])
        }
    }
    private var paymentValid: Bool { goldRequired <= player.tokens[.gold, default: 0] }
    private var availableAtEnd: [DuelTokenColor: Int] {
        var result = player.tokens
        for (color, count) in payment { result[color, default: 0] -= count }
        if card.ability == .takeMatchingToken, !matchingBoardIndices.isEmpty, abilityBoardIndex != nil,
           let effectiveColor {
            result[DuelTokenColor(effectiveColor), default: 0] += 1
        }
        if card.ability == .stealToken, let stolenToken { result[stolenToken, default: 0] += 1 }
        if selectedRoyal?.ability == .stealToken, let royalStolenToken { result[royalStolenToken, default: 0] += 1 }
        return result
    }
    private var requiredReturns: Int { max(0, availableAtEnd.values.reduce(0, +) - DuelRules.tokenLimit) }
    private var choicesValid: Bool {
        if card.isWildBonus, wildColor == nil { return false }
        if card.ability == .takeMatchingToken, !matchingBoardIndices.isEmpty, abilityBoardIndex == nil { return false }
        if card.ability == .stealToken, !stealable.isEmpty, stolenToken == nil { return false }
        if earnedRoyal, royalID == nil { return false }
        if selectedRoyal?.ability == .stealToken, !stealable.isEmpty, royalStolenToken == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                DuelJewelCardView(card: card, enlarged: true, affordable: paymentValid)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                if allowsPurchase {
                    paymentSection
                    choiceSections
                    if requiredReturns > 0 {
                        DuelReturnEditor(available: availableAtEnd, required: requiredReturns, returning: $returning)
                    }
                }

                Section {
                    if allowsPurchase {
                        Button("duel.purchase") { submit() }
                            .frame(maxWidth: .infinity)
                            .disabled(!paymentValid || !choicesValid || returning.values.reduce(0, +) != requiredReturns)
                    }
                    if let onReserve {
                        Button("duel.reserve", action: onReserve)
                            .frame(maxWidth: .infinity)
                            .disabled(player.reservedCardCount >= DuelRules.reserveLimit || !duel.board.contains(.gold))
                    }
                }
            }
            .navigationTitle("duel.card.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.close") { dismiss() } } }
        }
        .onAppear { configureDefaults() }
    }

    @ViewBuilder private var paymentSection: some View {
        Section("duel.payment.title") {
            ForEach(DuelTokenColor.boardTakeable, id: \.self) { token in
                let discount = token.gemColor.map { player.bonuses[$0, default: 0] } ?? 0
                let need = max(0, card.cost[token, default: 0] - discount)
                if need > 0 {
                    Stepper(value: paymentBinding(token), in: 0 ... min(need, player.tokens[token, default: 0])) {
                        HStack {
                            DuelTokenChip(color: token, diameter: 25)
                            Text(token.localizedKey)
                            Spacer()
                            Text("\(coloredPayment[token, default: 0]) / \(need)").monospacedDigit()
                        }
                    }
                }
            }
            LabeledContent("duel.payment.gold", value: "\(goldRequired) / \(player.tokens[.gold, default: 0])")
                .foregroundStyle(paymentValid ? Color.primary : Color.red)
            Text("duel.payment.hint").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var choiceSections: some View {
        if card.isWildBonus {
            Section("duel.wild.choose") {
                Picker("duel.wild.color", selection: $wildColor) {
                    ForEach(DuelGemColor.allCases.filter { player.bonuses[$0, default: 0] > 0 }) { color in
                        Label(color.localizedKey, systemImage: color.iconName).tag(Optional(color))
                    }
                }
            }
        }
        if card.ability == .takeMatchingToken, !matchingBoardIndices.isEmpty {
            boardPositionSection(title: "duel.ability.chooseBoardToken", indices: matchingBoardIndices, selection: $abilityBoardIndex)
        }
        if card.ability == .stealToken, !stealable.isEmpty {
            tokenPickerSection(title: "duel.ability.chooseStolen", selection: $stolenToken)
        }
        if earnedRoyal {
            Section("duel.royal.choose") {
                ForEach(duel.availableRoyals) { royal in
                    Button { royalID = royal.id } label: {
                        HStack {
                            DuelRoyalCardView(royal: royal)
                            Image(systemName: royalID == royal.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(royalID == royal.id ? Color.accentColor : .secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            if selectedRoyal?.ability == .stealToken, !stealable.isEmpty {
                tokenPickerSection(title: "duel.royal.chooseStolen", selection: $royalStolenToken)
            }
        }
    }

    private func boardPositionSection(
        title: LocalizedStringKey,
        indices: [Int],
        selection: Binding<Int?>
    ) -> some View {
        Section(title) {
            HStack {
                ForEach(indices, id: \.self) { index in
                    Button { selection.wrappedValue = index } label: {
                        VStack(spacing: 3) {
                            DuelTokenChip(color: duel.board[index]!, diameter: 32, selected: selection.wrappedValue == index)
                            Text("\(index / 5 + 1),\(index % 5 + 1)").font(.caption2.monospacedDigit())
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func tokenPickerSection(title: LocalizedStringKey, selection: Binding<DuelTokenColor?>) -> some View {
        Section(title) {
            HStack {
                ForEach(stealable) { token in
                    Button { selection.wrappedValue = token } label: {
                        DuelTokenChip(color: token, count: opponent.tokens[token], diameter: 34, selected: selection.wrappedValue == token)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func paymentBinding(_ token: DuelTokenColor) -> Binding<Int> {
        Binding(get: { coloredPayment[token, default: 0] }, set: { coloredPayment[token] = $0; returning = [:] })
    }

    private func configureDefaults() {
        for token in DuelTokenColor.boardTakeable {
            let discount = token.gemColor.map { player.bonuses[$0, default: 0] } ?? 0
            let need = max(0, card.cost[token, default: 0] - discount)
            coloredPayment[token] = min(need, player.tokens[token, default: 0])
        }
        wildColor = DuelGemColor.allCases.first { player.bonuses[$0, default: 0] > 0 }
        abilityBoardIndex = matchingBoardIndices.first
        stolenToken = stealable.first
        if earnedRoyal {
            royalID = duel.availableRoyals.first?.id
            royalStolenToken = stealable.first
        }
    }

    private func submit() {
        let choices = DuelPurchaseChoices(
            wildBonusColor: card.isWildBonus ? wildColor : nil,
            abilityBoardIndex: card.ability == .takeMatchingToken ? abilityBoardIndex : nil,
            stolenToken: card.ability == .stealToken ? stolenToken : nil,
            royalID: earnedRoyal ? royalID : nil,
            royalStolenToken: selectedRoyal?.ability == .stealToken ? royalStolenToken : nil
        )
        onPurchase(payment, choices, returning.filter { $0.value > 0 })
        dismiss()
    }
}

struct DuelReservedCardsSheet: View {
    let cards: [DuelJewelCard]
    let player: DuelPublicPlayerSnapshot
    let onSelect: (DuelJewelCard) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView("duel.reserved.empty", systemImage: "rectangle.stack")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 12)], spacing: 12) {
                            ForEach(cards) { card in
                                Button {
                                    dismiss()
                                    onSelect(card)
                                } label: {
                                    DuelJewelCardView(card: card, enlarged: true, affordable: duelCanPurchase(card, player: player))
                                }.buttonStyle(.plain)
                            }
                        }.padding()
                    }
                }
            }
            .navigationTitle("duel.reserved.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.close") { dismiss() } } }
        }
    }
}
