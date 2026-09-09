import Foundation

/// One bounded, atomic checkpoint for today's observed traffic. No connection history or credentials.
nonisolated final class TrafficDailyCache: @unchecked Sendable {
    static let maxBytes = 16 * 1_024 * 1_024
    private let url: URL
    private let lock = NSLock()
    private var lastSavedAt: Date?
    private var failed = false

    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentBattery/traffic-today.json")) {
        self.url = url
    }

    var hasError: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failed
    }

    func load(controller: String, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> TrafficSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maxBytes + 1) ?? Data()
            guard data.count <= Self.maxBytes else { throw CacheError.invalid }
            let record = try JSONDecoder().decode(Record.self, from: data)
            guard record.version == 1, record.controller == controller,
                  record.day == calendar.startOfDay(for: now) else { return nil }
            guard record.entries.count <= 2_003, Set(record.entries.map(\.key)).count == record.entries.count,
                  valid(record.total), record.entries.allSatisfy({ valid($0.bytes) && $0.key.app.utf8.count <= 4_096 && $0.key.domain.utf8.count <= 512 }),
                  record.startedAt >= record.day, record.updatedAt >= record.startedAt, record.updatedAt <= now else {
                throw CacheError.invalid
            }
            failed = false
            return TrafficSnapshot(dayStart: record.day, startedAt: record.startedAt, updatedAt: record.updatedAt,
                total: record.total, entries: record.entries.map { TrafficEntry(key: $0.key, bytes: $0.bytes) },
                hasGaps: true, isLimited: record.isLimited)
        } catch {
            failed = true
            return nil
        }
    }

    func save(_ snapshot: TrafficSnapshot, controller: String, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        lock.lock()
        defer { lock.unlock() }
        guard let day = snapshot.dayStart, day == calendar.startOfDay(for: now),
              let start = snapshot.startedAt, let updated = snapshot.updatedAt,
              lastSavedAt.map({ updated >= $0 }) ?? true else { return }
        do {
            guard snapshot.entries.count <= 2_003, valid(snapshot.total), snapshot.entries.allSatisfy({ valid($0.bytes) }) else {
                throw CacheError.invalid
            }
            let record = Record(version: 1, controller: controller, day: day, startedAt: start, updatedAt: updated,
                total: snapshot.total, entries: snapshot.entries.map { TrafficEntry(key: $0.key, bytes: $0.bytes) }, isLimited: snapshot.isLimited)
            let data = try JSONEncoder().encode(record)
            guard data.count <= Self.maxBytes else { throw CacheError.invalid }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            lastSavedAt = updated
            failed = false
        } catch { failed = true }
    }

    private func valid(_ bytes: TrafficBytes) -> Bool {
        bytes.upload.isFinite && bytes.download.isFinite && bytes.upload >= 0 && bytes.download >= 0
    }

    private enum CacheError: Error { case invalid }
    private struct Record: Codable {
        let version: Int
        let controller: String
        let day: Date
        let startedAt: Date
        let updatedAt: Date
        let total: TrafficBytes
        let entries: [TrafficEntry]
        let isLimited: Bool
    }
}
