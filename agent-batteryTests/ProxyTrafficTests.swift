import Foundation
import Testing
@testable import agent_battery

struct ProxyTrafficTests {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func baselinesExistingTrafficAndUsesElapsedSeconds() {
        var accumulator = TrafficAccumulator()
        let first = accumulator.ingest(sample(10_000, [connection("a", 8_000)]), at: epoch, time: 10)
        #expect(first.total.total == 0)
        #expect(first.speed == nil)
        let next = accumulator.ingest(sample(10_600, [connection("a", 8_400)]), at: epoch.addingTimeInterval(2), time: 12)
        #expect(next.total.upload == 600)
        #expect(next.speed?.upload == 300)
        #expect(next.entries.first?.bytes.upload == 400)
        #expect(next.unassigned.upload == 200)
    }

    @Test func countsNewConnectionsOnceAndGroupsHelperIntoApplication() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.ingest(sample(0, []), at: epoch, time: 0)
        let c = connection("a", 80, start: epoch.addingTimeInterval(0.5))
        let next = accumulator.ingest(sample(80, [c, c]), at: epoch.addingTimeInterval(1), time: 1)
        #expect(next.entries.count == 1)
        #expect(next.entries.first?.bytes.upload == 80)
        #expect(next.entries.first?.key.app == "/Applications/Browser.app")
        #expect(next.entries.first?.key.domain == "example.com")
        let same = accumulator.ingest(sample(80, [c]), at: epoch.addingTimeInterval(2), time: 2)
        #expect(same.entries.first?.bytes.upload == 80)
        #expect(same.speed?.upload == 0)
    }

    @Test func disappearingConnectionDoesNotDuplicateOnReappearance() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.ingest(sample(0, []), at: epoch, time: 0)
        _ = accumulator.ingest(sample(80, [connection("a", 80, start: epoch.addingTimeInterval(0.2))]), at: epoch.addingTimeInterval(1), time: 1)
        _ = accumulator.ingest(sample(100, []), at: epoch.addingTimeInterval(2), time: 2)
        let result = accumulator.ingest(sample(120, [connection("a", 120, start: epoch.addingTimeInterval(0.2))]), at: epoch.addingTimeInterval(3), time: 3)
        #expect(result.total.upload == 120)
        #expect(result.entries.first?.bytes.upload == 80)
        #expect(result.unassigned.upload == 40)
    }

    @Test func restartAndOfflineGapDoNotInventTrafficOrSpeed() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.ingest(sample(500, []), at: epoch, time: 0)
        _ = accumulator.ingest(sample(600, []), at: epoch.addingTimeInterval(1), time: 1)
        let reset = accumulator.ingest(sample(10, []), at: epoch.addingTimeInterval(2), time: 2)
        #expect(reset.total.upload == 100)
        #expect(reset.speed == nil)
        #expect(reset.hasGaps)
        accumulator.interrupt()
        let recovered = accumulator.ingest(sample(10_000, []), at: epoch.addingTimeInterval(3), time: 3)
        #expect(recovered.total.upload == 100)
        #expect(recovered.speed == nil)
        let resumed = accumulator.ingest(sample(10_010, []), at: epoch.addingTimeInterval(4), time: 4)
        #expect(resumed.total.upload == 110)
        #expect(resumed.history.first?.segment != resumed.history.last?.segment)
        let wake = accumulator.ingest(sample(20_000, []), at: epoch.addingTimeInterval(100), time: 100)
        #expect(wake.total.upload == 110)
        #expect(wake.speed == nil)
    }

    @Test func sleepGapIsDetectedWhenUptimeClockPauses() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.ingest(sample(100, []), at: epoch, time: 0)
        let wake = accumulator.ingest(sample(1_000, []), at: epoch.addingTimeInterval(3_600), time: 1)
        #expect(wake.speed == nil)
        #expect(wake.hasGaps)
        #expect(wake.total.total == 0)
    }

    @Test func routesAndApplicationDrilldownPreserveTotals() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.ingest(sample(0, []), at: epoch, time: 0)
        let proxy = connection("p", 100, start: epoch.addingTimeInterval(0.2))
        let direct = connection("d", 50, start: epoch.addingTimeInterval(0.2), chains: ["DIRECT"])
        let unknown = connection("u", 20, start: epoch.addingTimeInterval(0.2), chains: [])
        let next = accumulator.ingest(sample(170, [proxy, direct, unknown]), at: epoch.addingTimeInterval(1), time: 1)
        #expect(next.rows(domains: false, route: .all).first?.bytes.upload == 170)
        #expect(next.rows(domains: true, route: .proxy).first?.bytes.upload == 100)
        #expect(next.rows(domains: true, route: .direct).first?.bytes.upload == 50)
        #expect(next.rows(domains: true, route: .unknown).first?.bytes.upload == 20)
        #expect(next.rows(domains: true, route: .all, app: "/Applications/Browser.app").first?.bytes.upload == 170)
        #expect(next.rows(domains: true, route: .all, app: "missing").isEmpty)
        #expect(next.rows(domains: false, route: .all).first?.routes == [.proxy, .direct, .unknown])
        #expect(next.rows(domains: true, route: .proxy).first?.routes == [.proxy])
        #expect(next.rows(domains: true, route: .direct).first?.routes == [.direct])
        #expect(next.rows(domains: true, route: .unknown).first?.routes == [.unknown])
        #expect(next.rows(domains: true, route: .all, app: "/Applications/Browser.app").first?.routes == [.proxy, .direct, .unknown])
    }

    @Test func boundedHistoryAndOverflowRetainByteTotals() {
        var accumulator = TrafficAccumulator(entryLimit: 2, historyLimit: 3)
        _ = accumulator.ingest(sample(0, []), at: epoch, time: 0)
        var result = TrafficSnapshot()
        for tick in 1...100 {
            let c = connection("\(tick)", 10, start: epoch.addingTimeInterval(Double(tick) - 0.5), domain: "\(tick).example.com")
            result = accumulator.ingest(sample(Int64(tick * 10), [c]), at: epoch.addingTimeInterval(Double(tick)), time: Double(tick))
        }
        #expect(result.entries.count == 3)
        #expect(result.entries.reduce(0) { $0 + $1.bytes.upload } == 1_000)
        #expect(result.history.count == 3)
        #expect(result.isLimited)
        #expect(result.unassigned.upload == 0)
    }

    @Test func malformedNegativeAndOversizedResponsesAreRejected() throws {
        let empty = try ProxyTrafficClient.decode(Data(#"{"uploadTotal":0,"downloadTotal":0,"connections":null}"#.utf8))
        #expect(empty.connections == nil)
        #expect(throws: (any Error).self) {
            try ProxyTrafficClient.decode(Data(#"{"uploadTotal":-1,"downloadTotal":0}"#.utf8))
        }
        #expect(throws: (any Error).self) { try ProxyTrafficClient.decode(Data("{}".utf8)) }
        #expect(throws: (any Error).self) { try ProxyTrafficClient.decode(Data(count: ProxyTrafficClient.maxResponseBytes + 1)) }
    }

    @Test func readsClashSocketAndBoundsResponses() async throws {
        let fixture = try await ClashSocketFixture { target in
            switch target {
            case "/connections": ClashSocketFixture.response(#"{"uploadTotal":200,"downloadTotal":400,"connections":[]}"#)
            case "/oversized": ClashSocketFixture.response(String(repeating: "x", count: 100))
            default: ClashSocketFixture.response("", status: 503)
            }
        }
        let api = ClashVergeAPI(socketPaths: ["/missing", fixture.path])
        let client = ProxyTrafficClient(api: api)
        let snapshot = try await client.sample()
        #expect(snapshot.total.total == 0)
        await #expect(throws: ProxyTrafficClient.ClientError.oversized) { try await api.read("/oversized", limit: 10) }
        await #expect(throws: ProxyTrafficClient.ClientError.unavailable) { try await api.read("/missing", limit: 10) }
        await client.close()
        withExtendedLifetime(fixture) {}
    }

    @Test func cancellingBlockedRequestReturnsPromptly() async throws {
        let fixture = try await ClashSocketFixture { _ in nil }
        defer { withExtendedLifetime(fixture) {} }
        let client = ProxyTrafficClient(api: ClashVergeAPI(socketPaths: [fixture.path]))
        let start = Date()
        let task = Task { try await client.sample() }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled request unexpectedly succeeded")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        #expect(Date().timeIntervalSince(start) < 2)
        await client.close()
    }

    private func sample(_ upload: Int64, _ connections: [ProxyConnection]) -> ProxyConnections {
        ProxyConnections(uploadTotal: upload, downloadTotal: upload * 2, connections: connections)
    }

    private func connection(_ id: String, _ upload: Int64, start: Date? = nil, chains: [String] = ["Node", "Group"], domain: String = "EXAMPLE.COM.") -> ProxyConnection {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ProxyConnection(id: id,
            metadata: .init(host: domain, destinationIP: "1.2.3.4", process: "Helper", processPath: "/Applications/Browser.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper"),
            upload: upload, download: upload * 2, start: format.string(from: start ?? epoch.addingTimeInterval(-10)), chains: chains)
    }
}
