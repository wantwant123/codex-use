import SwiftUI

struct ProxyTrafficSummaryView: View {
    @ObservedObject var store: ProxyTrafficStore
    let openDetails: () -> Void

    @State private var isHovered = false

    private var countryName: String? {
        guard let code = store.countryCode else { return nil }
        return Locale.current.localizedString(forRegionCode: code)
    }

    var body: some View {
        Button(action: openDetails) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "network")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 22, height: 22)
                        .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text("traffic.clashTitle")
                        .font(.subheadline.weight(.semibold))

                    if let countryName {
                        Text(verbatim: countryName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.primary.opacity(0.06), in: Capsule())
                    }

                    Spacer(minLength: 4)

                    ProxyHealthIndicator(health: store.currentHealth)

                    if let latency = store.currentHealth.latencyMS {
                        Text(verbatim: "\(latency) ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    speedChip(symbol: "arrow.down", text: TrafficFormat.speed(store.speed?.download), color: .blue)
                    speedChip(symbol: "arrow.up", text: TrafficFormat.speed(store.speed?.upload), color: .orange)
                    Spacer(minLength: 2)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("traffic.sessionTotal")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        Text(verbatim: store.snapshot.startedAt == nil ? "—" : TrafficFormat.bytes(store.snapshot.total.total))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }

                if !store.isLive {
                    Text(LocalizedStringKey(store.statusKey))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .panelCard(padding: 11)
        .overlay(
            RoundedRectangle(cornerRadius: SurfaceStyle.cardCornerRadius, style: .continuous)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .help("traffic.details")
    }

    private func speedChip(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(color)
            Text(verbatim: text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
