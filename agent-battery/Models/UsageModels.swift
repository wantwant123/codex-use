import Foundation

enum UsageDefaults {
    static let codexSessionsPath = "~/.codex/sessions"
    static let antigravityBrainPath = "~/.gemini/antigravity/brain"
    static let antigravityDailyTokenBudget = 10_000_000
    static let antigravityWeeklyTokenBudget = 50_000_000
}

enum UsageTool: String, CaseIterable, Codable, Hashable, Identifiable {
    case codex
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            String(localized: "tool.codexName")
        case .antigravity:
            String(localized: "tool.antigravityName")
        }
    }

    var shortName: String {
        switch self {
        case .codex:
            String(localized: "tool.codexShortName")
        case .antigravity:
            String(localized: "tool.antigravityShortName")
        }
    }

    var systemImage: String {
        switch self {
        case .codex:
            "terminal"
        case .antigravity:
            "sparkles"
        }
    }

    var assetImageName: String {
        switch self {
        case .codex:
            "codex"
        case .antigravity:
            "antigravity"
        }
    }
}

enum MenuBarQuotaSource: String, CaseIterable, Identifiable {
    case codex
    case antigravity
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex:
            String(localized: "tool.codexName")
        case .antigravity:
            String(localized: "tool.antigravityName")
        case .both:
            String(localized: "settings.menuBarSourceBoth")
        }
    }

    var tools: [UsageTool] {
        switch self {
        case .codex: [.codex]
        case .antigravity: [.antigravity]
        case .both: [.codex, .antigravity]
        }
    }
}

struct TokenBreakdown: Codable, Equatable, Sendable {
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int

    var totalTokens: Int {
        inputTokens + cacheReadTokens + outputTokens
    }

    var cacheHitRatio: Double? {
        let promptTotal = inputTokens + cacheReadTokens
        guard promptTotal > 0 else { return nil }
        return Double(cacheReadTokens) / Double(promptTotal)
    }
}

struct ModelTokenUsage: Codable, Equatable, Identifiable, Sendable {
    var id: String { model }

    let model: String
    let tokens: Int
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
    let tokenBreakdown: TokenBreakdown?
    let topModels: [ModelTokenUsage]
    let isBudgetEstimated: Bool

    init(
        tool: UsageTool,
        fiveHourRemainingPercent: Double?,
        weeklyRemainingPercent: Double?,
        fiveHourResetAt: Date?,
        weeklyResetAt: Date?,
        dailyTokenUsage: Int?,
        weeklyTokenUsage: Int?,
        monthlyTokenUsage: Int?,
        updatedAt: Date?,
        status: UsageStatus,
        message: String?,
        tokenBreakdown: TokenBreakdown? = nil,
        topModels: [ModelTokenUsage] = [],
        isBudgetEstimated: Bool = false
    ) {
        self.tool = tool
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.fiveHourResetAt = fiveHourResetAt
        self.weeklyResetAt = weeklyResetAt
        self.dailyTokenUsage = dailyTokenUsage
        self.weeklyTokenUsage = weeklyTokenUsage
        self.monthlyTokenUsage = monthlyTokenUsage
        self.updatedAt = updatedAt
        self.status = status
        self.message = message
        self.tokenBreakdown = tokenBreakdown
        self.topModels = topModels
        self.isBudgetEstimated = isBudgetEstimated
    }

    private enum CodingKeys: String, CodingKey {
        case tool
        case fiveHourRemainingPercent
        case weeklyRemainingPercent
        case fiveHourResetAt
        case weeklyResetAt
        case dailyTokenUsage
        case weeklyTokenUsage
        case monthlyTokenUsage
        case updatedAt
        case status
        case message
        case tokenBreakdown
        case topModels
        case isBudgetEstimated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(UsageTool.self, forKey: .tool)
        fiveHourRemainingPercent = try container.decodeIfPresent(Double.self, forKey: .fiveHourRemainingPercent)
        weeklyRemainingPercent = try container.decodeIfPresent(Double.self, forKey: .weeklyRemainingPercent)
        fiveHourResetAt = try container.decodeIfPresent(Date.self, forKey: .fiveHourResetAt)
        weeklyResetAt = try container.decodeIfPresent(Date.self, forKey: .weeklyResetAt)
        dailyTokenUsage = try container.decodeIfPresent(Int.self, forKey: .dailyTokenUsage)
        weeklyTokenUsage = try container.decodeIfPresent(Int.self, forKey: .weeklyTokenUsage)
        monthlyTokenUsage = try container.decodeIfPresent(Int.self, forKey: .monthlyTokenUsage)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        status = try container.decode(UsageStatus.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        tokenBreakdown = try container.decodeIfPresent(TokenBreakdown.self, forKey: .tokenBreakdown)
        topModels = try container.decodeIfPresent([ModelTokenUsage].self, forKey: .topModels) ?? []
        isBudgetEstimated = try container.decodeIfPresent(Bool.self, forKey: .isBudgetEstimated) ?? false
    }

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
    var hasFiveHourQuota: Bool {
        fiveHourRemainingPercent != nil || fiveHourResetAt != nil
    }

    var hasWeeklyQuota: Bool {
        weeklyRemainingPercent != nil || weeklyResetAt != nil
    }

    private static let weeklyMenuBarDisplayThreshold = 10.0

    var menuBarRemainingPercent: Double? {
        if let weeklyRemainingPercent,
           weeklyRemainingPercent < Self.weeklyMenuBarDisplayThreshold {
            return weeklyRemainingPercent
        }

        return fiveHourRemainingPercent ?? weeklyRemainingPercent
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
    let antigravityBrainPath: String
    let antigravityDailyTokenBudget: Int
    let antigravityWeeklyTokenBudget: Int

    init(
        codexSessionsPath: String,
        staleInterval: TimeInterval,
        antigravityBrainPath: String = UsageDefaults.antigravityBrainPath,
        antigravityDailyTokenBudget: Int = UsageDefaults.antigravityDailyTokenBudget,
        antigravityWeeklyTokenBudget: Int = UsageDefaults.antigravityWeeklyTokenBudget
    ) {
        self.codexSessionsPath = codexSessionsPath
        self.staleInterval = staleInterval
        self.antigravityBrainPath = antigravityBrainPath
        self.antigravityDailyTokenBudget = antigravityDailyTokenBudget
        self.antigravityWeeklyTokenBudget = antigravityWeeklyTokenBudget
    }
}
