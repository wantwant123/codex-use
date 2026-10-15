import Foundation
import Testing
@testable import agent_battery

struct MenuBarClockTests {
    @Test func timeZonesCanShowDifferentCalendarDays() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-15T01:30:00Z"))
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(MenuBarClock.dateTime(at: date, in: shanghai) == "10/15 09:30")
        #expect(MenuBarClock.dateTime(at: date, in: losAngeles) == "10/14 18:30")
        #expect(MenuBarClock.text(at: date, in: shanghai, locale: Locale(identifier: "zh_CN")) == "10/15 09:30 上海")
    }

    @Test func daylightSavingSkipsAndRepeatsHours() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        for (instant, expected) in [
            ("2026-03-08T06:59:00Z", "03/08 01:59"),
            ("2026-03-08T07:00:00Z", "03/08 03:00"),
            ("2026-11-01T05:30:00Z", "11/01 01:30"),
            ("2026-11-01T06:30:00Z", "11/01 01:30")
        ] {
            let date = try #require(ISO8601DateFormatter().date(from: instant))
            #expect(MenuBarClock.dateTime(at: date, in: zone) == expected)
        }
    }

    @Test func fractionalOffsetsAndYearRollover() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-12-31T20:30:00Z"))
        let zone = try #require(TimeZone(identifier: "Asia/Kathmandu"))
        #expect(MenuBarClock.dateTime(at: date, in: zone) == "01/01 02:15")
        #expect(MenuBarClock.city(in: try #require(TimeZone(identifier: "UTC"))) == "UTC")
    }

    @Test func searchAcceptsCitiesAndIdentifiers() {
        let zone = ClockTimeZone(id: "America/New_York", city: "纽约", name: "北美东部时间")
        #expect(zone.matches("纽约"))
        #expect(zone.matches("new york"))
        #expect(zone.matches("America/New_York"))
        #expect(zone.matches("America/"))
        #expect(zone.matches("  "))
        #expect(!zone.matches("上海"))
        #expect(ClockTimeZone.all.contains { $0.id == "UTC" })
    }

    @Test @MainActor func selectionPersistsAndInvalidZoneFallsBack() throws {
        let suite = "clock-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "showTrafficInMenuBar")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.clockTimeZoneIdentifier == TimeZone.current.identifier)
        #expect(!settings.showProxyHealthInMenuBar)
        settings.clockTimeZoneIdentifier = "America/New_York"
        #expect(AppSettings(defaults: defaults).clockTimeZone.identifier == "America/New_York")
        defaults.set("Invalid/Zone", forKey: "clockTimeZoneIdentifier")
        #expect(AppSettings(defaults: defaults).clockTimeZone.identifier == TimeZone.current.identifier)
    }
}
