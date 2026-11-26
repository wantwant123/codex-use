import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var traffic: ProxyTrafficStore
    @ObservedObject var tokenSpeed: TokenSpeedStore
    @StateObject private var clock = MenuBarClockStore()

    var body: some View {
        // MenuBarExtra extracts images/text instead of hosting arbitrary SwiftUI shapes.
        // One non-template image preserves the order: quota(s), output speed, clock, country, health light.
        // TimelineView cannot own the status-item label: its timeline can trigger
        // a continuous native layout loop before the menu bar item appears.
        Image(nsImage: renderedImage(at: clock.now))
            .accessibilityLabel(labelText(at: clock.now))
            .help(tooltip(at: clock.now))
    }

    func renderedImage(at date: Date = Date()) -> NSImage {
        var groups: [NSImage] = [quotaGroupImage()]

        if settings.showTokenSpeedInMenuBar {
            groups.append(MenuBarText.image(text: tokenSpeed.menuBarText, color: .white.opacity(0.92)))
        }
        if settings.showClockInMenuBar {
            groups.append(MenuBarText.image(text: MenuBarClock.text(at: date, in: settings.clockTimeZone), color: .white))
        }
        if let country {
            groups.append(MenuBarText.image(text: country, color: .white.opacity(0.95)))
        }

        let showHealth = settings.trafficEnabled && settings.showProxyHealthInMenuBar
        let dotSeparator = MenuBarText.separatorDotImage()

        var parts: [NSImage] = []
        for (index, group) in groups.enumerated() {
            if index > 0 {
                parts.append(dotSeparator)
            }
            parts.append(group)
        }
        if showHealth {
            parts.append(ProxyHealthIndicator(health: traffic.currentHealth).menuBarImage)
        }

        let spacing: CGFloat = 4.5
        let totalWidth = parts.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, parts.count - 1))
        let totalHeight = max(parts.map(\.size.height).max() ?? 14, 14)
        let size = NSSize(width: ceil(totalWidth), height: ceil(totalHeight))

        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                part.draw(
                    at: NSPoint(x: x, y: (size.height - part.size.height) / 2),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                x += part.size.width + spacing
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private var activeTools: [UsageTool] {
        settings.menuBarQuotaSource.tools
    }

    private var country: String? {
        guard settings.trafficEnabled, let code = traffic.countryCode else { return nil }
        return Locale.current.localizedString(forRegionCode: code)
    }

    private func labelText(at date: Date) -> String {
        var parts = activeTools.map { tool in
            let snapshot = store.snapshot(for: tool)
            return "\(tool.shortName) \(UsageFormatters.percentText(snapshot.menuBarRemainingPercent))"
        }
        if settings.showTokenSpeedInMenuBar { parts.append(tokenSpeed.menuBarText) }
        if settings.showClockInMenuBar { parts.append(MenuBarClock.text(at: date, in: settings.clockTimeZone)) }
        if let country { parts.append(country) }
        if settings.trafficEnabled && settings.showProxyHealthInMenuBar { parts.append(traffic.currentHealth.kind.title) }
        return parts.joined(separator: " · ")
    }

    private func tooltip(at date: Date) -> String {
        var parts = [labelText(at: date)]
        if settings.showTokenSpeedInMenuBar { parts.append(String(localized: "tokenSpeed.note")) }
        if settings.trafficEnabled && settings.showProxyHealthInMenuBar {
            parts.append(ProxyHealthIndicator(health: traffic.currentHealth).tooltip)
        }
        return parts.joined(separator: "\n")
    }

    @MainActor
    private func quotaGroupImage() -> NSImage {
        let tools = activeTools
        if tools.count == 1, let tool = tools.first {
            return quotaImage(for: store.snapshot(for: tool), forceToolPrefix: false)
        }

        let itemImages = tools.map { tool in
            quotaImage(for: store.snapshot(for: tool), forceToolPrefix: true)
        }
        let spacing: CGFloat = 6
        let totalWidth = itemImages.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, itemImages.count - 1))
        let totalHeight = itemImages.map(\.size.height).max() ?? 14
        let size = NSSize(width: ceil(totalWidth), height: ceil(totalHeight))

        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for item in itemImages {
                item.draw(
                    at: NSPoint(x: x, y: (size.height - item.size.height) / 2),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                x += item.size.width + spacing
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    @MainActor
    private func quotaImage(for snapshot: UsageSnapshot, forceToolPrefix: Bool) -> NSImage {
        let percent = (snapshot.status == .stale && snapshot.menuBarRemainingPercent != nil ? "≈" : "")
            + UsageFormatters.percentText(snapshot.menuBarRemainingPercent)
        let color = labelColor(for: snapshot)

        if forceToolPrefix {
            switch settings.menuBarDisplayMode {
            case .battery:
                let tagImage = MenuBarText.image(text: snapshot.tool.shortName, color: .white.opacity(0.75))
                let batteryPart = settings.showMenuBarPercent
                    ? batteryWithPercentImage(snapshot: snapshot, percent: percent, color: color)
                    : renderedBatteryImage(snapshot: snapshot, height: 11)
                return MenuBarText.combine([tagImage, batteryPart], spacing: 3.5)
            case .percent, .tool:
                let text = settings.showMenuBarPercent || settings.menuBarDisplayMode == .percent
                    ? "\(snapshot.tool.shortName) \(percent)"
                    : snapshot.tool.shortName
                return MenuBarText.image(text: text, color: color)
            }
        }

        switch settings.menuBarDisplayMode {
        case .percent:
            return MenuBarText.image(text: percent, color: color)
        case .battery:
            return settings.showMenuBarPercent
                ? batteryWithPercentImage(snapshot: snapshot, percent: percent, color: color)
                : renderedBatteryImage(snapshot: snapshot, height: 12)
        case .tool:
            return MenuBarText.image(
                text: settings.showMenuBarPercent ? "\(snapshot.tool.shortName) \(percent)" : snapshot.tool.shortName,
                color: color
            )
        }
    }

    private func batteryIcon(snapshot: UsageSnapshot, height: CGFloat = 12) -> some View {
        BatteryIcon(
            percent: snapshot.menuBarRemainingPercent,
            height: height,
            autoColor: settings.colorByUsage,
            fillColor: .white,
            lowColor: settings.usageColorLow,
            midColor: settings.usageColorMid,
            highColor: settings.usageColorHigh,
            lowEdge: Double(settings.criticalThreshold),
            midEdge: Double(settings.warningThreshold)
        )
    }

    @MainActor
    private func batteryWithPercentImage(snapshot: UsageSnapshot, percent: String, color: Color) -> NSImage {
        let batteryImage = renderedBatteryImage(snapshot: snapshot, height: 11.5)
        let textImage = MenuBarText.image(text: percent, color: color)
        return MenuBarText.combine([batteryImage, textImage], spacing: 4)
    }
}

private enum MenuBarText {
    static func image(text: String, color: Color) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .medium),
            .foregroundColor: NSColor(color)
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let size = attrString.size()
        let drawSize = NSSize(width: ceil(size.width), height: ceil(size.height))
        let image = NSImage(size: drawSize, flipped: false) { rect in
            attrString.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func separatorDotImage() -> NSImage {
        let size = NSSize(width: 3, height: 14)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.white.withAlphaComponent(0.32).setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: 0.25, y: 5.75, width: 2.5, height: 2.5))
            dot.fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    static func combine(_ parts: [NSImage], spacing: CGFloat) -> NSImage {
        let width = parts.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, parts.count - 1))
        let height = parts.map(\.size.height).max() ?? 14
        let size = NSSize(width: ceil(width), height: ceil(height))
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                part.draw(
                    at: NSPoint(x: x, y: (size.height - part.size.height) / 2),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                x += part.size.width + spacing
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

private extension MenuBarLabelView {
    func labelColor(for snapshot: UsageSnapshot) -> Color {
        guard let percent = snapshot.menuBarRemainingPercent else {
            return .secondary
        }

        let usesUsageColor: Bool
        switch settings.menuBarDisplayMode {
        case .percent, .tool:
            usesUsageColor = settings.colorByUsage
        case .battery:
            usesUsageColor = false
        }

        guard usesUsageColor else { return .white }

        if percent < Double(settings.criticalThreshold) {
            return settings.usageColorLow
        }
        if percent < Double(settings.warningThreshold) {
            return settings.usageColorMid
        }
        return settings.usageColorHigh
    }

    @MainActor
    func renderedBatteryImage(snapshot: UsageSnapshot, height: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: batteryIcon(snapshot: snapshot, height: height))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: height * 2.4, height: height))
        image.isTemplate = false
        return image
    }
}
