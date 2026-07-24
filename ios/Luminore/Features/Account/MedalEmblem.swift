import SwiftUI

/// A restrained metal palette driven by the winner's score margin. Older
/// records have no margin and intentionally fall back to neutral silver.
struct MedalEmblem: View {
    let issuerUUID: UUID
    var scoreMargin: Int?
    var size: CGFloat = 76

    private var seed: Int {
        issuerUUID.uuidString.utf8.reduce(17) { partial, byte in
            partial &* 31 &+ Int(byte)
        } & 0x7fff_ffff
    }

    private var style: MedalMetalStyle {
        MedalMetalStyle(scoreMargin: scoreMargin)
    }

    var body: some View {
        ZStack {
            HStack(spacing: size * 0.025) {
                ribbon.rotationEffect(.degrees(8))
                ribbon.rotationEffect(.degrees(-8))
            }
            .offset(y: -size * 0.18)

            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            style.edge,
                            style.highlight,
                            style.mid,
                            style.edge,
                            style.highlight,
                            style.mid,
                            style.edge
                        ],
                        center: .center,
                        angle: .degrees(Double(seed % 28) - 14)
                    )
                )
                .overlay {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [style.highlight, style.mid, style.edge],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: size * 0.46
                            )
                        )
                        .padding(size * 0.085)
                }
                .overlay {
                    Circle()
                        .strokeBorder(style.rim.opacity(0.88), lineWidth: max(1.2, size * 0.024))
                        .padding(size * 0.055)
                    Circle()
                        .strokeBorder(.white.opacity(0.24), lineWidth: 1)
                        .padding(size * 0.115)
                }
                .overlay {
                    brushedMetalDetails
                }
                .overlay {
                    VStack(spacing: size * 0.015) {
                        Image(systemName: style.symbolName)
                            .font(.system(size: size * 0.23, weight: .semibold))
                        if let scoreMargin {
                            Text("+\(scoreMargin)")
                                .font(.system(size: size * 0.105, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(style.engraving)
                    .shadow(color: .white.opacity(0.25), radius: 0.5, y: 1)
                }
                .frame(width: size * 0.74, height: size * 0.74)
                .offset(y: size * 0.1)
                .shadow(color: style.shadow, radius: size * 0.09, y: size * 0.055)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var ribbon: some View {
        RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [style.ribbonHighlight, style.ribbon],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, size * 0.04)
            }
            .frame(width: size * 0.2, height: size * 0.5)
    }

    private var brushedMetalDetails: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .trim(from: 0.08 + Double(index) * 0.12, to: 0.25 + Double(index) * 0.12)
                    .stroke(.white.opacity(0.13), lineWidth: max(0.7, size * 0.01))
                    .padding(size * (0.15 + CGFloat(index) * 0.035))
                    .rotationEffect(.degrees(Double(seed % 90)))
            }
        }
    }
}

private struct MedalMetalStyle {
    let edge: Color
    let mid: Color
    let highlight: Color
    let rim: Color
    let engraving: Color
    let ribbon: Color
    let ribbonHighlight: Color
    let shadow: Color
    let symbolName: String

    init(scoreMargin: Int?) {
        guard let scoreMargin else {
            edge = Color(hue: 0.61, saturation: 0.05, brightness: 0.42)
            mid = Color(hue: 0.6, saturation: 0.035, brightness: 0.7)
            highlight = Color(hue: 0.58, saturation: 0.025, brightness: 0.94)
            rim = Color(hue: 0.6, saturation: 0.04, brightness: 0.82)
            engraving = Color(hue: 0.61, saturation: 0.08, brightness: 0.35)
            ribbon = Color(hue: 0.61, saturation: 0.16, brightness: 0.31)
            ribbonHighlight = Color(hue: 0.6, saturation: 0.12, brightness: 0.48)
            shadow = .black.opacity(0.22)
            symbolName = "seal.fill"
            return
        }

        switch scoreMargin {
        case 0 ... 2:
            edge = Color(hue: 0.57, saturation: 0.11, brightness: 0.42)
            mid = Color(hue: 0.56, saturation: 0.09, brightness: 0.72)
            highlight = Color(hue: 0.55, saturation: 0.05, brightness: 0.96)
            rim = Color(hue: 0.56, saturation: 0.1, brightness: 0.85)
            engraving = Color(hue: 0.58, saturation: 0.18, brightness: 0.33)
            ribbon = Color(hue: 0.58, saturation: 0.25, brightness: 0.35)
            ribbonHighlight = Color(hue: 0.57, saturation: 0.2, brightness: 0.52)
            shadow = Color(hue: 0.57, saturation: 0.18, brightness: 0.3).opacity(0.24)
            symbolName = "shield.fill"
        case 3 ... 5:
            edge = Color(hue: 0.075, saturation: 0.32, brightness: 0.38)
            mid = Color(hue: 0.08, saturation: 0.25, brightness: 0.68)
            highlight = Color(hue: 0.09, saturation: 0.14, brightness: 0.93)
            rim = Color(hue: 0.085, saturation: 0.28, brightness: 0.78)
            engraving = Color(hue: 0.065, saturation: 0.38, brightness: 0.31)
            ribbon = Color(hue: 0.02, saturation: 0.3, brightness: 0.34)
            ribbonHighlight = Color(hue: 0.025, saturation: 0.24, brightness: 0.52)
            shadow = Color(hue: 0.07, saturation: 0.3, brightness: 0.28).opacity(0.25)
            symbolName = "star.fill"
        case 6 ... 9:
            edge = Color(hue: 0.115, saturation: 0.3, brightness: 0.42)
            mid = Color(hue: 0.12, saturation: 0.25, brightness: 0.72)
            highlight = Color(hue: 0.125, saturation: 0.14, brightness: 0.97)
            rim = Color(hue: 0.12, saturation: 0.32, brightness: 0.83)
            engraving = Color(hue: 0.1, saturation: 0.42, brightness: 0.33)
            ribbon = Color(hue: 0.1, saturation: 0.28, brightness: 0.32)
            ribbonHighlight = Color(hue: 0.105, saturation: 0.23, brightness: 0.5)
            shadow = Color(hue: 0.11, saturation: 0.35, brightness: 0.3).opacity(0.25)
            symbolName = "sparkles"
        default:
            edge = Color(hue: 0.12, saturation: 0.14, brightness: 0.16)
            mid = Color(hue: 0.115, saturation: 0.16, brightness: 0.38)
            highlight = Color(hue: 0.12, saturation: 0.2, brightness: 0.72)
            rim = Color(hue: 0.125, saturation: 0.32, brightness: 0.86)
            engraving = Color(hue: 0.125, saturation: 0.24, brightness: 0.94)
            ribbon = Color(hue: 0.68, saturation: 0.2, brightness: 0.22)
            ribbonHighlight = Color(hue: 0.68, saturation: 0.16, brightness: 0.38)
            shadow = .black.opacity(0.35)
            symbolName = "crown.fill"
        }
    }
}
