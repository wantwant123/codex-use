import Foundation
import Testing
@testable import agent_battery

struct DailyTrafficHealthTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var date: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    @Test func dailyRolloverClearsTotalsRowsAndLiveBaseline() {
        let midnight = calendar.startOfDay(for: date).addingTimeInterval(86_400)
        var accumulator = TrafficAccumulator(calendar: calendar)
        _ = accumulator.ingest(sample(100), at: midnight.addingTimeInterval(-2), time: 0)
        let yesterday = accumulator.ingest(sample(150), at: midnight.addingTimeInterval(-1), time: 1)
        #expect(yesterday.total.upload == 50)
        let today = accumulator.ingest(sample(175), at: midnight, time: 2)
        #expect(today.dayStart == midnight)
        #expect(today.total.total == 0)
        #expect(today.entries.isEmpty)
        #expect(today.history.isEmpty)
        #expect(today.speed == nil)
        let later = accumulator.ingest(sample(200), at: midnight.addingTimeInterval(1), time: 3)
        #expect(later.total.upload == 25)
        #expect(later.rows(domains: false, route: .all).first?.bytes.upload == 25)
    }

    @Test func calendarRolloverHandlesDaylightSavingTime() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try #require(local.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let nextDay = try #require(local.date(byAdding: .day, value: 1, to: start))
        #expect(nextDay.timeIntervalSince(start) == 23 * 3600)
        var accumulator = TrafficAccumulator(calendar: local)
        _ = accumulator.ingest(sample(100), at: nextDay.addingTimeInterval(-2), time: 0)
        _ = accumulator.ingest(sample(200), at: nextDay.addingTimeInterval(-1), time: 1)
        #expect(accumulator.current(at: nextDay).total.total == 0)
    }

    @Test func dailyCheckpointRestoresTotalsWithoutRecountingOldConnections() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = TrafficDailyCache(url: folder.appendingPathComponent("today.json"))
        var original = TrafficAccumulator(calendar: calendar)
        _ = original.ingest(sample(100), at: date, time: 0)
        let snapshot = original.ingest(sample(120), at: date.addingTimeInterval(1), time: 1)
        cache.save(snapshot, controller: "local-a", now: date.addingTimeInterval(1), calendar: calendar)
        let restored = try #require(cache.load(controller: "local-a", now: date.addingTimeInterval(5), calendar: calendar))
        #expect(restored.total.upload == 20)
        #expect(restored.entries.first?.bytes.upload == 20)
        #expect(restored.entries.first?.speed.total == 0)
        #expect(restored.history.isEmpty)
        var restarted = TrafficAccumulator(calendar: calendar, restored: restored)
        #expect(restarted.ingest(sample(500), at: date.addingTimeInterval(6), time: 6).total.upload == 20)
        #expect(restarted.ingest(sample(510), at: date.addingTimeInterval(7), time: 7).total.upload == 30)
        #expect(cache.load(controller: "local-b", now: date.addingTimeInterval(8), calendar: calendar) == nil)
        #expect(cache.load(controller: "local-a", now: date.addingTimeInterval(86_400), calendar: calendar) == nil)
    }

    @Test func oldCheckpointCannotOverwriteNewerDailyTotals() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = TrafficDailyCache(url: folder.appendingPathComponent("today.json"))
        var accumulator = TrafficAccumulator(calendar: calendar)
        _ = accumulator.ingest(sample(100), at: date, time: 0)
        let old = accumulator.ingest(sample(120), at: date.addingTimeInterval(1), time: 1)
        let new = accumulator.ingest(sample(150), at: date.addingTimeInterval(2), time: 2)
        cache.save(new, controller: "local", now: date.addingTimeInterval(3), calendar: calendar)
        cache.save(old, controller: "local", now: date.addingTimeInterval(3), calendar: calendar)
        #expect(cache.load(controller: "local", now: date.addingTimeInterval(3), calendar: calendar)?.total.upload == 50)
    }

    @Test func corruptOrOversizedCheckpointIsRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("today.json")
        let cache = TrafficDailyCache(url: url)
        for data in [Data("not json".utf8), Data(count: TrafficDailyCache.maxBytes + 1)] {
            try data.write(to: url)
            #expect(cache.load(controller: "local", now: date, calendar: calendar) == nil)
            #expect(cache.hasError)
        }
    }

    @Test func healthRequiresRepeatedFailureAndExpires() {
        #expect(ProxyHealth.result(delays: [100, 500], previousFailures: 0, at: date, outbounds: []).report.kind == .healthy)
        #expect(ProxyHealth.result(delays: [1_500], previousFailures: 0, at: date, outbounds: []).report.kind == .slow)
        #expect(ProxyHealth.result(delays: [100, nil], previousFailures: 0, at: date, outbounds: []).report.kind == .partial)
        let first = ProxyHealth.result(delays: [nil], previousFailures: 0, at: date, outbounds: ["node"])
        #expect(first.report.kind == .retrying)
        let second = ProxyHealth.result(delays: [nil], previousFailures: first.failures, at: date, outbounds: ["node"])
        #expect(second.report.kind == .failed)
        let recovered = ProxyHealth.result(delays: [100], previousFailures: second.failures, at: date, outbounds: ["node"])
        #expect(recovered.failures == 0)
        #expect(recovered.report.current(at: date.addingTimeInterval(26)).kind == .stale)
        #expect(ProxyHealth.result(delays: [], previousFailures: 2, at: date, outbounds: []).report.kind == .unknown)
    }

    @Test func healthTestsOnlyBoundedActualProxyOutbounds() {
        let connections = (0..<10).map { index in connection(upload: Int64(index), chains: ["node-\(index)"]) }
            + [connection(upload: 99_999, chains: ["DIRECT"])]
        let names = ProxyTrafficClient.outbounds(in: ProxyConnections(uploadTotal: 1_000_000, downloadTotal: 0, connections: connections))
        #expect(names == ["node-9", "node-8", "node-7"])
    }

    @Test func healthRequestUsesNodeDelayEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthFixtureProtocol.self]
        let client = try ProxyTrafficClient(address: "http://127.0.0.1:19100", secret: "fixture", configuration: configuration)
        _ = try await client.sample()
        let report = await client.checkHealth()
        #expect(report.kind == .healthy)
        #expect(report.latencyMS == 100)
        #expect(report.outbounds == ["node / test"])
        await client.close()
    }

    @Test func cancellingHealthProbeReturnsPromptly() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthFixtureProtocol.self]
        let client = try ProxyTrafficClient(address: "http://127.0.0.1:19101", secret: "fixture", configuration: configuration)
        _ = try await client.sample()
        let start = Date()
        let task = Task { await client.checkHealth() }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let report = await task.value
        #expect(report.kind == .checking)
        #expect(Date().timeIntervalSince(start) < 2)
        await client.close()
    }

    @Test @MainActor func disabledMonitorDoesNotStayAliveThroughItsTimer() throws {
        let suite = "traffic-lifetime-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.trafficEnabled = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var store: ProxyTrafficStore? = ProxyTrafficStore(settings: settings, dailyCache: TrafficDailyCache(url: folder.appendingPathComponent("today.json")))
        weak var reference = store
        store = nil
        #expect(reference == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    private func sample(_ upload: Int64) -> ProxyConnections {
        ProxyConnections(uploadTotal: upload, downloadTotal: upload * 2, connections: [connection(upload: upload, chains: ["node"])])
    }
    private func connection(upload: Int64, chains: [String]) -> ProxyConnection {
        ProxyConnection(id: chains.joined(), metadata: .init(host: "example.com", destinationIP: nil, process: "app", processPath: nil),
                        upload: upload, download: upload * 2, start: "2026-01-01T00:00:00Z", chains: chains)
    }
}

private final class HealthFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        #expect(url.host == "127.0.0.1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        if url.port == 19101 && url.path != "/connections" { return }
        let data: Data
        if url.path == "/connections" {
            data = Data(#"{"uploadTotal":10,"downloadTotal":20,"connections":[{"id":"a","upload":10,"download":20,"chains":["node / test"],"metadata":{}}]}"#.utf8)
        } else {
            #expect(url.absoluteString.contains("node%20%2F%20test/delay"))
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.contains(URLQueryItem(name: "url", value: "https://www.gstatic.com/generate_204")) == true)
            data = Data(#"{"delay":100}"#.utf8)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
