import SwiftUI

struct QuotaBatteryView: View {
    let percent: Double?
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Offset shell gives the battery a visible lower edge.
                    RoundedRectangle(cornerRadius: 15)
                        .fill(.black.opacity(0.22))
                        .offset(y: 5)

                    RoundedRectangle(cornerRadius: 15)
                        .fill(LinearGradient(
                            colors: [.primary.opacity(0.18), .primary.opacity(0.04), .primary.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))

                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.6), color, color.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: max(0, geometry.size.width - 12) * fraction)
                        .padding(6)

                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(LinearGradient(
                            colors: [.white.opacity(0.65), .white.opacity(0.05), .primary.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ), lineWidth: 1)

                    Capsule()
                        .fill(.white.opacity(0.3))
                        .frame(height: 3)
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 9)
                }
            }

            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    colors: [.primary.opacity(0.15), .primary.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 8, height: 23)
        }
        .frame(height: 54)
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : (isHovered ? -9 : -4)),
            axis: (x: 1, y: 0.25, z: 0),
            perspective: 0.35
        )
        .shadow(color: color.opacity(0.16), radius: 9, y: 7)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isHovered)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: fraction)
    }

    private var fraction: Double {
        percent.map { UsageMath.clampPercent($0) / 100 } ?? 0
    }
}
