import Foundation

nonisolated struct TokenSpeedSample: Equatable, Sendable {
    let outputTokens: Int
    let duration: TimeInterval
    let recordedAt: Date

    var tokensPerSecond: Double { Double(outputTokens) / duration }
}

/// Reads completed sampling intervals only. Input tokens and tool execution time are excluded.
nonisolated final class CodexTokenSpeedReader {
    private let tailLimit = 512 * 1024
    private var discoveredAt = Date.distantPast
    private var sourcePath = ""
    private var files: [URL] = []
    private var cache: [URL: (modified: Date, size: Int, sample: TokenSpeedSample?)] = [:]

    func read(path: String, now: Date = Date()) throws -> TokenSpeedSample? {
        let root = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        if sourcePath != path || now.timeIntervalSince(discoveredAt) >= 10 {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
            var candidates: [(URL, Date)] = []
            if root.pathExtension == "jsonl" {
                candidates = [(root, now)]
            } else {
                guard let enumerator = FileManager.default.enumerator(at: root,
                    includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                    return nil
                }
                for case let url as URL in enumerator where url.pathExtension == "jsonl"
                    && url.lastPathComponent.hasPrefix("rollout-") {
                    guard let metadata = try? url.resourceValues(forKeys: Set(keys)), metadata.isRegularFile == true,
                          let modified = metadata.contentModificationDate, now.timeIntervalSince(modified) < 120 else { continue }
                    candidates.append((url, modified))
                }
            }
            files = candidates.sorted { $0.1 > $1.1 }.prefix(12).map(\.0)
            cache = cache.filter { files.contains($0.key) }
            sourcePath = path
            discoveredAt = now
        }

        for url in files {
            // One unavailable or rotated session must not hide readings from other sessions.
            guard let metadata = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = metadata.fileSize, let modified = metadata.contentModificationDate else {
                cache.removeValue(forKey: url)
                continue
            }
            if let saved = cache[url], saved.size == size, saved.modified == modified { continue }
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                cache.removeValue(forKey: url)
                continue
            }
            defer { try? handle.close() }
            let offset = max(0, size - tailLimit)
            try handle.seek(toOffset: UInt64(offset))
            var data = try handle.read(upToCount: tailLimit) ?? Data()
            if offset > 0 {
                // The first line may be truncated. A complete boundary is required for a speed sample.
                if let newline = data.firstIndex(of: 10) { data = Data(data.suffix(from: newline + 1)) }
                else { data = Data() }
            }
            cache[url] = (modified, size, Self.parse(data))
        }
        return cache.values.compactMap(\.sample)
            .filter { now.timeIntervalSince($0.recordedAt) >= 0 && now.timeIntervalSince($0.recordedAt) <= 60 }
            .max { $0.recordedAt < $1.recordedAt }
    }

    static func parse(_ data: Data) -> TokenSpeedSample? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainISO = ISO8601DateFormatter()
        var start: Date?
        var previousOutput: Int?
        var tools: [DateInterval] = []
        var modelItems: [DateInterval] = []
        var timingIsComplete = true
        var hasTimedItems = false
        var latest: TokenSpeedSample?

        for line in data.split(separator: 10) {
            guard line.range(of: Data("\"event_msg\"".utf8)) != nil else { continue }
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  event["type"] as? String == "event_msg",
                  let payload = event["payload"] as? [String: Any],
                  let type = payload["type"] as? String,
                  let timestamp = event["timestamp"] as? String,
                  let date = iso.date(from: timestamp) ?? plainISO.date(from: timestamp) else {
                timingIsComplete = false
                continue
            }
            switch type {
            case "task_started":
                start = date
                tools = []
                modelItems = []
                timingIsComplete = true
                hasTimedItems = false
            case "task_complete", "turn_aborted":
                start = nil
                tools = []
                modelItems = []
            case "item_completed":
                guard let item = payload["item"] as? [String: Any], let kind = item["type"] as? String else {
                    timingIsComplete = false
                    continue
                }
                if kind == "UserMessage" { continue }
                guard let begin = payload["started_at_ms"] as? Double,
                      let end = payload["completed_at_ms"] as? Double, end >= begin else {
                    timingIsComplete = false
                    continue
                }
                hasTimedItems = true
                let itemInterval = DateInterval(start: Date(timeIntervalSince1970: begin / 1000),
                                                end: Date(timeIntervalSince1970: end / 1000))
                if ["AgentMessage", "Reasoning"].contains(kind) { modelItems.append(itemInterval) }
                else { tools.append(itemInterval) }
            case "token_count":
                guard let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any],
                      let output = total["output_tokens"] as? Int, output >= 0 else { continue }
                // Rate-limit-only events can repeat the last usage. They are not new samples.
                if previousOutput == output { continue }
                let last = (info["last_token_usage"] as? [String: Any])?["output_tokens"] as? Int
                if let start, date > start, timingIsComplete, hasTimedItems, let last, last > 0, last <= output,
                   previousOutput == nil || output - previousOutput! == last {
                    let interval = DateInterval(start: start, end: date)
                    // A tool can begin before the model finishes streaming. Keep that overlap.
                    let overlaps = tools.flatMap { tool in modelItems.compactMap { tool.intersection(with: $0) } }
                    let duration = interval.duration - toolDuration(tools, within: interval)
                        + toolDuration(overlaps, within: interval)
                    if duration >= 0.1 {
                        latest = TokenSpeedSample(outputTokens: last, duration: duration, recordedAt: date)
                    }
                }
                previousOutput = output
                start = date
                tools = []
                modelItems = []
                timingIsComplete = true
                hasTimedItems = false
            default:
                break
            }
        }
        return latest
    }

    private static func toolDuration(_ tools: [DateInterval], within interval: DateInterval) -> TimeInterval {
        let ranges = tools.compactMap { $0.intersection(with: interval) }.sorted { $0.start < $1.start }
        var end = interval.start
        var duration: TimeInterval = 0
        for range in ranges where range.end > end {
            duration += range.end.timeIntervalSince(max(end, range.start))
            end = range.end
        }
        return duration
    }
}
