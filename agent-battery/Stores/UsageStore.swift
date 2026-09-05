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
    private var isRefreshing = false
    private var refreshPending = false
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
            for: snapshot.menuBarRemainingPercent,
            warningThreshold: settings.warningThreshold,
            criticalThreshold: settings.criticalThreshold
        )
    }

    func refresh() {
        // All callers and completion handlers run on the main thread.
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        let configuration = settings.dataConfiguration

        refreshQueue.async { [weak self] in
            guard let self else { return }
            let codexRaw = autoreleasepool {
                self.codexProvider.fetch(configuration: configuration)
            }
            let now = Date()

            DispatchQueue.main.async {
                var nextSnapshots = self.snapshots
                var nextHistories = self.histories
                let codexSnapshot = self.resolvedSnapshot(codexRaw, now: now)
                nextSnapshots[.codex] = codexSnapshot
                nextHistories[.codex] = self.historyStore.record(codexSnapshot, at: now)
                self.histories = nextHistories
                self.snapshots = nextSnapshots
                self.lastRefreshAt = now
                self.isRefreshing = false
                if self.refreshPending {
                    self.refreshPending = false
                    self.refresh()
                }
            }
        }
    }

    func refreshOnLaunch() {
        guard !didPerformLaunchRefresh else {
            return
        }

        didPerformLaunchRefresh = true
        refresh()
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.refreshInterval.rawValue), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func resolvedSnapshot(_ newSnapshot: UsageSnapshot, now: Date) -> UsageSnapshot {
        let projectedSnapshot = newSnapshot.markingElapsedResetsStale(now: now)
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
            .markingElapsedResetsStale(now: now)
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
