import Foundation

nonisolated enum ProxyHealthKind: String, Sendable {
    case checking, healthy, slow, partial, retrying, failed, unavailable, unknown, stale
    var title: String { NSLocalizedString("traffic.health.\(rawValue)", comment: "") }
}

nonisolated struct ProxyHealth: Sendable {
    var kind: ProxyHealthKind = .checking
    var checkedAt: Date?
    var latencyMS: Int?
    var outbounds: [String] = []

    func current(at date: Date = Date()) -> Self {
        guard let checkedAt, date.timeIntervalSince(checkedAt) > 25 else { return self }
        return Self(kind: .stale, checkedAt: checkedAt, outbounds: outbounds)
    }

    static func result(delays: [Int?], previousFailures: Int, at date: Date, outbounds: [String]) -> (report: Self, failures: Int) {
        guard !delays.isEmpty else { return (Self(kind: .unknown, checkedAt: date), 0) }
        let successful = delays.compactMap { $0 }
        let failures = successful.isEmpty ? min(previousFailures + 1, 2) : 0
        let kind: ProxyHealthKind
        if successful.isEmpty { kind = failures >= 2 ? .failed : .retrying }
        else if successful.count != delays.count { kind = .partial }
        else { kind = (successful.max() ?? 0) >= 1_500 ? .slow : .healthy }
        return (Self(kind: kind, checkedAt: date, latencyMS: successful.max(), outbounds: outbounds), failures)
    }
}
