import Foundation

enum UsageFormatters {
    private static let resetDetailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        if Locale.current.identifier.hasPrefix("zh") {
            formatter.locale = Locale(identifier: "zh_Hans")
            formatter.dateFormat = "EEE HH:mm, M 月 d号"
        } else {
            formatter.dateFormat = "EEE HH:mm, MMM d"
        }
        return formatter
    }()

    private static let tokenCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func percentText(_ value: Double?) -> String {
        guard let value else {
            return String(localized: "formatter.percentUnknown")
        }
        return "\(Int(UsageMath.clampPercent(value).rounded()))%"
    }

    static func tokenCountText(_ value: Int?) -> String {
        guard let value else {
            return String(localized: "formatter.tokenCountUnknown")
        }

        return tokenCountFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func compactTokenCountText(_ value: Int?) -> String {
        guard let value else {
            return String(localized: "formatter.tokenCountUnknown")
        }

        let number = Double(value)
        if value >= 1_000_000_000 {
            return compactText(number / 1_000_000_000, suffix: "B")
        }

        if value >= 1_000_000 {
            return compactText(number / 1_000_000, suffix: "M")
        }

        if value >= 1_000 {
            return compactText(number / 1_000, suffix: "K")
        }

        return "\(value)"
    }

    static func updatedText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return String(localized: "formatter.updatedUnavailable")
        }

        let elapsedSeconds = max(0, Int(now.timeIntervalSince(date)))
        if elapsedSeconds < 60 {
            return String(localized: "formatter.updatedJustNow")
        }

        let elapsedMinutes = elapsedSeconds / 60
        if elapsedMinutes < 60 {
            return String(format: NSLocalizedString("formatter.updatedMinutesAgo", comment: ""), elapsedMinutes)
        }

        return String(format: NSLocalizedString("formatter.updatedHoursAgo", comment: ""), elapsedMinutes / 60)
    }

    static var resetRelativePrefixText: String {
        localizedSegment(
            "formatter.resetRelativePrefix",
            fallback: isChineseLocale ? "" : "Reset in "
        )
    }

    static var resetRelativeSuffixText: String {
        localizedSegment(
            "formatter.resetRelativeSuffix",
            fallback: isChineseLocale ? "后重置" : ""
        )
    }

    static func resetDetailText(_ date: Date) -> String {
        resetDetailFormatter.string(from: date)
    }

    static func resetCountdownText(
        until date: Date,
        now: Date = Date(),
        locale: Locale = .current
    ) -> String {
        let remainingSeconds = max(60, Int64(date.timeIntervalSince(now)))
        let days = remainingSeconds / (24 * 60 * 60)
        let hours = (remainingSeconds % (24 * 60 * 60)) / (60 * 60)
        let minutes = (remainingSeconds % (60 * 60)) / 60
        let units = [
            durationUnit(value: days, english: "d", chinese: "天", locale: locale),
            durationUnit(value: hours, english: "h", chinese: "小时", locale: locale),
            durationUnit(value: minutes, english: "m", chinese: "分钟", locale: locale),
        ]
            .compactMap { $0 }
            .prefix(2)

        return units.joined(separator: " ")
    }

    private static var isChineseLocale: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

    private static func durationUnit(
        value: Int64,
        english: String,
        chinese: String,
        locale: Locale
    ) -> String? {
        guard value > 0 else {
            return nil
        }

        if locale.identifier.hasPrefix("zh") {
            return "\(value) \(chinese)"
        }

        return "\(value)\(english)"
    }

    private static func localizedSegment(_ key: String, fallback: String) -> String {
        let value = NSLocalizedString(key, comment: "")
        return value == key ? fallback : value
    }

    private static func compactText(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == floor(rounded) {
            return "\(Int(rounded))\(suffix)"
        }

        return String(format: "%.1f%@", rounded, suffix)
    }
}
