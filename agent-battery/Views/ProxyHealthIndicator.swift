import AppKit
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

    var tooltip: String {
        var parts = [health.kind.title]
        if let latency = health.latencyMS { parts.append("\(latency) ms") }
        if let date = health.checkedAt { parts.append(date.formatted(date: .omitted, time: .standard)) }
        parts.append(contentsOf: health.outbounds.map { String($0.prefix(80)) })
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Self.glyph(color: color)
            .accessibilityLabel(health.kind.title)
            .help(tooltip)
    }

    // Three tiny images are shared for the process lifetime; speed updates do not render new lights.
    private static let greenImage = renderedImage(color: .green)
    private static let yellowImage = renderedImage(color: .orange)
    private static let redImage = renderedImage(color: .red)

    var menuBarImage: NSImage {
        switch health.kind {
        case .healthy: Self.greenImage
        case .failed, .unavailable: Self.redImage
        default: Self.yellowImage
        }
    }

    private static func renderedImage(color: Color) -> NSImage {
        let renderer = ImageRenderer(content: glyph(color: color).environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 14, height: 14))
        image.isTemplate = false
        return image
    }

    private static func glyph(color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.18)).frame(width: 14, height: 14)
            Circle().fill(color.gradient).frame(width: 8, height: 8)
            Circle().fill(.white.opacity(0.65)).frame(width: 2, height: 2).offset(x: -1.5, y: -1.5)
        }
    }
}
