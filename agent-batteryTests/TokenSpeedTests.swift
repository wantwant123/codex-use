import Foundation
import Testing
@testable import agent_battery

struct TokenSpeedTests {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func excludesInputTokensAndOverlappingToolExecution() throws {
        let sample = try #require(parse([
            event(0, ["type": "task_started"]),
            item("Reasoning", start: 1, end: 3),
            item("CommandExecution", start: 4, end: 12),
            item("McpToolCall", start: 8, end: 14),
            usage(20, total: 400, last: 400)
        ]))
        // 400 output tokens / (20 seconds - 10 seconds of tool time).
        // Reasoning is already included in output_tokens, so it must not be added again.
        #expect(sample.outputTokens == 400)
        #expect(sample.duration == 10)
        #expect(sample.tokensPerSecond == 40)
    }

    @Test func deduplicatesCountsAndExcludesTimeBetweenUserTurns() throws {
        let sample = try #require(parse([
            event(0, ["type": "task_started"]), item("AgentMessage", start: 1, end: 10),
            usage(10, total: 200, last: 200),
            usage(11, total: 200, last: 200),
            event(12, ["type": "task_complete"]),
            event(1000, ["type": "task_started"]),
            item("AgentMessage", start: 1001, end: 1010),
            usage(1010, total: 500, last: 300)
        ]))
        #expect(sample.tokensPerSecond == 30)
        #expect(sample.recordedAt == epoch.addingTimeInterval(1010))
    }

    @Test func keepsModelStreamingTimeWhenToolsRunConcurrently() throws {
        let sample = try #require(parse([
            event(0, ["type": "task_started"]),
            item("Reasoning", start: 0, end: 10),
            item("CommandExecution", start: 5, end: 20),
            usage(20, total: 100, last: 100)
        ]))
        #expect(sample.duration == 10)
        #expect(sample.tokensPerSecond == 10)
    }

    @Test func requiresBothBoundariesAndSupportedTiming() {
        #expect(parse([usage(10, total: 100, last: 100)]) == nil)
        #expect(parse([event(0, ["type": "task_started"]), usage(10, total: 100, last: 100)]) == nil)
        #expect(parse([
            event(0, ["type": "task_started"]),
            event(5, ["type": "item_completed", "item": ["type": "CommandExecution"]]),
            usage(10, total: 100, last: 100)
        ]) == nil)
        #expect(parse([
            event(0, ["type": "task_started"]), item("CommandExecution", start: 0, end: 10),
            usage(10, total: 100, last: 100)
        ]) == nil)
    }

    @Test func missingSamplesAndResetCountersDoNotInventSpeed() {
        for (total, last) in [(300, 100), (50, 50), (90, -10)] {
            #expect(parse([
                usage(10, total: 100, last: 100),
                item("AgentMessage", start: 11, end: 20),
                usage(20, total: total, last: last)
            ]) == nil)
        }
    }

    @Test func readsAppendedResultsExpiresAndResetsAfterTruncation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-speed.jsonl")
        var lines = [event(0, ["type": "task_started"]), item("AgentMessage", start: 1, end: 10),
                     usage(10, total: 200, last: 200)]
        try Data(lines.joined(separator: "\n").utf8).write(to: file)
        let reader = CodexTokenSpeedReader()
        #expect(try reader.read(path: file.path, now: epoch.addingTimeInterval(11))?.tokensPerSecond == 20)
        lines += [item("AgentMessage", start: 11, end: 20), usage(20, total: 500, last: 300)]
        try Data(lines.joined(separator: "\n").utf8).write(to: file)
        #expect(try reader.read(path: file.path, now: epoch.addingTimeInterval(21))?.tokensPerSecond == 30)
        #expect(try reader.read(path: file.path, now: epoch.addingTimeInterval(81)) == nil)
        try Data(usage(90, total: 100, last: 100).utf8).write(to: file)
        #expect(try reader.read(path: file.path, now: epoch.addingTimeInterval(91)) == nil)
    }

    @Test func partialTailDoesNotCreateAFalseSample() {
        #expect(CodexTokenSpeedReader.parse(Data(("{broken\n" + usage(10, total: 200, last: 200)).utf8)) == nil)
        let lines = [event(0, ["type": "task_started"]), item("AgentMessage", start: 1, end: 10),
                     usage(10, total: 200, last: 200)]
        #expect(CodexTokenSpeedReader.parse(Data((lines.joined(separator: "\n") + "\n{\"type\":\"event_msg\"").utf8))?.tokensPerSecond == 20)
    }

    private func parse(_ lines: [String]) -> TokenSpeedSample? {
        CodexTokenSpeedReader.parse(Data(lines.joined(separator: "\n").utf8))
    }

    private func event(_ seconds: Double, _ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [
            "timestamp": ISO8601DateFormatter().string(from: epoch.addingTimeInterval(seconds)),
            "type": "event_msg", "payload": payload
        ])
        return String(decoding: data, as: UTF8.self)
    }

    private func item(_ type: String, start: Double, end: Double) -> String {
        event(end, ["type": "item_completed", "item": ["type": type],
                    "started_at_ms": epoch.addingTimeInterval(start).timeIntervalSince1970 * 1000,
                    "completed_at_ms": epoch.addingTimeInterval(end).timeIntervalSince1970 * 1000])
    }

    private func usage(_ seconds: Double, total: Int, last: Int) -> String {
        event(seconds, ["type": "token_count", "info": [
            "total_token_usage": ["output_tokens": total, "input_tokens": 900_000],
            "last_token_usage": ["output_tokens": last, "reasoning_output_tokens": 50, "input_tokens": 90_000]
        ]])
    }
}
