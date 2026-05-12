import Foundation
import Testing
@testable import agent_battery

struct AgentBatteryTests {
    @Test func remainingPercentConvertsUsedPercent() {
        #expect(UsageMath.remainingPercent(fromUsedPercent: 0) == 100)
        #expect(UsageMath.remainingPercent(fromUsedPercent: 38.4) == 61.6)
        #expect(UsageMath.remainingPercent(fromUsedPercent: 120) == 0)
        #expect(UsageMath.remainingPercent(fromUsedPercent: -12) == 100)
    }

    @Test func percentTextRoundsAndHandlesMissingValues() {
        #expect(UsageFormatters.percentText(61.6) == "62%")
        #expect(UsageFormatters.percentText(nil) == "--%")
        #expect(UsageFormatters.percentText(140) == "100%")
        #expect(UsageFormatters.percentText(-10) == "0%")
        #expect(UsageFormatters.tokenCountText(nil) == "--")
    }

    @Test func resetCountdownTextUsesLargestTwoDurationUnits() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            UsageFormatters.resetCountdownText(
                until: now.addingTimeInterval((3 * 24 * 60 * 60) + (12 * 60 * 60) + (55 * 60)),
                now: now,
                locale: Locale(identifier: "zh_Hans")
            ) == "3 天 12 小时"
        )
        #expect(
            UsageFormatters.resetCountdownText(
                until: now.addingTimeInterval((2 * 60 * 60) + (5 * 60)),
                now: now,
                locale: Locale(identifier: "en_US")
            ) == "2h 5m"
        )
        #expect(
            UsageFormatters.resetCountdownText(
                until: now.addingTimeInterval(30),
                now: now,
                locale: Locale(identifier: "zh_Hans")
            ) == "1 分钟"
        )
    }

    @Test func warningLevelsFollowConfiguredThresholds() {
        #expect(UsageMath.level(for: 62, warningThreshold: 40, criticalThreshold: 15) == .normal)
        #expect(UsageMath.level(for: 18, warningThreshold: 40, criticalThreshold: 15) == .warning)
        #expect(UsageMath.level(for: 12, warningThreshold: 40, criticalThreshold: 15) == .critical)
        #expect(UsageMath.level(for: nil, warningThreshold: 40, criticalThreshold: 15) == .unavailable)
    }

    @Test func menuBarRemainingPercentSwitchesToWeeklyBelowTenPercent() {
        #expect(usageSnapshot(fiveHour: 72, weekly: 9).menuBarRemainingPercent == 9)
        #expect(usageSnapshot(fiveHour: 72, weekly: 10).menuBarRemainingPercent == 72)
        #expect(usageSnapshot(fiveHour: 72, weekly: nil).menuBarRemainingPercent == 72)
    }

    @Test func appSettingsUsesDefaultCodexSessionsPath() throws {
        let suiteName = "agent-battery-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(defaults: defaults)

        #expect(settings.dataConfiguration.codexSessionsPath == UsageDefaults.codexSessionsPath)
    }

    @Test func menuBarDisplayModeControlsPercentToggle() {
        #expect(!MenuBarDisplayMode.percent.supportsPercentToggle)
        #expect(MenuBarDisplayMode.battery.supportsPercentToggle)
        #expect(MenuBarDisplayMode.tool.supportsPercentToggle)
    }

    @Test func cachedSnapshotsProjectElapsedResetWindows() throws {
        let suiteName = "agent-battery-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let cache = UsageSnapshotCache(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = UsageSnapshot(
            tool: .codex,
            fiveHourRemainingPercent: 45,
            weeklyRemainingPercent: 60,
            fiveHourResetAt: now.addingTimeInterval(60 * 60),
            weeklyResetAt: now.addingTimeInterval(24 * 60 * 60),
            dailyTokenUsage: 12_345,
            weeklyTokenUsage: 45_678,
            monthlyTokenUsage: 90_123,
            updatedAt: now,
            status: .available,
            message: nil
        )

        cache.store(snapshot, now: now)

        let beforeReset = try #require(cache.snapshot(for: .codex, now: now.addingTimeInterval(30 * 60)))
        let afterFiveHourReset = try #require(cache.snapshot(for: .codex, now: now.addingTimeInterval(2 * 60 * 60)))
        let afterWeeklyReset = try #require(cache.snapshot(for: .codex, now: now.addingTimeInterval(9 * 24 * 60 * 60)))

        #expect(beforeReset.fiveHourRemainingPercent == 45)
        #expect(beforeReset.weeklyRemainingPercent == 60)
        #expect(beforeReset.dailyTokenUsage == 12_345)
        #expect(beforeReset.weeklyTokenUsage == 45_678)
        #expect(beforeReset.monthlyTokenUsage == 90_123)
        #expect(afterFiveHourReset.fiveHourRemainingPercent == 100)
        #expect(afterFiveHourReset.fiveHourResetAt == snapshot.fiveHourResetAt?.addingTimeInterval(5 * 60 * 60))
        #expect(afterFiveHourReset.weeklyRemainingPercent == 60)
        #expect(afterFiveHourReset.weeklyResetAt == snapshot.weeklyResetAt)
        #expect(afterWeeklyReset.fiveHourRemainingPercent == 100)
        #expect(afterWeeklyReset.weeklyRemainingPercent == 100)
        #expect(afterWeeklyReset.weeklyResetAt == snapshot.weeklyResetAt?.addingTimeInterval(2 * 7 * 24 * 60 * 60))
    }

    @Test func usageHistoryStoreRecordsAndPrunesEntries() throws {
        let suiteName = "agent-battery-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UsageHistoryStore(
            defaults: defaults,
            maxEntriesPerTool: 2,
            retention: 60
        )
        let start = Date(timeIntervalSince1970: 1_000)

        _ = store.record(historySnapshot(percent: 70), at: start)
        _ = store.record(historySnapshot(percent: 60), at: start.addingTimeInterval(30))
        _ = store.record(historySnapshot(percent: 50), at: start.addingTimeInterval(90))

        let history = store.history(for: .codex, now: start.addingTimeInterval(90))

        #expect(history.map(\.fiveHourRemainingPercent) == [60, 50])
        #expect(history.map(\.status) == [.available, .available])
    }

    @Test func codexProviderUsesLatestRateLimitEventAcrossRollouts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let olderEventInNewerFile = directory.appendingPathComponent("rollout-newer-file.jsonl")
        let newerEventInOlderFile = directory.appendingPathComponent("rollout-older-file.jsonl")

        try codexLine(
            timestamp: "2026-04-29T10:00:00Z",
            fiveHourUsed: 80,
            weeklyUsed: 30
        ).write(to: olderEventInNewerFile, atomically: true, encoding: .utf8)
        try codexLine(
            timestamp: "2026-04-29T12:00:00Z",
            fiveHourUsed: 25,
            weeklyUsed: 10
        ).write(to: newerEventInOlderFile, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: olderEventInNewerFile.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -60)],
            ofItemAtPath: newerEventInOlderFile.path
        )

        let snapshot = CodexUsageProvider().fetch(
            configuration: UsageDataConfiguration(
                codexSessionsPath: directory.path,
                staleInterval: .greatestFiniteMagnitude
            )
        )

        #expect(snapshot.status == .available)
        #expect(snapshot.fiveHourRemainingPercent == 75)
        #expect(snapshot.weeklyRemainingPercent == 90)
    }

    @Test func codexProviderParsesFractionalSecondTimestamps() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let rolloutURL = directory.appendingPathComponent("rollout-fractional.jsonl")
        try codexLine(
            timestamp: "2026-04-30T04:10:46.547Z",
            fiveHourUsed: 6,
            weeklyUsed: 39
        ).write(to: rolloutURL, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageProvider().fetch(
            configuration: UsageDataConfiguration(
                codexSessionsPath: directory.path,
                staleInterval: .greatestFiniteMagnitude
            )
        )
        let expectedUpdatedAt = try #require(ISO8601DateFormatter().date(from: "2026-04-30T04:10:46Z"))

        #expect(snapshot.status == .available)
        #expect(snapshot.updatedAt == expectedUpdatedAt)
        #expect(snapshot.fiveHourRemainingPercent == 94)
        #expect(snapshot.weeklyRemainingPercent == 61)
    }

    @Test func codexProviderSumsTodayTokenUsageAcrossRollouts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let dayInterval = try #require(Calendar.current.dateInterval(of: .day, for: Date()))
        let firstRollout = directory.appendingPathComponent("rollout-today-1.jsonl")
        let secondRollout = directory.appendingPathComponent("rollout-today-2.jsonl")

        try (
            codexLine(
                timestamp: ISO8601DateFormatter().string(from: dayInterval.start.addingTimeInterval(-60)),
                fiveHourUsed: 4,
                weeklyUsed: 8,
                totalTokens: 100
            ) +
            codexLine(
                timestamp: ISO8601DateFormatter().string(from: dayInterval.start.addingTimeInterval(60)),
                fiveHourUsed: 5,
                weeklyUsed: 9,
                totalTokens: 250
            ) +
            codexLine(
                timestamp: ISO8601DateFormatter().string(from: dayInterval.start.addingTimeInterval(120)),
                fiveHourUsed: 6,
                weeklyUsed: 10,
                totalTokens: 400
            )
        ).write(to: firstRollout, atomically: true, encoding: .utf8)

        try (
            codexLine(
                timestamp: ISO8601DateFormatter().string(from: dayInterval.start.addingTimeInterval(180)),
                fiveHourUsed: 7,
                weeklyUsed: 11,
                totalTokens: 50
            ) +
            codexLine(
                timestamp: ISO8601DateFormatter().string(from: dayInterval.start.addingTimeInterval(240)),
                fiveHourUsed: 8,
                weeklyUsed: 12,
                totalTokens: 80
            )
        ).write(to: secondRollout, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageProvider().fetch(
            configuration: UsageDataConfiguration(
                codexSessionsPath: directory.path,
                staleInterval: .greatestFiniteMagnitude
            )
        )

        #expect(snapshot.status == .available)
        #expect(snapshot.dailyTokenUsage == 380)
        #expect(snapshot.weeklyTokenUsage == 380)
        #expect(snapshot.monthlyTokenUsage == 380)
    }

    @Test func codexProviderExpandsTailUntilTokenCountIsFound() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let rolloutURL = directory.appendingPathComponent("rollout-large-tail.jsonl")
        let padding = """
        {"timestamp":"2026-04-30T04:11:00Z","type":"event_msg","payload":{"type":"exec_command_end","output":"\(String(repeating: "x", count: 1_100_000))"}}

        """
        try (codexLine(
            timestamp: "2026-04-30T04:10:46Z",
            fiveHourUsed: 12,
            weeklyUsed: 25
        ) + padding).write(to: rolloutURL, atomically: true, encoding: .utf8)

        let snapshot = CodexUsageProvider().fetch(
            configuration: UsageDataConfiguration(
                codexSessionsPath: directory.path,
                staleInterval: .greatestFiniteMagnitude
            )
        )

        #expect(snapshot.status == .available)
        #expect(snapshot.fiveHourRemainingPercent == 88)
        #expect(snapshot.weeklyRemainingPercent == 75)
    }

    @Test func usageStoreFetchesLatestCodexUsageOnStartup() async throws {
        let suiteName = "agent-battery-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let now = Date()
        let rolloutURL = directory.appendingPathComponent("rollout-startup.jsonl")
        try codexLine(
            timestamp: ISO8601DateFormatter().string(from: now),
            fiveHourUsed: 21,
            weeklyUsed: 34,
            fiveHourResetsAt: now.addingTimeInterval(60 * 60),
            weeklyResetsAt: now.addingTimeInterval(24 * 60 * 60)
        ).write(to: rolloutURL, atomically: true, encoding: .utf8)

        let settings = AppSettings(defaults: defaults)
        settings.codexSessionsPath = directory.path
        let store = UsageStore(
            settings: settings,
            snapshotCache: UsageSnapshotCache(defaults: defaults),
            historyStore: UsageHistoryStore(defaults: defaults)
        )
        let snapshot = await refreshedSnapshot(from: store, for: .codex) {
            $0.fiveHourRemainingPercent == 79
        }
        let history = store.history(for: .codex)

        #expect(snapshot.status == .available)
        #expect(snapshot.fiveHourRemainingPercent == 79)
        #expect(snapshot.weeklyRemainingPercent == 66)
        #expect(history.contains { $0.fiveHourRemainingPercent == 79 && $0.weeklyRemainingPercent == 66 })
    }

    private func codexLine(
        timestamp: String,
        fiveHourUsed: Double,
        weeklyUsed: Double
    ) -> String {
        codexLine(
            timestamp: timestamp,
            fiveHourUsed: fiveHourUsed,
            weeklyUsed: weeklyUsed,
            fiveHourResetsAt: Date(timeIntervalSince1970: 1_777_479_241),
            weeklyResetsAt: Date(timeIntervalSince1970: 1_777_996_864)
        )
    }

    private func codexLine(
        timestamp: String,
        fiveHourUsed: Double,
        weeklyUsed: Double,
        fiveHourResetsAt: Date,
        weeklyResetsAt: Date
    ) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","primary":{"used_percent":\(fiveHourUsed),"window_minutes":300,"resets_at":\(Int(fiveHourResetsAt.timeIntervalSince1970))},"secondary":{"used_percent":\(weeklyUsed),"window_minutes":10080,"resets_at":\(Int(weeklyResetsAt.timeIntervalSince1970))},"plan_type":"plus"}}}

        """
    }

    private func codexLine(
        timestamp: String,
        fiveHourUsed: Double,
        weeklyUsed: Double,
        totalTokens: Int
    ) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(totalTokens),"output_tokens":0,"total_tokens":\(totalTokens)}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":\(fiveHourUsed),"window_minutes":300,"resets_at":1777479241},"secondary":{"used_percent":\(weeklyUsed),"window_minutes":10080,"resets_at":1777996864},"plan_type":"plus"}}}

        """
    }

    private func refreshedSnapshot(
        from store: UsageStore,
        for tool: UsageTool,
        matching predicate: (UsageSnapshot) -> Bool
    ) async -> UsageSnapshot {
        let deadline = Date().addingTimeInterval(2)
        var snapshot = store.snapshot(for: tool)

        while !predicate(snapshot), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            snapshot = store.snapshot(for: tool)
        }

        return snapshot
    }

    private func historySnapshot(percent: Double) -> UsageSnapshot {
        UsageSnapshot(
            tool: .codex,
            fiveHourRemainingPercent: percent,
            weeklyRemainingPercent: percent + 10,
            fiveHourResetAt: nil,
            weeklyResetAt: nil,
            dailyTokenUsage: nil,
            weeklyTokenUsage: nil,
            monthlyTokenUsage: nil,
            updatedAt: nil,
            status: .available,
            message: nil
        )
    }

    private func usageSnapshot(fiveHour: Double?, weekly: Double?) -> UsageSnapshot {
        UsageSnapshot(
            tool: .codex,
            fiveHourRemainingPercent: fiveHour,
            weeklyRemainingPercent: weekly,
            fiveHourResetAt: nil,
            weeklyResetAt: nil,
            dailyTokenUsage: nil,
            weeklyTokenUsage: nil,
            monthlyTokenUsage: nil,
            updatedAt: nil,
            status: .available,
            message: nil
        )
    }
}
