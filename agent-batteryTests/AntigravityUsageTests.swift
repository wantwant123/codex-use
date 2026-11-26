import Foundation
import Testing
@testable import agent_battery

struct AntigravityUsageTests {
    @Test func quotaClientParsesRetrieveUserQuotaSummaryGroups() throws {
        let payload: [String: Any] = [
            "response": [
                "groups": [
                    [
                        "displayName": "Claude and GPT models",
                        "buckets": [
                            ["displayName": "Weekly limit", "window": "weekly", "remainingFraction": 0.50, "resetTime": "2026-12-03T13:50:00Z"],
                            ["displayName": "5h limit", "window": "5h", "remainingFraction": 1.0, "resetTime": "2026-11-26T16:50:00Z"],
                        ]
                    ],
                    [
                        "displayName": "Gemini Models",
                        "buckets": [
                            ["displayName": "Weekly limit", "window": "weekly", "remainingFraction": 0.82, "resetTime": "2026-12-03T14:50:00Z"],
                            ["displayName": "5h limit", "window": "5h", "remainingFraction": 0.31, "resetTime": "2026-11-26T12:11:00Z"],
                        ]
                    ]
                ]
            ]
        ]

        let groups = AntigravityQuotaClient.parseQuotaSummary(payload)
        #expect(groups.count == 2)
        // Gemini Models should be sorted first as primary.
        #expect(groups[0].name == "Gemini Models")
        #expect(groups[0].weeklyRemainingPercent == 82)
        #expect(groups[0].fiveHourRemainingPercent == 31)
        #expect(groups[0].weeklyResetAt != nil)
        #expect(groups[0].fiveHourResetAt != nil)
        #expect(groups[1].name == "Claude and GPT models")
        #expect(groups[1].weeklyRemainingPercent == 50)
        #expect(groups[1].fiveHourRemainingPercent == 100)
    }

    @Test func quotaClientFallsBackToGetUserStatusModelConfigs() {
        let payload: [String: Any] = [
            "userStatus": [
                "cascadeModelConfigData": [
                    "clientModelConfigs": [
                        [
                            "label": "Gemini 4 Neon (High)",
                            "quotaInfo": ["remainingFraction": 0.31, "resetTime": "2026-11-26T12:11:00Z"]
                        ],
                        [
                            "label": "Gemini 3 Flash",
                            "quotaInfo": ["remainingFraction": 0.85, "resetTime": "2026-11-26T12:11:00Z"]
                        ],
                        [
                            "label": "Claude Sonnet 4.5",
                            "quotaInfo": ["remainingFraction": 0.50, "resetTime": "2026-12-03T13:50:00Z"]
                        ]
                    ]
                ]
            ]
        ]

        let groups = AntigravityQuotaClient.parseUserStatus(payload)
        #expect(groups.count == 2)
        #expect(groups[0].name == "Gemini Models")
        #expect(groups[0].fiveHourRemainingPercent == 31)
        #expect(groups[1].name == "Claude and GPT models")
        #expect(groups[1].fiveHourRemainingPercent == 50)
    }

    @Test func quotaClientParsesProcessAndLsofDiscoveryOutput() {
        let ps = """
          101 /usr/libexec/other --flag 1
          202 /Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm --csrf_token=abc-123-xyz --extension_server_port 54321
          303 /Users/test/language_server_macos --csrf_token "quoted-token"
        """
        let instances = AntigravityQuotaClient.parseServerInstances(from: ps)
        #expect(instances.count == 2)
        #expect(instances[0].pid == 202)
        #expect(instances[0].csrfToken == "abc-123-xyz")
        #expect(instances[0].hintPort == 54321)
        #expect(instances[1].pid == 303)
        #expect(instances[1].csrfToken == "quoted-token")

        let lsof = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        language_ 202 user   10u  IPv4 0x1234      0t0  TCP 127.0.0.1:51234 (LISTEN)
        language_ 202 user   11u  IPv4 0x5678      0t0  TCP 127.0.0.1:54321 (LISTEN)
        language_ 202 user   12u  IPv6 0x9999      0t0  TCP [::1]:51235 (LISTEN)
        """
        let ports = AntigravityQuotaClient.parseListeningPorts(from: lsof, preferred: 54321)
        #expect(ports == [51234, 51235, 54321])
    }

    @Test func providerCombinesLiveQuotaGroupsWithLocalTranscriptTokens() throws {
        let brain = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-agy-tests-\(UUID().uuidString)")
        let conv1Logs = brain.appendingPathComponent("conv-1/.system_generated/logs", isDirectory: true)
        let conv2Logs = brain.appendingPathComponent("conv-2/.system_generated/logs", isDirectory: true)
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
        """
        let conv2Content = """
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"\(t2)","model":"gemini-2.5-flash","input_tokens":500,"cache_read_tokens":500,"output_tokens":500}
        """

        try conv1Content.write(to: conv1Logs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
        try conv2Content.write(to: conv2Logs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let liveGroups = [
            QuotaGroup(id: "gemini", name: "Gemini Models", fiveHourRemainingPercent: 31, fiveHourResetAt: now.addingTimeInterval(1200), weeklyRemainingPercent: 82, weeklyResetAt: now.addingTimeInterval(86_400)),
            QuotaGroup(id: "claude-gpt", name: "Claude and GPT models", fiveHourRemainingPercent: 100, fiveHourResetAt: nil, weeklyRemainingPercent: 50, weeklyResetAt: now.addingTimeInterval(86_400)),
        ]
        let provider = AntigravityUsageProvider(readLiveQuotaGroups: { liveGroups })
        let config = UsageDataConfiguration(
            codexSessionsPath: "/nonexistent",
            staleInterval: 600,
            antigravityBrainPath: brain.path
        )

        let snapshot = provider.fetch(configuration: config, now: now)

        #expect(snapshot.tool == .antigravity)
        #expect(snapshot.status == .available)
        #expect(!snapshot.isBudgetEstimated)
        #expect(snapshot.quotaGroups.count == 2)
        #expect(snapshot.fiveHourRemainingPercent == 31)
        #expect(snapshot.weeklyRemainingPercent == 82)
        #expect(snapshot.dailyTokenUsage == 6_000)
        #expect(snapshot.weeklyTokenUsage == 6_000)
        #expect(snapshot.monthlyTokenUsage == 6_000)
        #expect(snapshot.tokenBreakdown == TokenBreakdown(inputTokens: 1_500, cacheReadTokens: 3_500, outputTokens: 1_000))
        #expect(snapshot.topModels.first?.model == "Gemini 4 Neon High")
    }

    @Test func providerReportsStaleLocalTokensWhenAntigravityNotRunning() throws {
        let brain = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-battery-agy-offline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: brain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: brain) }

        let now = Date()
        let line = "{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(ISO8601DateFormatter().string(from: now))\",\"model\":\"gemini-4-neon-high\",\"input_tokens\":1000,\"cache_read_tokens\":2000,\"output_tokens\":200}\n"
        try line.write(to: brain.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let provider = AntigravityUsageProvider(readLiveQuotaGroups: { throw AntigravityQuotaClient.ClientError.serverNotRunning })
        let snapshot = provider.fetch(
            configuration: UsageDataConfiguration(codexSessionsPath: "/nonexistent", staleInterval: 600, antigravityBrainPath: brain.path),
            now: now
        )
        #expect(snapshot.status == .stale)
        #expect(snapshot.quotaGroups.isEmpty)
        #expect(snapshot.fiveHourRemainingPercent == nil)
        #expect(snapshot.dailyTokenUsage == 3_200)
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
        #expect(decoded.quotaGroups.isEmpty)
        #expect(!decoded.isBudgetEstimated)
    }
}
