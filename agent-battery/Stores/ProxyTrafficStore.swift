import Combine
import Foundation

@MainActor
final class ProxyTrafficStore: ObservableObject {
    @Published private(set) var snapshot = TrafficSnapshot()
    @Published private(set) var statusKey = "traffic.connecting"
    @Published private(set) var isLive = false
    private var task: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        subscription = Publishers.CombineLatest(settings.$trafficEnabled, settings.$proxyControllerAddress)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restart() }
        restart()
    }

    deinit { task?.cancel() }

    func restart() {
        task?.cancel()
        snapshot = TrafficSnapshot()
        isLive = false
        guard settings.trafficEnabled else {
            statusKey = "traffic.disabled"
            return
        }
        let client: ProxyTrafficClient
        do {
            client = try ProxyTrafficClient(address: settings.proxyControllerAddress, secret: ProxyControllerSecret.read())
        } catch {
            statusKey = "traffic.invalidAddress"
            return
        }
        statusKey = "traffic.connecting"
        task = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                let tick = ProcessInfo.processInfo.systemUptime
                do {
                    let snapshot = try await client.sample()
                    guard !Task.isCancelled else { break }
                    self?.snapshot = snapshot
                    self?.isLive = true
                    self?.statusKey = snapshot.speed == nil ? "traffic.baseline" : "traffic.live"
                    failures = 0
                } catch {
                    guard !Task.isCancelled else { break }
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
