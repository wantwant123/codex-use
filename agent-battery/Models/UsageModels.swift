import Foundation

enum UsageDefaults {
    static let codexSessionsPath = "~/.codex/sessions"
}

enum UsageTool: String, CaseIterable, Codable, Hashable, Identifiable {
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            String(localized: "tool.codexName")
        }
    }

    var shortName: String {
        switch self {
        case .codex:
            String(localized: "tool.codexShortName")
        }
    }

    var systemImage: String {
        switch self {
        case .codex:
            "terminal"
        }
    }

    var assetImageName: String {
        switch self {
        case .codex:
            "codex"
        }
    }
}

enum UsageStatus: String, Codable, Hashable {
    case available
    case unavailable
    case stale
    case error

    var title: String {
        switch self {
        case .available:
            String(localized: "status.available")
        case .unavailable:
            String(localized: "status.unavailable")
        case .stale:
            String(localized: "status.stale")
        case .error:
            String(localized: "status.error")
        }
    }
}

enum UsageLevel {
    case normal
    case warning
    case critical
    case unavailable
}

struct UsageSnapshot: Codable, Identifiable, Equatable {
    var id: UsageTool { tool }

    let tool: UsageTool
    let fiveHourRemainingPercent: Double?
    let weeklyRemainingPercent: Double?
    let fiveHourResetAt: Date?
    let weeklyResetAt: Date?
    let dailyTokenUsage: Int?
    let weeklyTokenUsage: Int?
    let monthlyTokenUsage: Int?
    let updatedAt: Date?
    let status: UsageStatus
    let message: String?

    static func unavailable(
        tool: UsageTool,
        message: String,
        updatedAt: Date? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            tool: tool,
            fiveHourRemainingPercent: nil,
            weeklyRemainingPercent: nil,
            fiveHourResetAt: nil,
            weeklyResetAt: nil,
            dailyTokenUsage: nil,
            weeklyTokenUsage: nil,
            monthlyTokenUsage: nil,
            updatedAt: updatedAt,
            status: .unavailable,
            message: message
        )
    }

    static func error(tool: UsageTool, message: String) -> UsageSnapshot {
        UsageSnapshot(
            tool: tool,
            fiveHourRemainingPercent: nil,
            weeklyRemainingPercent: nil,
            fiveHourResetAt: nil,
            weeklyResetAt: nil,
            dailyTokenUsage: nil,
            weeklyTokenUsage: nil,
            monthlyTokenUsage: nil,
            updatedAt: Date(),
            status: .error,
            message: message
        )
    }
}

extension UsageSnapshot {
    private static let weeklyMenuBarDisplayThreshold = 10.0

    var menuBarRemainingPercent: Double? {
        if let weeklyRemainingPercent,
           weeklyRemainingPercent < Self.weeklyMenuBarDisplayThreshold {
            return weeklyRemainingPercent
        }

        return fiveHourRemainingPercent
    }
}

struct UsageHistoryEntry: Codable, Identifiable, Equatable {
    var id: String { "\(tool.rawValue)-\(recordedAt.timeIntervalSince1970)" }

    let tool: UsageTool
    let recordedAt: Date
    let fiveHourRemainingPercent: Double?
    let weeklyRemainingPercent: Double?
    let fiveHourResetAt: Date?
    let weeklyResetAt: Date?
    let dailyTokenUsage: Int?
    let weeklyTokenUsage: Int?
    let monthlyTokenUsage: Int?
    let status: UsageStatus

    init(
        tool: UsageTool,
        recordedAt: Date,
        fiveHourRemainingPercent: Double?,
        weeklyRemainingPercent: Double?,
        fiveHourResetAt: Date?,
        weeklyResetAt: Date?,
        dailyTokenUsage: Int?,
        weeklyTokenUsage: Int?,
        monthlyTokenUsage: Int?,
        status: UsageStatus
    ) {
        self.tool = tool
        self.recordedAt = recordedAt
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.fiveHourResetAt = fiveHourResetAt
        self.weeklyResetAt = weeklyResetAt
        self.dailyTokenUsage = dailyTokenUsage
        self.weeklyTokenUsage = weeklyTokenUsage
        self.monthlyTokenUsage = monthlyTokenUsage
        self.status = status
    }

    init(snapshot: UsageSnapshot, recordedAt: Date) {
        self.init(
            tool: snapshot.tool,
            recordedAt: recordedAt,
            fiveHourRemainingPercent: snapshot.fiveHourRemainingPercent,
            weeklyRemainingPercent: snapshot.weeklyRemainingPercent,
            fiveHourResetAt: snapshot.fiveHourResetAt,
            weeklyResetAt: snapshot.weeklyResetAt,
            dailyTokenUsage: snapshot.dailyTokenUsage,
            weeklyTokenUsage: snapshot.weeklyTokenUsage,
            monthlyTokenUsage: snapshot.monthlyTokenUsage,
            status: snapshot.status
        )
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case percent
    case battery
    case tool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .percent:
            String(localized: "displayMode.percent")
        case .battery:
            String(localized: "displayMode.battery")
        case .tool:
            String(localized: "displayMode.tool")
        }
    }

    var supportsPercentToggle: Bool { self != .percent }
}

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirtySeconds:
            String(localized: "refreshInterval.thirtySec")
        case .oneMinute:
            String(localized: "refreshInterval.oneMin")
        case .fiveMinutes:
            String(localized: "refreshInterval.fiveMin")
        }
    }
}

struct UsageDataConfiguration {
    let codexSessionsPath: String
    let staleInterval: TimeInterval
}
