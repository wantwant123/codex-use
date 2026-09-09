import AppKit
import Combine
import Foundation

@MainActor
final class ProxyTrafficStore: ObservableObject {
    @Published private(set) var snapshot = TrafficSnapshot()
    @Published private(set) var statusKey = "traffic.connecting"
    @Published private(set) var isLive = false
    @Published private(set) var health = ProxyHealth()
    @Published private(set) var storageFailed = false
    private var task: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var rolloverTimer: Timer?
    private var termination: AnyCancellable?
    private let dailyCache: TrafficDailyCache
    private var activeController = ""
    private var subscription: AnyCancellable?
    private let settings: AppSettings

    init(settings: AppSettings, dailyCache: TrafficDailyCache = TrafficDailyCache()) {
        self.dailyCache = dailyCache
        self.settings = settings
        subscription = Publishers.CombineLatest(settings.$trafficEnabled, settings.$proxyControllerAddress)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restart() }
        termination = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.persistCurrent() }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let day = self.snapshot.dayStart,
                      day != Calendar.autoupdatingCurrent.startOfDay(for: Date()) else { return }
                self.restart()
            }
        }
        rolloverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        restart()
    }

    deinit {
        task?.cancel()
        healthTask?.cancel()
        rolloverTimer?.invalidate()
    }

    func restart() {
        persistCurrent()
        let previousTask = task
        previousTask?.cancel()
        healthTask?.cancel()
        health = ProxyHealth()
        isLive = false
        if snapshot.dayStart != Calendar.autoupdatingCurrent.startOfDay(for: Date()) {
            snapshot = TrafficSnapshot(dayStart: Calendar.autoupdatingCurrent.startOfDay(for: Date()))
        }
        guard settings.trafficEnabled else {
            statusKey = "traffic.disabled"
            return
        }
        let address = settings.proxyControllerAddress
        let secret = ProxyControllerSecret.read()
        guard let controller = try? ProxyTrafficClient.makeRequest(address: address, secret: "").url?.absoluteString else {
            statusKey = "traffic.invalidAddress"
            return
        }
        if controller != activeController {
            snapshot = TrafficSnapshot(dayStart: Calendar.autoupdatingCurrent.startOfDay(for: Date()))
        }
        statusKey = "traffic.connecting"
        let cache = dailyCache
        task = Task { [weak self] in
            // Finish the prior client's checkpoint before loading the next one.
            await previousTask?.value
            guard !Task.isCancelled else { return }
            let client: ProxyTrafficClient
            do { client = try ProxyTrafficClient(address: address, secret: secret, dailyCache: cache) }
            catch { self?.statusKey = "traffic.invalidAddress"; return }
            let restored = await client.currentSnapshot()
            guard !Task.isCancelled else { await client.close(); return }
            self?.activeController = controller
            self?.snapshot = restored
            self?.storageFailed = cache.hasError
            self?.startHealthChecks(client: client)
            var failures = 0
            while !Task.isCancelled {
                let tick = ProcessInfo.processInfo.systemUptime
                do {
                    let snapshot = try await client.sample()
                    guard !Task.isCancelled else { break }
                    self?.snapshot = snapshot
                    self?.storageFailed = self?.dailyCache.hasError ?? false
                    self?.isLive = true
                    self?.statusKey = snapshot.speed == nil ? "traffic.baseline" : "traffic.live"
                    failures = 0
                } catch {
                    guard !Task.isCancelled else { break }
                    let current = await client.currentSnapshot()
                    guard !Task.isCancelled else { break }
                    self?.snapshot = current
                    self?.isLive = false
                    self?.statusKey = Self.message(for: error)
                    failures = min(failures + 1, 5)
                }
                let interval = failures == 0 ? 1.0 : min(30.0, pow(2.0, Double(failures)))
                let delay = max(0.05, interval - (ProcessInfo.processInfo.systemUptime - tick))
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
            }
            await client.close()
        }
    }

    private func startHealthChecks(client: ProxyTrafficClient) {
        healthTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            while !Task.isCancelled {
                let start = ProcessInfo.processInfo.systemUptime
                let report = await client.checkHealth()
                guard !Task.isCancelled else { return }
                self?.health = report
                let delay = max(1, 10 - (ProcessInfo.processInfo.systemUptime - start))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    var currentHealth: ProxyHealth {
        guard settings.trafficEnabled else { return ProxyHealth(kind: .unknown) }
        if !isLive {
            return ProxyHealth(kind: statusKey == "traffic.connecting" ? .checking : .unavailable)
        }
        return health.current()
    }

    private func persistCurrent() {
        guard !activeController.isEmpty else { return }
        dailyCache.save(snapshot, controller: activeController)
        storageFailed = dailyCache.hasError
    }

    var speed: TrafficBytes? { isLive ? snapshot.speed : nil }

    private static func message(for error: Error) -> String {
        switch error {
        case ProxyTrafficClient.ClientError.unauthorized: "traffic.unauthorized"
        case ProxyTrafficClient.ClientError.oversized: "traffic.oversized"
        case ProxyTrafficClient.ClientError.invalidResponse, is DecodingError: "traffic.invalidResponse"
        default: "traffic.disconnected"
        }
    }
}
