import SwiftUI

struct QuotaBatteryView: View {
    let percent: Double?
    let color: Color
    var height: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let outerRadius = height * 0.28
        let innerPadding = max(4, height * 0.11)
        let innerRadius = max(6, outerRadius - innerPadding * 0.7)

        HStack(spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Subtle lower shell edge for depth.
                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .fill(.black.opacity(0.18))
                        .offset(y: 3.5)

                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.primary.opacity(0.15), .primary.opacity(0.04), .primary.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))

                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.68), color, color.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: max(0, geometry.size.width - innerPadding * 2) * fraction)
                        .padding(innerPadding)

                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .strokeBorder(LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.06), .primary.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ), lineWidth: 1)

                    Capsule()
                        .fill(.white.opacity(0.28))
                        .frame(height: 2.5)
                        .padding(.horizontal, 14)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, innerPadding + 2.5)
                }
            }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(
                    colors: [.primary.opacity(0.14), .primary.opacity(0.36)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 6.5, height: height * 0.42)
        }
        .frame(height: height)
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : (isHovered ? -8 : -3)),
            axis: (x: 1, y: 0.25, z: 0),
            perspective: 0.35
        )
        .shadow(color: color.opacity(0.16), radius: 7, y: 5)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isHovered)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: fraction)
    }

    private var fraction: Double {
        percent.map { UsageMath.clampPercent($0) / 100 } ?? 0
    }
}
