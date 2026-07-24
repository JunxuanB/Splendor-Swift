import SwiftUI

/// 宝石版图 — the signature Duel panel. A 5×5 gem board where you tap up to three
/// tokens in a straight adjacent line to take them. The header shows the bag count
/// and the central privilege pool; the action column groups 使用权杖 (top) and
/// 补充版图 (below); the footer explains the three ways to gain 权杖.
struct DuelTokenBoard: View {
    @ObservedObject var state: DuelGameState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        VStack(spacing: 10) {
            header

            HStack(alignment: .top, spacing: 10) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(state.board) { cell in
                        cellView(cell)
                    }
                }
                .frame(maxWidth: .infinity)
                .background {
                    // Faint guide tracing the center-out spiral refill route.
                    DuelSpiralPath(order: DuelGameState.spiralOrder, spacing: 6)
                        .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2.5, 3.5]))
                        .foregroundStyle(.primary.opacity(0.12))
                        .allowsHitTesting(false)
                }

                actionColumn
                    .frame(width: 66)
            }

            DuelPrivilegeLegend()
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(state.privilegeMode ? Color.accentColor.opacity(0.8) : .primary.opacity(0.06),
                              lineWidth: state.privilegeMode ? 2 : 1)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if state.privilegeMode {
                Label("点选 1 枚宝石使用权杖", systemImage: DuelSymbol.privilege)
                    .font(.caption2.bold())
                    .foregroundStyle(Color.accentColor)
            } else {
                Label("宝石版图", systemImage: "circle.grid.3x3.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            infoPill(icon: DuelSymbol.bag, text: "袋 \(state.bagRemaining)", tint: .secondary)
            infoPill(icon: DuelSymbol.privilege, text: "可获取权杖 \(state.privilegesOnBoard)",
                     tint: Color(red: 0.52, green: 0.36, blue: 0.72))
        }
    }

    private func infoPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.caption2.bold().monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
    }

    // MARK: Board cells

    @ViewBuilder
    private func cellView(_ cell: DuelBoardCell) -> some View {
        if let color = cell.token {
            Button {
                withAnimation(.snappy) { state.tapCell(cell.index) }
            } label: {
                DuelBoardToken(
                    color: color,
                    diameter: 46,
                    isSelected: state.isSelected(cell.index),
                    isSelectable: color != .gold
                )
                .frame(maxWidth: .infinity)
                .duelFlightAnchor(.boardCell(cell.index))
            }
            .buttonStyle(.plain)
            .disabled(color == .gold && !state.privilegeMode)
            .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .strokeBorder(.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 46, height: 46)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    // MARK: Action column

    @ViewBuilder
    private var actionColumn: some View {
        VStack(spacing: 8) {
            if state.hasSelection {
                selectedPreview
                Button("拿取") { withAnimation(.snappy) { state.confirmTake() } }
                    .buttonStyle(.borderedProminent)
                Button("取消") { withAnimation(.snappy) { state.cancelSelection() } }
                    .buttonStyle(.bordered)
            } else {
                // Use privileges first, then replenish — the required order if you do both.
                privilegeButton
                    .disabled(state.player.privileges == 0)
                refillButton
                    .disabled(state.bagRemaining == 0 || !state.board.contains { $0.token == nil })
            }
        }
        .font(.caption2.bold())
        .controlSize(.small)
    }

    @ViewBuilder
    private var privilegeButton: some View {
        let button = Button {
            withAnimation(.snappy) { state.togglePrivilegeMode() }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: DuelSymbol.privilege)
                Text("使用权杖")
                Text("×\(state.player.privileges)").monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }

        if state.privilegeMode {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var refillButton: some View {
        Button {
            withAnimation(.snappy) { state.refillBoard() }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("补充版图")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var selectedPreview: some View {
        HStack(spacing: 2) {
            ForEach(Array(state.selectedColors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color.tint)
                    .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(height: 14)
    }
}

/// Footer legend: the three ways a player gains 权杖.
struct DuelPrivilegeLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("对手触发·我获权杖")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            item(icon: "3.circle.fill", text: "拿3同色")
            item(icon: DuelColor.pearl.iconName, text: "拿2珍珠")
            item(icon: "arrow.triangle.2.circlepath", text: "补版图")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color(red: 0.52, green: 0.36, blue: 0.72).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func item(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(Color(red: 0.46, green: 0.32, blue: 0.64))
    }
}

/// Connects the centers of the board spaces in refill (spiral) order — center-out,
/// ending at the bottom-right corner.
struct DuelSpiralPath: Shape {
    let order: [Int]
    var columns = 5
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard columns > 0 else { return path }
        let cellWidth = (rect.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (rect.height - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        func center(_ index: Int) -> CGPoint {
            let row = index / columns, col = index % columns
            return CGPoint(
                x: CGFloat(col) * (cellWidth + spacing) + cellWidth / 2,
                y: CGFloat(row) * (cellHeight + spacing) + cellHeight / 2
            )
        }

        for (offset, index) in order.enumerated() {
            let point = center(index)
            if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
