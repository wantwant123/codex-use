import Combine
import Foundation

final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [UsageTool: UsageSnapshot]
    @Published private(set) var histories: [UsageTool: [UsageHistoryEntry]]
    @Published private(set) var lastRefreshAt: Date?

    private let settings: AppSettings
    private let codexProvider = CodexUsageProvider()
    private let snapshotCache: UsageSnapshotCache
    private let historyStore: UsageHistoryStore
    private let refreshQueue = DispatchQueue(label: "agent-battery.usage-store.refresh", qos: .userInitiated)
    private var refreshTimer: Timer?
    private var didPerformLaunchRefresh = false
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: AppSettings,
        snapshotCache: UsageSnapshotCache = UsageSnapshotCache(),
        historyStore: UsageHistoryStore = UsageHistoryStore()
    ) {
        self.settings = settings
        self.snapshotCache = snapshotCache
        self.historyStore = historyStore
        snapshots = Self.initialSnapshots(from: snapshotCache)
        histories = Self.initialHistories(from: historyStore)

        settings.objectWillChange
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleRefreshTimer()
                self?.refresh()
            }
            .store(in: &cancellables)

        scheduleRefreshTimer()
        refreshOnLaunch()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    var enabledTools: [UsageTool] {
        UsageTool.allCases
    }

    var primarySnapshot: UsageSnapshot {
        snapshot(for: .codex)
    }

    func snapshot(for tool: UsageTool) -> UsageSnapshot {
        snapshots[tool] ?? UsageSnapshot.unavailable(tool: tool, message: String(localized: "store.waitingFirstRefresh"))
    }

    func history(for tool: UsageTool) -> [UsageHistoryEntry] {
        histories[tool] ?? []
    }

    func level(for snapshot: UsageSnapshot) -> UsageLevel {
        UsageMath.level(
            for: snapshot.fiveHourRemainingPercent,
            warningThreshold: settings.warningThreshold,
            criticalThreshold: settings.criticalThreshold
        )
    }

    func refresh() {
        let configuration = settings.dataConfiguration

        refreshQueue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let codexRaw = self.codexProvider.fetch(configuration: configuration)

            DispatchQueue.main.async {
                var nextSnapshots = self.snapshots
                var nextHistories = self.histories
                let codexSnapshot = self.resolvedSnapshot(codexRaw, now: now)
                nextSnapshots[.codex] = codexSnapshot
                nextHistories[.codex] = self.historyStore.record(codexSnapshot, at: now)
                self.histories = nextHistories
                self.snapshots = nextSnapshots
                self.lastRefreshAt = now
            }
        }
    }

    func refreshOnLaunch() {
        guard !didPerformLaunchRefresh else {
            return
        }

        didPerformLaunchRefresh = true
        refresh()
        scheduleCodexLaunchRefresh()
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.refreshInterval.rawValue), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func scheduleCodexLaunchRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }

    private func resolvedSnapshot(_ newSnapshot: UsageSnapshot, now: Date) -> UsageSnapshot {
        let projectedSnapshot = newSnapshot.projectingElapsedResets(now: now)
        if projectedSnapshot.hasUsageValues {
            snapshotCache.store(projectedSnapshot, now: now)
            return projectedSnapshot
        }

        if let cachedSnapshot = snapshotCache.snapshot(for: projectedSnapshot.tool, now: now) {
            snapshotCache.store(cachedSnapshot, now: now)
            return cachedSnapshot.replacingStatus(
                .stale,
                message: fallbackMessage(from: projectedSnapshot)
            )
        }

        return snapshotPreservingPreviousValues(projectedSnapshot, now: now)
    }

    private func snapshotPreservingPreviousValues(
        _ newSnapshot: UsageSnapshot,
        now: Date
    ) -> UsageSnapshot {
        guard
            let previous = snapshots[newSnapshot.tool],
            previous.hasUsageValues
        else {
            return newSnapshot
        }

        return previous
            .projectingElapsedResets(now: now)
            .replacingStatus(
                .stale,
                message: fallbackMessage(from: newSnapshot)
            )
    }

    private func fallbackMessage(from sourceSnapshot: UsageSnapshot) -> String {
        if let message = sourceSnapshot.message, !message.isEmpty {
            return String(format: NSLocalizedString("store.usingCachedDataWith", comment: ""), message)
        }

        return String(localized: "store.usingCachedData")
    }

    private static func initialSnapshots(from snapshotCache: UsageSnapshotCache) -> [UsageTool: UsageSnapshot] {
        Dictionary(
            uniqueKeysWithValues: UsageTool.allCases.map { tool in
                let snapshot = snapshotCache.snapshot(for: tool)?
                    .replacingStatus(.stale, message: String(localized: "store.usingCachedData"))
                    ?? UsageSnapshot.unavailable(tool: tool, message: String(localized: "store.waitingFirstRefresh"))
                return (tool, snapshot)
            }
        )
    }

    private static func initialHistories(from historyStore: UsageHistoryStore) -> [UsageTool: [UsageHistoryEntry]] {
        Dictionary(
            uniqueKeysWithValues: UsageTool.allCases.map { tool in
                (tool, historyStore.history(for: tool))
            }
        )
    }
}
