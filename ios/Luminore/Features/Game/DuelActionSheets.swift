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
            ScrollView {
                VStack(spacing: 18) {
                    if let card {
                        DuelJewelCardView(card: card, enlarged: true).frame(width: 190)
                    } else if case let .deck(tier) = source {
                        deckHeader(tier)
                    }

                    DuelSheetSection(titleKey: "duel.reserve.chooseGold") {
                        DuelMiniBoardPicker(board: duel.board, selectableIndices: goldIndices, selection: $selectedGoldIndex)
                        Text("duel.reserve.goldPositionHint").font(.footnote).foregroundStyle(.secondary)
                    }

                    if requiredReturns > 0 {
                        DuelSheetSection(titleKey: "duel.return.title") {
                            DuelReturnControls(available: availableAfterGold, required: requiredReturns, returning: $returning)
                        }
                    }

                    Button("duel.reserve") {
                        if let selectedGoldIndex {
                            onConfirm(selectedGoldIndex, returning.filter { $0.value > 0 })
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(selectedGoldIndex == nil || returning.values.reduce(0, +) != requiredReturns)
                }
                .padding(20)
            }
            .navigationTitle("duel.reserve.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { selectedGoldIndex = goldIndices.first }
    }

    private func deckHeader(_ tier: Int) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.fill").font(.largeTitle).foregroundStyle(.secondary)
            Text(["", "Ⅰ", "Ⅱ", "Ⅲ"][tier]).font(.title3.bold())
            Text("duel.reserve.fromDeck").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// A titled rounded container used inside the Duel sheets — the sheet equivalent of
/// a grouped `Form` section, but usable in a plain `VStack`/`ScrollView`.
struct DuelSheetSection<Content: View>: View {
    let titleKey: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titleKey).font(.subheadline.bold()).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Token-return steppers usable outside a `Form` (for the centered-style sheets).
struct DuelReturnControls: View {
    let available: [DuelTokenColor: Int]
    let required: Int
    @Binding var returning: [DuelTokenColor: Int]

    var body: some View {
        VStack(spacing: 8) {
            Text("duel.return.required \(required)")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(DuelTokenColor.allCases) { color in
                let held = available[color, default: 0]
                if held > 0 {
                    Stepper(value: binding(color), in: 0 ... held) {
                        HStack {
                            DuelTokenChip(color: color, diameter: 26)
                            Text(color.localizedKey)
                            Spacer()
                            Text("\(returning[color, default: 0]) / \(held)").monospacedDigit()
                        }
                    }
                }
            }
            LabeledContent("duel.return.remaining", value: "\(max(0, required - returning.values.reduce(0, +)))")
                .font(.footnote)
        }
    }

    private func binding(_ color: DuelTokenColor) -> Binding<Int> {
        Binding(get: { returning[color, default: 0] }, set: { returning[color] = $0 })
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
            ScrollView {
                VStack(spacing: 18) {
                    DuelJewelCardView(card: card, enlarged: true, affordable: paymentValid)
                        .frame(width: 190)

                    bonusCapsule

                    if let ability = card.ability {
                        Label(ability.localizedKey, systemImage: ability.iconName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.purple)
                    }

                    if allowsPurchase {
                        choiceSections
                        if requiredReturns > 0 {
                            DuelSheetSection(titleKey: "duel.return.title") {
                                DuelReturnControls(available: availableAtEnd, required: requiredReturns, returning: $returning)
                            }
                        }
                        paymentSummary
                    }

                    actionButtons
                }
                .padding(20)
            }
            .navigationTitle("duel.card.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { configureDefaults() }
    }

    private var bonusCapsule: some View {
        let gold = Color(red: 0.80, green: 0.62, blue: 0.20)
        let hasBonus = card.isWildBonus || card.bonusColor != nil
        let tint = card.isWildBonus ? Color.purple : (card.bonusColor?.tint ?? gold)
        return HStack(spacing: 7) {
            Image(systemName: hasBonus ? (card.isWildBonus ? "sparkles" : (card.bonusColor?.iconName ?? "questionmark")) : "crown.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                if hasBonus {
                    Text("duel.bonus.permanent").font(.caption).foregroundStyle(.secondary)
                    if card.isWildBonus {
                        Text("duel.bonus.wild")
                    } else if let color = card.bonusColor {
                        Text("\(card.bonusAmount) × ") + Text(color.localizedKey)
                    }
                } else {
                    // Prestige-only card: no permanent gem bonus.
                    Text("duel.bonus.pointsOnly")
                }
            }
            if card.crowns > 0 { DuelCardCrowns(count: card.crowns, size: 13) }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(hasBonus ? 0.12 : 0.18), in: Capsule())
    }

    @ViewBuilder private var choiceSections: some View {
        if card.isWildBonus {
            DuelSheetSection(titleKey: "duel.wild.choose") {
                HStack(spacing: 8) {
                    ForEach(DuelGemColor.allCases.filter { player.bonuses[$0, default: 0] > 0 }) { color in
                        Button { wildColor = color } label: {
                            DuelTokenChip(color: color.tokenColor, diameter: 38, selected: wildColor == color)
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        if card.ability == .takeMatchingToken, !matchingBoardIndices.isEmpty {
            DuelSheetSection(titleKey: "duel.ability.chooseBoardToken") {
                DuelMiniBoardPicker(board: duel.board, selectableIndices: matchingBoardIndices, selection: $abilityBoardIndex)
            }
        }
        if card.ability == .stealToken, !stealable.isEmpty {
            DuelSheetSection(titleKey: "duel.ability.chooseStolen") {
                stealPicker(selection: $stolenToken)
            }
        }
        if earnedRoyal {
            DuelSheetSection(titleKey: "duel.royal.choose") {
                Label("duel.royal.chooseRequired", systemImage: "crown.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 0.20))
                HStack(spacing: 8) {
                    ForEach(duel.availableRoyals) { royal in
                        Button { royalID = royal.id } label: {
                            DuelRoyalCardView(royal: royal)
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: royalID == royal.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(royalID == royal.id ? Color.accentColor : .secondary)
                                        .padding(5)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(Color.accentColor, lineWidth: royalID == royal.id ? 2 : 0)
                                }
                        }.buttonStyle(.plain)
                    }
                }
            }
            if selectedRoyal?.ability == .stealToken, !stealable.isEmpty {
                DuelSheetSection(titleKey: "duel.royal.chooseStolen") {
                    stealPicker(selection: $royalStolenToken)
                }
            }
        }
    }

    private func stealPicker(selection: Binding<DuelTokenColor?>) -> some View {
        HStack(spacing: 8) {
            ForEach(stealable) { token in
                Button { selection.wrappedValue = token } label: {
                    DuelTokenChip(color: token, count: opponent.tokens[token], diameter: 38, selected: selection.wrappedValue == token)
                }.buttonStyle(.plain)
            }
        }
    }

    private var paymentSummary: some View {
        DuelSheetSection(titleKey: "duel.payment.title") {
            let spend = payment.filter { $0.value > 0 }.sorted { $0.key.rawValue < $1.key.rawValue }
            if spend.isEmpty {
                Text("duel.payment.free").font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(spend, id: \.key) { token, count in
                        DuelTokenChip(color: token, count: count, diameter: 32)
                    }
                }
            }
            LabeledContent("duel.payment.gold") {
                Text("\(goldRequired) / \(player.tokens[.gold, default: 0])").monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(paymentValid ? Color.secondary : Color.red)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let onReserve {
                Button("duel.reserve", action: onReserve)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(player.reservedCardCount >= DuelRules.reserveLimit || !duel.board.contains(.gold))
            }
            if allowsPurchase {
                Button("duel.purchase") { submit() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!paymentValid || !choicesValid || returning.values.reduce(0, +) != requiredReturns)
            }
        }
        .controlSize(.large)
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
            // Do NOT pre-select a royal: reaching 3 or 6 crowns must prompt the player
            // to choose one explicitly (the buy button stays disabled until they do).
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Informational detail for a royal card tapped on the board. Royals are claimed
/// automatically during a purchase that crosses a crown threshold, so this sheet
/// just explains the card and when it can be claimed — mirroring `NobleDetailSheet`.
struct DuelRoyalDetailSheet: View {
    let royal: DuelRoyalCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                DuelRoyalCardView(royal: royal, enlarged: true).frame(width: 200)

                if let ability = royal.ability {
                    Label(ability.localizedKey, systemImage: ability.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)
                }

                Text("duel.royal.explain")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("duel.royal.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.close") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
