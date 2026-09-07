import Darwin
import Foundation
import SQLite3
import Testing
@testable import agent_battery

struct LiveQuotaTests {
    @Test func liveAccountWinsOverLocalTwentyThreePercent() throws {
        let sessions = try makeSessions()
        defer { try? FileManager.default.removeItem(at: sessions.deletingLastPathComponent().deletingLastPathComponent()) }
        try localEvent(used: 77, timestamp: Date().addingTimeInterval(60))
            .write(to: sessions.appendingPathComponent("rollout-old.jsonl"), atomically: true, encoding: .utf8)
        let provider = CodexUsageProvider(readLiveRateLimits: { _ in self.response(used: 88) })
        let result = provider.fetch(configuration: configuration(sessions))
        #expect(result.weeklyRemainingPercent == 12)
        #expect(result.fiveHourRemainingPercent == nil)
        #expect(result.status == .available)
        #expect(result.dailyTokenUsage == 100)
    }

    @Test func liveQuotaWorksWithoutLocalRollouts() throws {
        let sessions = try makeSessions()
        defer { try? FileManager.default.removeItem(at: sessions.deletingLastPathComponent().deletingLastPathComponent()) }
        try FileManager.default.removeItem(at: sessions)
        let provider = CodexUsageProvider(readLiveRateLimits: { _ in self.response(used: 88) })
        let result = provider.fetch(configuration: configuration(sessions))
        #expect(result.weeklyRemainingPercent == 12)
        #expect(result.monthlyTokenUsage == nil)
        #expect(result.status == .available)
    }

    @Test func failedLiveQueryMarksLocalReadingStaleEvenWhenRecent() throws {
        let sessions = try makeSessions()
        defer { try? FileManager.default.removeItem(at: sessions.deletingLastPathComponent().deletingLastPathComponent()) }
        let timestamp = Date().addingTimeInterval(-30)
        try localEvent(used: 77, timestamp: timestamp)
            .write(to: sessions.appendingPathComponent("rollout-old.jsonl"), atomically: true, encoding: .utf8)
        let provider = CodexUsageProvider(readLiveRateLimits: { _ in throw CodexRateLimitClient.ClientError.timedOut })
        let result = provider.fetch(configuration: configuration(sessions))
        #expect(result.weeklyRemainingPercent == 23)
        #expect(result.status == .stale)
        #expect(result.updatedAt! <= timestamp)
        #expect(result.message != nil)
    }

    @Test func selectsCodexBucketAndDoesNotSubstituteSpark() {
        #expect(CodexRateLimitClient.codexLimit(in: response(used: 88))?["limitId"] as? String == "codex")
        let spark: [String: Any] = ["limitId": "codex_bengalfox", "primary": ["usedPercent": 0]]
        #expect(CodexRateLimitClient.codexLimit(in: ["rateLimitsByLimitId": ["codex_bengalfox": spark], "rateLimits": spark]) == nil)
        #expect(CodexRateLimitClient.codexLimit(in: ["rateLimits": spark]) == nil)
        #expect(CodexRateLimitClient.codexLimit(in: ["rateLimits": ["primary": ["usedPercent": 88]]]) != nil)
    }

    @Test func sqliteFileModificationDoesNotMakeAnOldEventNew() throws {
        let sessions = try makeSessions()
        let home = sessions.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }
        let now = Date()
        try localEvent(used: 88, timestamp: now.addingTimeInterval(-60))
            .write(to: sessions.appendingPathComponent("rollout-current.jsonl"), atomically: true, encoding: .utf8)
        var database: OpaquePointer?
        #expect(sqlite3_open(home.appendingPathComponent("logs_2.sqlite").path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let event = "{\"type\":\"codex.rate_limits\",\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":77,\"window_minutes\":10080}}}"
        let sql = "CREATE TABLE logs(feedback_log_body TEXT, ts INTEGER, ts_nanos INTEGER); INSERT INTO logs VALUES ('\(event)', \(Int(now.timeIntervalSince1970) - 3600), 0);"
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        let provider = CodexUsageProvider(readLiveRateLimits: { _ in throw CodexRateLimitClient.ClientError.unavailable })
        let result = provider.fetch(configuration: configuration(sessions))
        #expect(result.weeklyRemainingPercent == 12)
        #expect(result.status == .stale)
    }

    @MainActor @Test func olderOfflineReadingDoesNotReplaceNewerCachedQuota() async throws {
        let sessions = try makeSessions()
        defer { try? FileManager.default.removeItem(at: sessions.deletingLastPathComponent().deletingLastPathComponent()) }
        let rollout = sessions.appendingPathComponent("rollout-old.jsonl")
        try localEvent(used: 77, timestamp: Date().addingTimeInterval(-3600))
            .write(to: rollout, atomically: true, encoding: .utf8)
        let suite = "agent-battery-live-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = UsageSnapshotCache(defaults: defaults)
        let fresh = UsageSnapshot(tool: .codex, fiveHourRemainingPercent: nil, weeklyRemainingPercent: 12,
                                  fiveHourResetAt: nil, weeklyResetAt: nil, dailyTokenUsage: nil, weeklyTokenUsage: nil,
                                  monthlyTokenUsage: nil, updatedAt: Date(), status: .available, message: nil)
        cache.store(fresh)
        let settings = AppSettings(defaults: defaults)
        settings.codexSessionsPath = rollout.path // Offline file; do not query an account in this test.
        let store = UsageStore(settings: settings, snapshotCache: cache, historyStore: UsageHistoryStore(defaults: defaults))
        let deadline = Date().addingTimeInterval(2)
        while store.lastRefreshAt == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.lastRefreshAt != nil)
        #expect(store.primarySnapshot.weeklyRemainingPercent == 12)
        #expect(store.primarySnapshot.status == .stale)
    }

    @Test func clientHandlesHandshakeAndChunkedReply() throws {
        let sessions = try makeSessions()
        let home = sessions.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }
        let reply = String(decoding: try JSONSerialization.data(withJSONObject: ["id": 2, "result": response(used: 88)]), as: UTF8.self)
        let script = try makeServer(in: home, action: "reply = r'''\(reply)'''\n  sys.stdout.write(reply[:20]); sys.stdout.flush()\n  time.sleep(0.02)\n  print(reply[20:], flush=True)")
        let result = try CodexRateLimitClient(executableURL: script, timeout: 5).fetch(codexHomeURL: home)
        #expect(CodexRateLimitClient.codexLimit(in: result)?["limitId"] as? String == "codex")
    }

    @Test func clientTimesOutAndReapsUnresponsiveChild() throws {
        let sessions = try makeSessions()
        let home = sessions.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }
        // Use the system shell so interpreter cold-start time cannot hide the PID.
        let script = home.appendingPathComponent("unresponsive-codex")
        try """
        #!/bin/sh
        printf '%s' "$$" > server.pid
        read -r request
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r notification
        read -r request
        exec /bin/sleep 30
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let start = Date()
        #expect(throws: CodexRateLimitClient.ClientError.self) {
            try CodexRateLimitClient(executableURL: script, timeout: 5).fetch(codexHomeURL: home)
        }
        #expect(Date().timeIntervalSince(start) < 7)
        let pid = try #require(Int32(String(contentsOf: home.appendingPathComponent("server.pid"), encoding: .utf8)))
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test func clientRejectsErrorReply() throws {
        let sessions = try makeSessions()
        let home = sessions.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }
        let script = try makeServer(in: home, action: "print(json.dumps({'id':2,'error':{'code':-32603,'message':'offline'}}), flush=True)")
        #expect(throws: CodexRateLimitClient.ClientError.self) {
            try CodexRateLimitClient(executableURL: script, timeout: 5).fetch(codexHomeURL: home)
        }
    }

    private func makeServer(in home: URL, action: String) throws -> URL {
        let script = home.appendingPathComponent("fake-codex")
        let code = """
        #!/usr/bin/python3
        import sys, json, time, os
        open('server.pid', 'w').write(str(os.getpid()))
        for line in sys.stdin:
         message = json.loads(line)
         if message.get('id') == 1:
          print(json.dumps({'id':1,'result':{}}), flush=True)
         elif message.get('id') == 2:
          \(action)
        """
        try code.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func makeSessions() throws -> URL {
        let sessions = FileManager.default.temporaryDirectory.appendingPathComponent("agent-battery-live-\(UUID().uuidString)/.codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        return sessions
    }

    private func configuration(_ sessions: URL) -> UsageDataConfiguration {
        UsageDataConfiguration(codexSessionsPath: sessions.path, staleInterval: 300)
    }

    private func response(used: Double) -> [String: Any] {
        let codex: [String: Any] = ["limitId": "codex", "primary": ["usedPercent": used, "windowDurationMins": 10080, "resetsAt": Date().timeIntervalSince1970 + 3600], "secondary": NSNull()]
        return ["rateLimits": ["limitId": "codex", "primary": ["usedPercent": 77]],
                "rateLimitsByLimitId": ["codex": codex, "codex_bengalfox": ["limitId": "codex_bengalfox", "primary": ["usedPercent": 0]]]]
    }

    private func localEvent(used: Double, timestamp: Date) -> String {
        """
        {"timestamp":"\(ISO8601DateFormatter().string(from: timestamp))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":\(used),"window_minutes":10080}}}}
        """
    }
}
