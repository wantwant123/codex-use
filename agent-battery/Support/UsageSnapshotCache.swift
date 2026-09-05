import Foundation

struct UsageSnapshotCache {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot(for tool: UsageTool, now: Date = Date()) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: key(for: tool)),
              let snapshot = try? decoder.decode(UsageSnapshot.self, from: data) else {
            return nil
        }

        return snapshot.markingElapsedResetsStale(now: now)
    }

    func store(_ snapshot: UsageSnapshot, now: Date = Date()) {
        let projected = snapshot.markingElapsedResetsStale(now: now)
        guard projected.hasUsageValues,
              let data = try? encoder.encode(projected) else {
            return
        }

        defaults.set(data, forKey: key(for: projected.tool))
    }

    private func key(for tool: UsageTool) -> String {
        "usageSnapshotCache.\(tool.rawValue)"
    }
}

extension UsageSnapshot {
    var hasUsageValues: Bool {
        fiveHourRemainingPercent != nil || weeklyRemainingPercent != nil
    }

    func markingElapsedResetsStale(now: Date = Date()) -> UsageSnapshot {
        let fiveHourExpired = fiveHourResetAt.map { $0 <= now } ?? false
        let weeklyExpired = weeklyResetAt.map { $0 <= now } ?? false

        guard fiveHourExpired || weeklyExpired else {
            return self
        }

        return replacingStatus(.stale, message: String(localized: "usage.awaitingReset"))
    }

    func replacingStatus(_ status: UsageStatus, message: String?) -> UsageSnapshot {
        UsageSnapshot(
            tool: tool,
            fiveHourRemainingPercent: fiveHourRemainingPercent,
            weeklyRemainingPercent: weeklyRemainingPercent,
            fiveHourResetAt: fiveHourResetAt,
            weeklyResetAt: weeklyResetAt,
            dailyTokenUsage: dailyTokenUsage,
            weeklyTokenUsage: weeklyTokenUsage,
            monthlyTokenUsage: monthlyTokenUsage,
            updatedAt: updatedAt,
            status: status,
            message: message
        )
    }
}
