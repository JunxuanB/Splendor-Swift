import LuminoreCore
import SwiftUI

enum DuelBoardPage: String, CaseIterable, Identifiable {
    case tokens
    case cards

    var id: String { rawValue }
    var titleKey: LocalizedStringKey { self == .tokens ? "duel.page.tokens" : "duel.page.cards" }
}

struct DuelVictoryHeader: View {
    let player: DuelPublicPlayerSnapshot

    var body: some View {
        HStack(spacing: 9) {
            track(icon: "trophy", tint: .blue, current: player.prestige, target: DuelRules.targetPrestige)
            Divider().frame(height: 27)
            track(icon: "crown", tint: .orange, current: player.crowns, target: DuelRules.targetCrowns)
            Divider().frame(height: 27)
            track(icon: "paintpalette", tint: .purple, current: player.colorPrestige.values.max() ?? 0,
                  target: DuelRules.targetColorPrestige)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func track(icon: String, tint: Color, current: Int, target: Int) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(tint)
                Text("\(current)/\(target)").font(.caption.bold().monospacedDigit())
            }
            ProgressView(value: Double(min(current, target)), total: Double(target)).tint(tint)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DuelOpponentPanel: View {
    let identity: PublicPlayerSnapshot
    let duelPlayer: DuelPublicPlayerSnapshot
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Label(identity.nickname, systemImage: identity.kind == .bot ? "cpu" : "person.crop.circle")
                    .font(.headline)
                if !identity.isConnected {
                    Image(systemName: "wifi.slash").foregroundStyle(.orange).font(.caption)
                }
                Spacer(minLength: 0)
                stat("\(duelPlayer.prestige)", icon: "trophy", tint: .blue)
                Divider().frame(height: 24)
                stat("\(duelPlayer.crowns)", icon: "crown", tint: .orange)
                Divider().frame(height: 24)
                stat("\(duelPlayer.colorPrestige.values.max() ?? 0)", icon: "paintpalette", tint: .purple)
                Divider().frame(height: 24)
                stat("\(duelPlayer.reservedCardCount)/3", icon: "rectangle.stack", tint: .secondary)
                Divider().frame(height: 24)
                stat("\(duelPlayer.privileges)", icon: "wand.and.stars", tint: .purple)
            }
            resourceRow(duelPlayer)
            colorPointRow(duelPlayer.colorPrestige)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isCurrent ? Color.accentColor.opacity(0.75) : .primary.opacity(0.08), lineWidth: isCurrent ? 2.5 : 1)
        }
    }

    private func stat(_ value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.bold().monospacedDigit())
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint)
        }
    }
}

struct DuelPlayerInventoryBar: View {
    let player: DuelPublicPlayerSnapshot
    let isCurrent: Bool
    let deadline: Date?
    let turnDurationSeconds: Int?
    let onOpenReserved: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenReserved) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(player.prestige)").font(.title2.bold().monospacedDigit())
                    Label("\(player.crowns)", systemImage: "crown").foregroundStyle(.orange)
                    HStack(spacing: 2) {
                        Text("\(player.reservedCardCount)/3")
                        Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                    }
                }
                .font(.caption.bold())
                .frame(width: 48, alignment: .leading)
            }
            .buttonStyle(.plain)
            Divider().frame(height: 72)
            VStack(spacing: 3) {
                resourceRow(player)
                colorPointRow(player.colorPrestige)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            if isCurrent {
                TurnProgressBar(deadline: deadline, duration: turnDurationSeconds)
            } else {
                Divider()
            }
        }
    }
}

@ViewBuilder
private func resourceRow(_ player: DuelPublicPlayerSnapshot) -> some View {
    HStack(spacing: 4) {
        ForEach(DuelTokenColor.allCases) { color in
            DuelResourceStack(
                color: color,
                bonus: color.gemColor.map { player.bonuses[$0, default: 0] } ?? 0,
                tokens: player.tokens[color, default: 0]
            )
            .frame(maxWidth: .infinity)
        }
    }
}

@ViewBuilder
private func colorPointRow(_ points: [DuelGemColor: Int]) -> some View {
    HStack(spacing: 4) {
        ForEach(DuelGemColor.allCases) { color in
            Text("\(points[color, default: 0])")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(points[color, default: 0] > 0 ? color.foreground : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 14)
                .background(color.tint.opacity(points[color, default: 0] > 0 ? 0.88 : 0.12), in: RoundedRectangle(cornerRadius: 4))
        }
        Color.clear.frame(maxWidth: .infinity, maxHeight: 14)
        Color.clear.frame(maxWidth: .infinity, maxHeight: 14)
    }
}

struct DuelTokenBoardSection: View {
    let duel: DuelClientSnapshot
    let player: DuelPublicPlayerSnapshot
    let isLocalTurn: Bool
    @Binding var selectedIndices: [Int]
    @Binding var privilegeMode: Bool
    let onTapToken: (Int) -> Void
    let onConfirmTake: () -> Void
    let onReplenish: () -> Void
    let onSkipTurn: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                Label(privilegeMode ? "duel.privilege.choose" : "duel.board.title",
                      systemImage: privilegeMode ? "wand.and.stars" : "circle.grid.3x3")
                    .font(.caption2.bold())
                    .foregroundStyle(privilegeMode ? Color.accentColor : .secondary)
                Spacer()
                info(icon: "bag", text: "\(duel.bagCount)")
                info(icon: "wand.and.stars", text: "\(duel.privilegesInPool)")
            }

            HStack(alignment: .top, spacing: 10) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(duel.board.indices, id: \.self) { index in
                        if let color = duel.board[index] {
                            Button { onTapToken(index) } label: {
                                DuelTokenChip(
                                    color: color,
                                    diameter: 46,
                                    selected: selectedIndices.contains(index),
                                    dimmed: !isLocalTurn || color == .gold
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(!isLocalTurn)
                        } else {
                            Circle().strokeBorder(.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 46, height: 46).frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background {
                    // Faint dashed guide tracing the center-out spiral refill route.
                    DuelSpiralPath(order: DuelRules.spiralOrder, spacing: 6)
                        .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2.5, 3.5]))
                        .foregroundStyle(.primary.opacity(0.12))
                        .allowsHitTesting(false)
                }

                VStack(spacing: 8) {
                    if selectedIndices.isEmpty {
                        if privilegeMode {
                            privilegeButton.buttonStyle(.borderedProminent)
                        } else {
                            privilegeButton.buttonStyle(.bordered)
                        }

                        Button(action: onReplenish) {
                            VStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("duel.replenish")
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isLocalTurn || duel.bagCount == 0 || duel.turnStage != .privilegesAvailable)

                        Button(action: onSkipTurn) {
                            VStack(spacing: 2) {
                                Image(systemName: "forward.end.fill")
                                Text("duel.skipTurn")
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .disabled(!isLocalTurn)
                    } else {
                        Button("duel.take", action: onConfirmTake).buttonStyle(.borderedProminent)
                        Button("common.cancel") { selectedIndices = [] }.buttonStyle(.bordered)
                    }
                }
                .font(.caption2.bold())
                .controlSize(.small)
                .frame(width: 66)
            }

            Text("duel.privilege.legend")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(11)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(privilegeMode ? Color.accentColor : .primary.opacity(0.06), lineWidth: privilegeMode ? 2 : 1))
    }

    private var privilegeButton: some View {
        Button {
            privilegeMode.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "wand.and.stars")
                Text("duel.privilege.use")
                Text("×\(player.privileges)").monospacedDigit()
            }.frame(maxWidth: .infinity)
        }
        .disabled(!isLocalTurn || player.privileges == 0 || duel.turnStage != .privilegesAvailable)
    }

    private func info(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text).monospacedDigit()
        }
        .font(.caption2.bold()).foregroundStyle(.secondary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.secondary.opacity(0.12), in: Capsule())
    }
}

struct DuelCardBoardSection: View {
    let duel: DuelClientSnapshot
    let player: DuelPublicPlayerSnapshot
    let isLocalTurn: Bool
    let showsHighlight: Bool
    let onSelectCard: (DuelJewelCard, DuelCardSource) -> Void
    let onReserveDeck: (Int) -> Void
    let onSelectRoyal: (DuelRoyalCard) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach([3, 2, 1], id: \.self) { tier in
                    HStack(spacing: 4) {
                        Button { onReserveDeck(tier) } label: {
                            VStack(spacing: 2) {
                                Text(["", "Ⅰ", "Ⅱ", "Ⅲ"][tier]).font(.caption.bold())
                                Image(systemName: "rectangle.stack")
                                Text("\(duel.deckCounts[tier, default: 0])").font(.caption2.bold().monospacedDigit())
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 29, height: 94)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isLocalTurn || duel.deckCounts[tier, default: 0] == 0 || player.reservedCardCount >= 3
                                  || !duel.board.contains(.gold))

                        ForEach(duel.market[tier, default: []]) { card in
                            Button { onSelectCard(card, .market(cardID: card.id)) } label: {
                                DuelJewelCardView(
                                    card: card,
                                    affordable: showsHighlight && duelCanPurchase(card, player: player)
                                )
                            }.buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
                royalSection
            }
            .padding(.vertical, 2)
        }
    }

    private var royalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill").font(.caption2)
                Text("duel.royal.title").font(.caption2.bold())
                Spacer()
                Text("duel.royal.hint").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 0.20))

            if duel.availableRoyals.isEmpty {
                Text("duel.royal.empty")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    ForEach(duel.availableRoyals) { royal in
                        Button { onSelectRoyal(royal) } label: {
                            DuelRoyalCardView(royal: royal).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

func duelCanPurchase(_ card: DuelJewelCard, player: DuelPublicPlayerSnapshot) -> Bool {
    // A wild bonus must stack onto an existing gem engine, so it cannot be a first card.
    if card.isWildBonus, !DuelGemColor.allCases.contains(where: { player.bonuses[$0, default: 0] > 0 }) { return false }
    var gold = player.tokens[.gold, default: 0]
    for token in DuelTokenColor.boardTakeable {
        let discount = token.gemColor.map { player.bonuses[$0, default: 0] } ?? 0
        let need = max(0, card.cost[token, default: 0] - discount)
        gold -= max(0, need - player.tokens[token, default: 0])
    }
    return gold >= 0
}
