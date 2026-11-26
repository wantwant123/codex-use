import SwiftUI

struct MenuBarModePreview: View {
    @ObservedObject var settings: AppSettings
    let mode: MenuBarDisplayMode
    let percent: Double
    let toolShortName: String

    var body: some View {
        HStack(spacing: 4) {
            switch mode {
            case .percent:
                Text(percentText)
                    .foregroundStyle(textColor)
            case .battery:
                BatteryIcon(
                    percent: percent,
                    height: 11.5,
                    autoColor: settings.colorByUsage,
                    fillColor: .white,
                    lowColor: settings.usageColorLow,
                    midColor: settings.usageColorMid,
                    highColor: settings.usageColorHigh,
                    lowEdge: Double(settings.criticalThreshold),
                    midEdge: Double(settings.warningThreshold)
                )
                if settings.showMenuBarPercent {
                    Text(percentText)
                        .foregroundStyle(textColor)
                }
            case .tool:
                Text(settings.showMenuBarPercent ? "\(toolShortName) \(percentText)" : toolShortName)
                    .foregroundStyle(textColor)
            }
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var percentText: String {
        "\(Int(percent))%"
    }

    private var textColor: Color {
        switch mode {
        case .battery:
            return .white
        case .percent, .tool:
            guard settings.colorByUsage else { return .white }
            if percent < Double(settings.criticalThreshold) {
                return settings.usageColorLow
            }
            if percent < Double(settings.warningThreshold) {
                return settings.usageColorMid
            }
            return settings.usageColorHigh
        }
    }
}

struct MenuBarModePreviewRow: View {
    @ObservedObject var settings: AppSettings
    let mode: MenuBarDisplayMode

    private static let samples: [Double] = [8, 30, 80]

    private var previewShortName: String {
        switch settings.menuBarQuotaSource {
        case .antigravity:
            UsageTool.antigravity.shortName
        case .codex, .both:
            UsageTool.codex.shortName
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.samples, id: \.self) { value in
                MenuBarModePreview(
                    settings: settings,
                    mode: mode,
                    percent: value,
                    toolShortName: previewShortName
                )
            }
        }
    }
}
