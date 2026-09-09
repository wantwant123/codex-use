import SwiftUI

struct ProxyHealthIndicator: View {
    let health: ProxyHealth

    private var color: Color {
        switch health.kind {
        case .healthy: .green
        case .failed, .unavailable: .red
        default: .orange
        }
    }

    private var tooltip: String {
        var parts = [health.kind.title]
        if let latency = health.latencyMS { parts.append("\(latency) ms") }
        if let date = health.checkedAt { parts.append(date.formatted(date: .omitted, time: .standard)) }
        parts.append(contentsOf: health.outbounds.map { String($0.prefix(80)) })
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.18)).frame(width: 14, height: 14)
            Circle().fill(color.gradient).frame(width: 8, height: 8)
            Circle().fill(.white.opacity(0.65)).frame(width: 2, height: 2).offset(x: -1.5, y: -1.5)
        }
        .accessibilityLabel(health.kind.title)
        .help(tooltip)
    }
}
