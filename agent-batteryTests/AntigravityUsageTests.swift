import Foundation
import Testing
@testable import agent_battery

struct AntigravityUsageTests {
    @Test func providerParsesStandardBrainTranscriptsAndComputesBudget() throws {
        let brain = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-agy-tests-\(UUID().uuidString)")
        let conv1Logs = brain
            .appendingPathComponent("conv-1/.system_generated/logs", isDirectory: true)
        let conv2Logs = brain
            .appendingPathComponent("conv-2/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: conv1Logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conv2Logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: brain) }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        let t1 = formatter.string(from: now.addingTimeInterval(-120))
        let t2 = formatter.string(from: now.addingTimeInterval(-60))

        let conv1Content = """
        {"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"\(t1)","content":"hello"}
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"\(t1)","model":"gemini-4-neon-high","input_tokens":1000,"cache_read_tokens":3000,"output_tokens":500}
        {"step_index":2,"source":"MODEL","type":"GENERIC","status":"DONE","created_at":"\(t2)","content":"tool output"}
        """
        let conv2Content = """
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"\(t2)","model":"gemini-2.5-flash","input_tokens":500,"cache_read_tokens":500,"output_tokens":500}
        """

        try conv1Content.write(to: conv1Logs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
        try conv2Content.write(to: conv2Logs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let config = UsageDataConfiguration(
            codexSessionsPath: "/nonexistent",
            staleInterval: 600,
            antigravityBrainPath: brain.path,
            antigravityDailyTokenBudget: 10_000,
            antigravityWeeklyTokenBudget: 20_000
        )

        let snapshot = AntigravityUsageProvider().fetch(configuration: config, now: now)

        #expect(snapshot.tool == .antigravity)
        #expect(snapshot.status == .available)
        #expect(snapshot.isBudgetEstimated)
        #expect(snapshot.dailyTokenUsage == 6_000)
        #expect(snapshot.weeklyTokenUsage == 6_000)
        #expect(snapshot.monthlyTokenUsage == 6_000)
        #expect(snapshot.fiveHourRemainingPercent == 40)
        #expect(snapshot.weeklyRemainingPercent == 70)
        #expect(snapshot.tokenBreakdown == TokenBreakdown(inputTokens: 1_500, cacheReadTokens: 3_500, outputTokens: 1_000))
        #expect(snapshot.tokenBreakdown?.cacheHitRatio == 0.7)
        #expect(snapshot.topModels.first?.model == "Gemini 4 Neon High")
        #expect(snapshot.topModels.first?.tokens == 4_500)
        #expect(snapshot.topModels.count == 2)
    }

    @Test func providerClampsBudgetOverflowAtZeroAndHandlesMissingFolder() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-agy-missing-\(UUID().uuidString)")
        let missingSnapshot = AntigravityUsageProvider().fetch(configuration: UsageDataConfiguration(
            codexSessionsPath: "/nonexistent",
            staleInterval: 600,
            antigravityBrainPath: missing.path
        ))
        #expect(missingSnapshot.status == .unavailable)

        let brain = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-agy-over-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: brain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: brain) }

        let now = Date()
        let line = """
        {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"\(ISO8601DateFormatter().string(from: now))","model":"gemini-4-neon-high","input_tokens":50000,"cache_read_tokens":50000,"output_tokens":20000}
        """
        try line.write(to: brain.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = AntigravityUsageProvider().fetch(
            configuration: UsageDataConfiguration(
                codexSessionsPath: "/nonexistent",
                staleInterval: 600,
                antigravityBrainPath: brain.path,
                antigravityDailyTokenBudget: 100_000,
                antigravityWeeklyTokenBudget: 100_000
            ),
            now: now
        )
        #expect(snapshot.fiveHourRemainingPercent == 0)
        #expect(snapshot.weeklyRemainingPercent == 0)
    }

    @Test func providerInvalidatesCacheOnAppendAndDelete() throws {
        let brain = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-agy-cache-\(UUID().uuidString)")
        let logs = brain.appendingPathComponent("conv-a/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: brain) }

        let url = logs.appendingPathComponent("transcript.jsonl")
        let now = Date()
        let ts = ISO8601DateFormatter().string(from: now)
        let first = "{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(ts)\",\"model\":\"gemini-4-neon-high\",\"input_tokens\":1000,\"cache_read_tokens\":0,\"output_tokens\":200}\n"
        try first.write(to: url, atomically: true, encoding: .utf8)

        let provider = AntigravityUsageProvider()
        let config = UsageDataConfiguration(
            codexSessionsPath: "/nonexistent",
            staleInterval: 600,
            antigravityBrainPath: brain.path,
            antigravityDailyTokenBudget: 10_000,
            antigravityWeeklyTokenBudget: 50_000
        )

        #expect(provider.fetch(configuration: config, now: now).dailyTokenUsage == 1_200)
        #expect(provider.fetch(configuration: config, now: now).dailyTokenUsage == 1_200)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(ts)\",\"model\":\"gemini-4-neon-high\",\"input_tokens\":800,\"cache_read_tokens\":0,\"output_tokens\":0}\n".utf8))
        try handle.close()

        #expect(provider.fetch(configuration: config, now: now).dailyTokenUsage == 2_000)

        try FileManager.default.removeItem(at: url)
        #expect(provider.fetch(configuration: config, now: now).status == .unavailable)
    }

    @Test func usageSnapshotDecodesLegacyCachedPayloadWithoutNewFields() throws {
        let legacyJSON = """
        {
          "tool": "codex",
          "fiveHourRemainingPercent": 80,
          "weeklyRemainingPercent": 65,
          "dailyTokenUsage": 1200,
          "status": "available"
        }
        """
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacyJSON.utf8))
        #expect(decoded.tool == .codex)
        #expect(decoded.fiveHourRemainingPercent == 80)
        #expect(decoded.weeklyRemainingPercent == 65)
        #expect(decoded.tokenBreakdown == nil)
        #expect(decoded.topModels.isEmpty)
        #expect(!decoded.isBudgetEstimated)
    }

    @Test func appSettingsPersistsAntigravityPreferences() throws {
        let suiteName = "agent-battery-agy-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.selectedTool == .codex)
        #expect(settings.menuBarQuotaSource == .codex)
        #expect(settings.antigravityBrainPath == UsageDefaults.antigravityBrainPath)
        #expect(settings.antigravityDailyTokenBudget == UsageDefaults.antigravityDailyTokenBudget)
        #expect(settings.antigravityWeeklyTokenBudget == UsageDefaults.antigravityWeeklyTokenBudget)

        settings.selectedTool = .antigravity
        settings.menuBarQuotaSource = .both
        settings.antigravityDailyTokenBudget = 20_000_000
        settings.antigravityWeeklyTokenBudget = 100_000_000

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.selectedTool == .antigravity)
        #expect(reloaded.menuBarQuotaSource == .both)
        #expect(reloaded.antigravityDailyTokenBudget == 20_000_000)
        #expect(reloaded.antigravityWeeklyTokenBudget == 100_000_000)
    }
}
