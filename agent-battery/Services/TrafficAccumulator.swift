import Foundation

/// Daily totals retain observed increments; live connection baselines are never restored from disk.
nonisolated struct TrafficAccumulator {
    private var previous: ProxyConnections?
    private var previousTime: TimeInterval?
    private var previousDate: Date?
    private var entries: [TrafficKey: TrafficEntry] = [:]
    private var snapshot = TrafficSnapshot()
    private var segment = 0
    private let entryLimit: Int
    private let historyLimit: Int
    private let calendar: Calendar
    private let dates = ISO8601DateFormatter()
    private let wholeSecondDates = ISO8601DateFormatter()

    init(entryLimit: Int = 2_000, historyLimit: Int = 300, calendar: Calendar = .autoupdatingCurrent, restored: TrafficSnapshot? = nil) {
        self.calendar = calendar
        self.entryLimit = max(1, entryLimit)
        self.historyLimit = max(1, historyLimit)
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let restored {
            snapshot = restored
            snapshot.speed = nil
            snapshot.history = []
            snapshot.hasGaps = true
            for var entry in restored.entries {
                entry.speed = TrafficBytes()
                entries[entry.key] = entry
            }
        }
    }

    mutating func interrupt() {
        previous = nil
        previousTime = nil
        if snapshot.startedAt != nil { snapshot.hasGaps = true }
        segment += 1
    }

    mutating func current(at date: Date) -> TrafficSnapshot {
        let day = calendar.startOfDay(for: date)
        if snapshot.dayStart != day {
            snapshot = TrafficSnapshot(dayStart: day)
            entries.removeAll(keepingCapacity: false)
            previous = nil
            previousTime = nil
            previousDate = nil
            segment = 0
        }
        return snapshot
    }

    mutating func ingest(_ sample: ProxyConnections, at date: Date, time: TimeInterval) -> TrafficSnapshot {
        _ = current(at: date)
        for key in entries.keys { entries[key]?.speed = TrafficBytes() }
        snapshot.speed = nil
        if snapshot.startedAt == nil { snapshot.startedAt = date }
        defer {
            previous = sample
            previousTime = time
            previousDate = date
        }
        if let old = previous, let oldTime = previousTime, let oldDate = previousDate {
            let seconds = time - oldTime
            if seconds > 0 && seconds <= 5 && date.timeIntervalSince(oldDate) <= 5 && sample.uploadTotal >= old.uploadTotal && sample.downloadTotal >= old.downloadTotal {
                let delta = TrafficBytes(upload: Double(sample.uploadTotal - old.uploadTotal), download: Double(sample.downloadTotal - old.downloadTotal))
                snapshot.total = snapshot.total + delta
                snapshot.speed = delta.perSecond(seconds)
                // A transiently missing connection is baselined when it reappears, never counted twice.
                var oldConnections: [String: ProxyConnection] = [:]
                for connection in old.connections ?? [] { oldConnections[connection.id] = connection }
                var seen = Set<String>()
                for connection in sample.connections ?? [] where seen.insert(connection.id).inserted {
                    let amount: TrafficBytes
                    if let prior = oldConnections[connection.id], prior.start == connection.start {
                        amount = TrafficBytes(upload: Double(max(0, connection.upload - prior.upload)), download: Double(max(0, connection.download - prior.download)))
                    } else if let start = connection.start.flatMap({ dates.date(from: $0) ?? wholeSecondDates.date(from: $0) }), start >= oldDate {
                        amount = TrafficBytes(upload: Double(max(0, connection.upload)), download: Double(max(0, connection.download)))
                    } else {
                        continue
                    }
                    guard amount.total > 0 else { continue }
                    var key = TrafficKey(app: connection.app, domain: connection.domain, route: connection.route)
                    if key.app.utf8.count > 4_096 || key.domain.utf8.count > 512 || (entries[key] == nil && entries.count >= entryLimit) {
                        key = TrafficKey(app: TrafficKey.overflow, domain: TrafficKey.overflow, route: connection.route)
                        snapshot.isLimited = true
                    }
                    var entry = entries[key] ?? TrafficEntry(key: key)
                    entry.bytes = entry.bytes + amount
                    entry.speed = entry.speed + amount.perSecond(seconds)
                    entries[key] = entry
                }
                snapshot.history.append(TrafficPoint(date: date, speed: snapshot.speed!, segment: segment))
            } else {
                snapshot.hasGaps = true
                segment += 1
            }
        }
        snapshot.history = Array(snapshot.history.filter { date.timeIntervalSince($0.date) <= 300 }.suffix(historyLimit))
        snapshot.entries = Array(entries.values)
        snapshot.updatedAt = date
        return snapshot
    }
}
