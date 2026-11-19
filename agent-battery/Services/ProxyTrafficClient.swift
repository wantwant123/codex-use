import Foundation

actor ProxyTrafficClient {
    enum ClientError: Error, Equatable {
        case unavailable, oversized, invalidResponse
    }

    private let api: ClashVergeAPI
    private var accumulator: TrafficAccumulator
    private let dailyCache: TrafficDailyCache?
    private let controller = ClashVergeAPI.controller
    private var lastSaveTime: TimeInterval = 0
    private var activeOutbounds: [String] = []
    private var healthFailures = 0
    private var probedOutbounds: Set<String> = []
    static let maxResponseBytes = 4 * 1_024 * 1_024

    init(api: ClashVergeAPI = ClashVergeAPI(), dailyCache: TrafficDailyCache? = nil) {
        self.api = api
        self.dailyCache = dailyCache
        accumulator = TrafficAccumulator(restored: dailyCache?.load(controller: controller))
    }

    func sample() async throws -> TrafficSnapshot {
        do {
            let data = try await api.read("/connections", limit: Self.maxResponseBytes)
            return try autoreleasepool {
                let sample = try Self.decode(data)
                let now = Date()
                let time = ProcessInfo.processInfo.systemUptime
                activeOutbounds = Self.outbounds(in: sample)
                let snapshot = accumulator.ingest(sample, at: now, time: time)
                if time - lastSaveTime >= 30 {
                    dailyCache?.save(snapshot, controller: controller, now: now)
                    lastSaveTime = time
                }
                return snapshot
            }
        } catch {
            activeOutbounds = []
            healthFailures = 0
            probedOutbounds = []
            accumulator.interrupt()
            throw error
        }
    }

    func currentSnapshot() -> TrafficSnapshot { accumulator.current(at: Date()) }

    func checkHealth() async -> ProxyHealth {
        let names = activeOutbounds
        let delays = await withTaskGroup(of: Int?.self, returning: [Int?].self) { group in
            for name in names { group.addTask { await self.probeDelay(for: name) } }
            var results: [Int?] = []
            for await delay in group { results.append(delay) }
            return results
        }
        guard !Task.isCancelled, Set(names) == Set(activeOutbounds) else { return ProxyHealth() }
        if Set(names) != probedOutbounds { healthFailures = 0 }
        probedOutbounds = Set(names)
        let result = ProxyHealth.result(delays: delays, previousFailures: healthFailures, at: Date(), outbounds: names)
        healthFailures = result.failures
        return result.report
    }

    private func probeDelay(for name: String) async -> Int? {
        guard !Task.isCancelled else { return nil }
        var url = URLComponents()
        url.percentEncodedPath = "/proxies/" + name.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + "/delay"
        url.queryItems = [URLQueryItem(name: "url", value: "https://www.gstatic.com/generate_204"),
                          URLQueryItem(name: "timeout", value: "3000"), URLQueryItem(name: "expected", value: "204")]
        guard let path = url.string else { return nil }
        do {
            let value = try JSONDecoder().decode(Delay.self, from: await api.read(path, limit: 4_096))
            return value.delay > 0 && value.delay <= 30_000 ? value.delay : nil
        } catch { return nil }
    }

    static func outbounds(in sample: ProxyConnections) -> [String] {
        var totals: [String: Double] = [:]
        for connection in sample.connections ?? [] where connection.route == .proxy {
            guard let name = connection.chains?.first, name.utf8.count <= 512 else { continue }
            totals[name, default: 0] += Double(connection.upload) + Double(connection.download)
        }
        return totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(3).map(\.key)
    }

    private struct Delay: Decodable { let delay: Int }

    static func decode(_ data: Data) throws -> ProxyConnections {
        guard data.count <= maxResponseBytes else { throw ClientError.oversized }
        let sample = try JSONDecoder().decode(ProxyConnections.self, from: data)
        guard sample.uploadTotal >= 0, sample.downloadTotal >= 0,
              (sample.connections ?? []).allSatisfy({ $0.upload >= 0 && $0.download >= 0 }) else {
            throw ClientError.invalidResponse
        }
        return sample
    }

    func close() {
        dailyCache?.save(accumulator.current(at: Date()), controller: controller)
    }
}
