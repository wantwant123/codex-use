import SwiftUI

enum SurfaceStyle {
    static let cardCornerRadius: CGFloat = 14
    static let tileCornerRadius: CGFloat = 10
    static let pillCornerRadius: CGFloat = 8

    static func accent(for tool: UsageTool) -> Color {
        switch tool {
        case .codex:
            Color(red: 0.14, green: 0.68, blue: 0.56)
        case .antigravity:
            Color(red: 0.36, green: 0.44, blue: 0.96)
        }
    }

    static func remainingColor(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        let clamped = UsageMath.clampPercent(percent) / 100
        return Color(
            hue: 0.34 * clamped,
            saturation: 0.80,
            brightness: 0.82
        )
    }
}

struct PanelCardModifier: ViewModifier {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = SurfaceStyle.cardCornerRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 0.75)
            )
    }
}

struct InsetTileModifier: ViewModifier {
    var padding: CGFloat = 8
    var cornerRadius: CGFloat = SurfaceStyle.tileCornerRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

struct StatusPillView: View {
    let title: String
    let tint: Color
    var showDot: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if showDot {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
            }
            Text(verbatim: title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(showDot ? .primary : tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.24), lineWidth: 0.5)
        )
    }
}

extension View {
    func panelCard(padding: CGFloat = 12, cornerRadius: CGFloat = SurfaceStyle.cardCornerRadius) -> some View {
        modifier(PanelCardModifier(padding: padding, cornerRadius: cornerRadius))
    }

    func insetTile(padding: CGFloat = 8, cornerRadius: CGFloat = SurfaceStyle.tileCornerRadius) -> some View {
        modifier(InsetTileModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
