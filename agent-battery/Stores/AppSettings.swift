import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

final class AppSettings: ObservableObject {
    private enum Keys {
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let showMenuBarPercent = "showMenuBarPercent"
        static let colorByUsage = "colorByUsage"
        static let refreshInterval = "refreshInterval"
        static let warningThreshold = "warningThreshold"
        static let criticalThreshold = "criticalThreshold"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let codexSessionsPath = "codexSessionsPath"
        static let usageColorLow = "usageColorLow"
        static let usageColorMid = "usageColorMid"
        static let usageColorHigh = "usageColorHigh"
    }

    enum UsageLevelColor: CaseIterable {
        case low, mid, high

        var defaultHex: String {
            switch self {
            case .low: "FF3B30"
            case .mid: "FF9500"
            case .high: "FFFFFF"
            }
        }
    }

    private let defaults: UserDefaults

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode) }
    }

    @Published var showMenuBarPercent: Bool {
        didSet { defaults.set(showMenuBarPercent, forKey: Keys.showMenuBarPercent) }
    }

    @Published var colorByUsage: Bool {
        didSet { defaults.set(colorByUsage, forKey: Keys.colorByUsage) }
    }

    @Published var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }

    @Published var warningThreshold: Int {
        didSet { defaults.set(warningThreshold, forKey: Keys.warningThreshold) }
    }

    @Published var criticalThreshold: Int {
        didSet { defaults.set(criticalThreshold, forKey: Keys.criticalThreshold) }
    }

    @Published private(set) var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    @Published var launchAtLoginMessage: String?

    @Published var codexSessionsPath: String {
        didSet { defaults.set(codexSessionsPath, forKey: Keys.codexSessionsPath) }
    }

    @Published var usageColorLowHex: String {
        didSet { defaults.set(usageColorLowHex, forKey: Keys.usageColorLow) }
    }

    @Published var usageColorMidHex: String {
        didSet { defaults.set(usageColorMidHex, forKey: Keys.usageColorMid) }
    }

    @Published var usageColorHighHex: String {
        didSet { defaults.set(usageColorHighHex, forKey: Keys.usageColorHigh) }
    }

    var usageColorLow: Color { Color(hex: usageColorLowHex) ?? .red }
    var usageColorMid: Color { Color(hex: usageColorMidHex) ?? .orange }
    var usageColorHigh: Color { Color(hex: usageColorHighHex) ?? .white }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarDisplayMode = MenuBarDisplayMode(
            rawValue: defaults.string(forKey: Keys.menuBarDisplayMode) ?? ""
        ) ?? .battery
        showMenuBarPercent = Self.bool(defaults, Keys.showMenuBarPercent, defaultValue: true)
        colorByUsage = Self.bool(defaults, Keys.colorByUsage, defaultValue: true)
        refreshInterval = RefreshInterval(
            rawValue: defaults.integer(forKey: Keys.refreshInterval)
        ) ?? .oneMinute
        warningThreshold = Self.int(defaults, Keys.warningThreshold, defaultValue: 40, range: 16...95)
        criticalThreshold = Self.int(defaults, Keys.criticalThreshold, defaultValue: 15, range: 1...39)
        launchAtLoginEnabled = Self.bool(
            defaults,
            Keys.launchAtLoginEnabled,
            defaultValue: SMAppService.mainApp.status == .enabled
        )
        launchAtLoginMessage = nil
        codexSessionsPath = defaults.string(forKey: Keys.codexSessionsPath) ?? UsageDefaults.codexSessionsPath
        usageColorLowHex = defaults.string(forKey: Keys.usageColorLow) ?? UsageLevelColor.low.defaultHex
        usageColorMidHex = defaults.string(forKey: Keys.usageColorMid) ?? UsageLevelColor.mid.defaultHex
        usageColorHighHex = defaults.string(forKey: Keys.usageColorHigh) ?? UsageLevelColor.high.defaultHex
    }

    var dataConfiguration: UsageDataConfiguration {
        UsageDataConfiguration(
            codexSessionsPath: codexSessionsPath,
            staleInterval: 10 * 60
        )
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }

            launchAtLoginMessage = nil
            launchAtLoginEnabled = enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginMessage = error.localizedDescription
        }
    }

    private static func bool(
        _ defaults: UserDefaults,
        _ key: String,
        defaultValue: Bool
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func int(
        _ defaults: UserDefaults,
        _ key: String,
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return min(max(defaults.integer(forKey: key), range.lowerBound), range.upperBound)
    }

}

extension Color {
    init?(hex: String) {
        var trimmed = hex
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
