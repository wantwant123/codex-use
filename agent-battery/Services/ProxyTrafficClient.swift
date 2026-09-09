import Foundation

actor ProxyTrafficClient {
    enum ClientError: Error, Equatable {
        case invalidAddress, unauthorized, unavailable, oversized, invalidResponse
    }

    private let session: URLSession
    private let request: URLRequest
    private var accumulator: TrafficAccumulator
    private let dailyCache: TrafficDailyCache?
    private let controller: String
    private var lastSaveTime: TimeInterval = 0
    private var activeOutbounds: [String] = []
    private var healthFailures = 0
    private var probedOutbounds: Set<String> = []
    static let maxResponseBytes = 4 * 1_024 * 1_024

    init(address: String, secret: String = "", configuration: URLSessionConfiguration = .ephemeral, dailyCache: TrafficDailyCache? = nil) throws {
        request = try Self.makeRequest(address: address, secret: secret)
        controller = request.url!.absoluteString
        self.dailyCache = dailyCache
        accumulator = TrafficAccumulator(restored: dailyCache?.load(controller: controller))
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 5
        configuration.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
        session = URLSession(configuration: configuration, delegate: LocalControllerDelegate(), delegateQueue: nil)
    }

    static func makeRequest(address: String, secret: String) throws -> URLRequest {
        guard var url = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http", ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              let port = url.port, (1...65535).contains(port) else { throw ClientError.invalidAddress }
        url.path = "/connections"
        guard let endpoint = url.url else { throw ClientError.invalidAddress }
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !secret.isEmpty { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        return request
    }

    func sample() async throws -> TrafficSnapshot {
        do {
            let data = try await read(request, limit: Self.maxResponseBytes)
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
        var probe = request
        var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        url.percentEncodedPath = "/proxies/" + name.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + "/delay"
        url.queryItems = [URLQueryItem(name: "url", value: "https://www.gstatic.com/generate_204"),
                          URLQueryItem(name: "timeout", value: "3000"), URLQueryItem(name: "expected", value: "204")]
        probe.url = url.url
        do {
            let value = try JSONDecoder().decode(Delay.self, from: await read(probe, limit: 4_096))
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

    private func read(_ request: URLRequest, limit: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard http.statusCode != 401 && http.statusCode != 403 else { throw ClientError.unauthorized }
        guard http.statusCode == 200 else { throw ClientError.unavailable }
        guard response.expectedContentLength <= Int64(limit) else { throw ClientError.oversized }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw ClientError.oversized }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

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
        session.invalidateAndCancel()
        dailyCache?.save(accumulator.current(at: Date()), controller: controller)
    }
}

nonisolated private final class LocalControllerDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    // A controller redirect must never forward its bearer credential to another endpoint.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
