import Foundation

final class AntigravityUsageProvider {
    private let readChunkBytes = 65_536
    private let maxEventLineBytes = 1_048_576
    private let plannerResponseMarker = Data("\"PLANNER_RESPONSE\"".utf8)
    private let fetchLock = NSLock()
    private var fileCache: [URL: CachedTranscriptStats] = [:]
    private let readLiveQuotaGroups: () throws -> [QuotaGroup]

    init(readLiveQuotaGroups: (() throws -> [QuotaGroup])? = nil) {
        if let readLiveQuotaGroups {
            self.readLiveQuotaGroups = readLiveQuotaGroups
        } else {
            let client = AntigravityQuotaClient()
            self.readLiveQuotaGroups = {
                try client.fetchQuotaGroups()
            }
        }
    }

    func fetch(configuration: UsageDataConfiguration, now: Date = Date()) -> UsageSnapshot {
        fetchLock.lock()
        defer { fetchLock.unlock() }

        let liveGroups = (try? readLiveQuotaGroups()) ?? []
        let localTokens = readLocalTokenSummary(
            brainPath: configuration.antigravityBrainPath,
            now: now
        )

        if !liveGroups.isEmpty {
            let primary = liveGroups[0]
            return UsageSnapshot(
                tool: .antigravity,
                fiveHourRemainingPercent: primary.fiveHourRemainingPercent,
                weeklyRemainingPercent: primary.weeklyRemainingPercent,
                fiveHourResetAt: primary.fiveHourResetAt,
                weeklyResetAt: primary.weeklyResetAt,
                dailyTokenUsage: localTokens?.dailyTokens,
                weeklyTokenUsage: localTokens?.weeklyTokens,
                monthlyTokenUsage: localTokens?.monthlyTokens,
                updatedAt: now,
                status: .available,
                message: nil,
                tokenBreakdown: localTokens?.breakdown,
                topModels: localTokens?.topModels ?? [],
                quotaGroups: liveGroups,
                isBudgetEstimated: false
            )
        }

        if let localTokens {
            return UsageSnapshot(
                tool: .antigravity,
                fiveHourRemainingPercent: nil,
                weeklyRemainingPercent: nil,
                fiveHourResetAt: nil,
                weeklyResetAt: nil,
                dailyTokenUsage: localTokens.dailyTokens,
                weeklyTokenUsage: localTokens.weeklyTokens,
                monthlyTokenUsage: localTokens.monthlyTokens,
                updatedAt: localTokens.latestEventAt ?? now,
                status: .stale,
                message: String(localized: "provider.antigravityLiveUnavailable"),
                tokenBreakdown: localTokens.breakdown,
                topModels: localTokens.topModels,
                quotaGroups: [],
                isBudgetEstimated: false
            )
        }

        return .unavailable(
            tool: .antigravity,
            message: String(localized: "provider.antigravityLiveUnavailable")
        )
    }

    private func readLocalTokenSummary(brainPath: String, now: Date) -> LocalTokenSummary? {
        let path = NSString(string: brainPath).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: path)

        guard let transcripts = try? transcriptFiles(from: rootURL), !transcripts.isEmpty else {
            return nil
        }

        let calendar = Calendar.current
        let dayInterval = calendar.dateInterval(of: .day, for: now)
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let monthInterval = calendar.dateInterval(of: .month, for: now)
        let intervals = [dayInterval, weekInterval, monthInterval]
        let earliestStart = intervals.compactMap { $0?.start }.min() ?? .distantFuture

        let relevant = transcripts.filter { $0.modifiedAt >= earliestStart }
        let relevantURLs = Set(relevant.map(\.url))
        fileCache = fileCache.filter { relevantURLs.contains($0.key) }

        var dailyTokens = 0
        var weeklyTokens = 0
        var monthlyTokens = 0
        var dailyInput = 0
        var dailyCacheRead = 0
        var dailyOutput = 0
        var weeklyModelTotals: [String: Int] = [:]
        var latestEventAt: Date?

        for file in relevant {
            guard let stats = try? cachedOrParsedStats(for: file.url, intervals: intervals) else {
                continue
            }
            dailyTokens += stats.dailyTokens
            weeklyTokens += stats.weeklyTokens
            monthlyTokens += stats.monthlyTokens
            dailyInput += stats.dailyInput
            dailyCacheRead += stats.dailyCacheRead
            dailyOutput += stats.dailyOutput
            for (model, count) in stats.weeklyModelTotals {
                weeklyModelTotals[model, default: 0] += count
            }
            if let fileLatest = stats.latestEventAt,
               latestEventAt == nil || fileLatest > latestEventAt! {
                latestEventAt = fileLatest
            }
        }

        let breakdown = TokenBreakdown(
            inputTokens: dailyInput,
            cacheReadTokens: dailyCacheRead,
            outputTokens: dailyOutput
        )
        let topModels = weeklyModelTotals
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(3)
            .map { ModelTokenUsage(model: $0.key, tokens: $0.value) }

        return LocalTokenSummary(
            dailyTokens: dailyTokens,
            weeklyTokens: weeklyTokens,
            monthlyTokens: monthlyTokens,
            breakdown: breakdown,
            topModels: topModels,
            latestEventAt: latestEventAt ?? transcripts.first?.modifiedAt
        )
    }

    private func transcriptFiles(from rootURL: URL) throws -> [TranscriptFile] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            return []
        }

        if !isDirectory.boolValue {
            guard rootURL.pathExtension == "jsonl" else { return [] }
            let modified = (try? rootURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return [TranscriptFile(url: rootURL, modifiedAt: modified)]
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsPackageDescendants]
        )

        var files: [TranscriptFile] = []
        var seen = Set<String>()

        func appendIfExists(_ url: URL) {
            guard seen.insert(url.standardizedFileURL.path).inserted else { return }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                return
            }
            files.append(TranscriptFile(url: url, modifiedAt: values.contentModificationDate ?? .distantPast))
        }

        // Standard layout: <brain>/<conversation-id>/.system_generated/logs/transcript.jsonl
        for child in children {
            if child.pathExtension == "jsonl" {
                appendIfExists(child)
                continue
            }
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let transcript = child
                .appendingPathComponent(".system_generated", isDirectory: true)
                .appendingPathComponent("logs", isDirectory: true)
                .appendingPathComponent("transcript.jsonl")
            appendIfExists(transcript)
        }

        return files.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func cachedOrParsedStats(for url: URL, intervals: [DateInterval?]) throws -> ParsedTranscriptStats {
        let metadata = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        if let cached = fileCache[url],
           cached.modifiedAt == metadata.contentModificationDate,
           cached.fileSize == metadata.fileSize,
           cached.intervals == intervals {
            return cached.stats
        }

        let stats = try parseTranscript(at: url, intervals: intervals)
        fileCache[url] = CachedTranscriptStats(
            modifiedAt: metadata.contentModificationDate,
            fileSize: metadata.fileSize,
            intervals: intervals,
            stats: stats
        )
        return stats
    }

    private func parseTranscript(at url: URL, intervals: [DateInterval?]) throws -> ParsedTranscriptStats {
        let dayInterval = intervals.indices.contains(0) ? intervals[0] : nil
        let weekInterval = intervals.indices.contains(1) ? intervals[1] : nil
        let monthInterval = intervals.indices.contains(2) ? intervals[2] : nil

        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        var stats = ParsedTranscriptStats()

        try forEachPlannerLine(in: url) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "PLANNER_RESPONSE",
                  let createdAtString = object["created_at"] as? String,
                  let createdAt = isoWithFraction.date(from: createdAtString) ?? isoPlain.date(from: createdAtString)
            else {
                return
            }

            let input = Self.nonNegativeInt(object["input_tokens"])
            let cacheRead = Self.nonNegativeInt(object["cache_read_tokens"])
            let output = Self.nonNegativeInt(object["output_tokens"])
            let total = input + cacheRead + output
            guard total > 0 else { return }

            if stats.latestEventAt == nil || createdAt > stats.latestEventAt! {
                stats.latestEventAt = createdAt
            }

            if let dayInterval, dayInterval.contains(createdAt) {
                stats.dailyTokens += total
                stats.dailyInput += input
                stats.dailyCacheRead += cacheRead
                stats.dailyOutput += output
            }

            if let weekInterval, weekInterval.contains(createdAt) {
                stats.weeklyTokens += total
                if let model = (object["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !model.isEmpty {
                    stats.weeklyModelTotals[Self.displayModelName(model), default: 0] += total
                }
            }

            if let monthInterval, monthInterval.contains(createdAt) {
                stats.monthlyTokens += total
            }
        }

        return stats
    }

    private func forEachPlannerLine(in url: URL, consume: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var line = Data()
        var skippingOversizedLine = false

        func finishLine() {
            if !skippingOversizedLine, line.range(of: plannerResponseMarker) != nil {
                autoreleasepool { consume(line) }
            }
            line.removeAll(keepingCapacity: true)
            skippingOversizedLine = false
        }

        while let chunk = try autoreleasepool(invoking: { try handle.read(upToCount: readChunkBytes) }), !chunk.isEmpty {
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 10)
                let end = newline ?? chunk.endIndex
                if !skippingOversizedLine {
                    if line.count + end - start <= maxEventLineBytes {
                        line.append(contentsOf: chunk[start..<end])
                    } else {
                        line.removeAll(keepingCapacity: true)
                        skippingOversizedLine = true
                    }
                }
                if let newline {
                    finishLine()
                    start = newline + 1
                } else {
                    break
                }
            }
        }
        finishLine()
    }

    private static func nonNegativeInt(_ value: Any?) -> Int {
        switch value {
        case let value as Int:
            max(0, value)
        case let value as Double:
            max(0, Int(value.rounded()))
        case let value as NSNumber:
            max(0, value.intValue)
        case let value as String:
            max(0, Int(value) ?? 0)
        default:
            0
        }
    }

    static func displayModelName(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard !parts.isEmpty else { return raw }
        return parts.map { part in
            let token = String(part)
            if token.allSatisfy({ $0.isNumber || $0 == "." }) {
                return token
            }
            return token.prefix(1).uppercased() + token.dropFirst()
        }.joined(separator: " ")
    }
}

private struct TranscriptFile {
    let url: URL
    let modifiedAt: Date
}

private struct LocalTokenSummary {
    let dailyTokens: Int
    let weeklyTokens: Int
    let monthlyTokens: Int
    let breakdown: TokenBreakdown
    let topModels: [ModelTokenUsage]
    let latestEventAt: Date?
}

private struct ParsedTranscriptStats {
    var dailyTokens = 0
    var weeklyTokens = 0
    var monthlyTokens = 0
    var dailyInput = 0
    var dailyCacheRead = 0
    var dailyOutput = 0
    var weeklyModelTotals: [String: Int] = [:]
    var latestEventAt: Date?
}

private struct CachedTranscriptStats {
    let modifiedAt: Date?
    let fileSize: Int?
    let intervals: [DateInterval?]
    let stats: ParsedTranscriptStats
}
