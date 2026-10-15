import Foundation

nonisolated enum MenuBarClock {
    static func dateTime(at date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    static func city(in timeZone: TimeZone, locale: Locale = .current) -> String {
        if ["GMT", "UTC", "Etc/UTC", "Etc/GMT"].contains(timeZone.identifier) { return "UTC" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "VVV"
        return formatter.string(from: Date())
    }

    static func text(at date: Date, in timeZone: TimeZone, locale: Locale = .current) -> String {
        "\(dateTime(at: date, in: timeZone)) \(city(in: timeZone, locale: locale))"
    }
}

nonisolated struct ClockTimeZone: Identifiable {
    let id: String
    let city: String
    let name: String

    static let all: [ClockTimeZone] = (TimeZone.knownTimeZoneIdentifiers + ["UTC"]).compactMap { id in
        guard let zone = TimeZone(identifier: id) else { return nil }
        return ClockTimeZone(id: id, city: MenuBarClock.city(in: zone),
                             name: zone.localizedName(for: .generic, locale: .current) ?? id)
    }.sorted { $0.city.localizedStandardCompare($1.city) == .orderedAscending }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || "\(city) \(name) \(id) \(id.replacingOccurrences(of: "_", with: " "))"
            .localizedStandardContains(query)
    }
}
