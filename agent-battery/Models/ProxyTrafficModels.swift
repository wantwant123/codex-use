import Foundation

nonisolated struct ProxyConnections: Decodable, Sendable {
    let uploadTotal: Int64
    let downloadTotal: Int64
    let connections: [ProxyConnection]?
}

nonisolated struct ProxyConnection: Decodable, Sendable {
    let id: String
    let metadata: Metadata
    let upload: Int64
    let download: Int64
    let start: String?
    let chains: [String]?

    struct Metadata: Decodable, Sendable {
        let host: String?
        let destinationIP: String?
        let process: String?
        let processPath: String?
    }

    var route: TrafficRoute {
        guard let chains, !chains.isEmpty else { return .unknown }
        if chains.contains("DIRECT") { return .direct }
        if chains.contains(where: { $0.hasPrefix("REJECT") }) { return .unknown }
        return .proxy
    }

    var app: String {
        let path = metadata.processPath ?? ""
        // Helpers inside an application belong to the outer application bundle.
        if let range = path.range(of: ".app/") {
            return String(path[..<range.lowerBound]) + ".app"
        }
        return path.isEmpty ? (metadata.process ?? "") : path
    }

    var domain: String {
        let host = (metadata.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host.isEmpty ? (metadata.destinationIP ?? "") : host
    }
}

nonisolated enum TrafficRoute: String, CaseIterable, Identifiable, Sendable, Codable {
    case all, proxy, direct, unknown
    var id: String { rawValue }
    var title: String { NSLocalizedString("traffic.route.\(rawValue)", comment: "") }
}

nonisolated struct TrafficBytes: Equatable, Sendable, Codable {
    var upload: Double = 0
    var download: Double = 0
    var total: Double { upload + download }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(upload: lhs.upload + rhs.upload, download: lhs.download + rhs.download)
    }

    func perSecond(_ seconds: Double) -> Self {
        Self(upload: upload / seconds, download: download / seconds)
    }
}

nonisolated struct TrafficKey: Hashable, Sendable, Codable {
    let app: String
    let domain: String
    let route: TrafficRoute
    static let overflow = "__traffic_overflow__"
}

nonisolated struct TrafficEntry: Sendable, Codable {
    let key: TrafficKey
    var bytes = TrafficBytes()
    var speed = TrafficBytes()
}

nonisolated struct TrafficPoint: Identifiable, Sendable {
    let date: Date
    let speed: TrafficBytes
    let segment: Int
    var id: Date { date }
}

nonisolated struct TrafficRow: Identifiable {
    let id: String
    let title: String
    var bytes = TrafficBytes()
    var speed = TrafficBytes()
    var routes: Set<TrafficRoute> = []

    var routeTitle: String {
        let observed = [TrafficRoute.proxy, .direct, .unknown].filter { routes.contains($0) }
        return observed.isEmpty ? TrafficRoute.unknown.title : observed.map(\.title).joined(separator: " + ")
    }
}

nonisolated struct TrafficSnapshot: Sendable {
    var dayStart: Date?
    var startedAt: Date?
    var updatedAt: Date?
    var total = TrafficBytes()
    var speed: TrafficBytes?
    var entries: [TrafficEntry] = []
    var history: [TrafficPoint] = []
    var hasGaps = false
    var isLimited = false

    var unassigned: TrafficBytes {
        let assigned = entries.reduce(TrafficBytes()) { $0 + $1.bytes }
        return TrafficBytes(upload: max(0, total.upload - assigned.upload), download: max(0, total.download - assigned.download))
    }

    func rows(domains: Bool, route: TrafficRoute, app: String? = nil) -> [TrafficRow] {
        var result: [String: TrafficRow] = [:]
        for entry in entries where (route == .all || entry.key.route == route) && (app == nil || app == entry.key.app) {
            let id = domains ? entry.key.domain : entry.key.app
            let title: String
            if id == TrafficKey.overflow {
                title = NSLocalizedString("traffic.other", comment: "")
            } else if id.isEmpty {
                title = NSLocalizedString(domains ? "traffic.unknownDomain" : "traffic.unknownApp", comment: "")
            } else {
                title = domains ? id : URL(fileURLWithPath: id).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            }
            var row = result[id] ?? TrafficRow(id: id, title: title)
            row.bytes = row.bytes + entry.bytes
            row.speed = row.speed + entry.speed
            row.routes.insert(entry.key.route)
            result[id] = row
        }
        return result.values.sorted { $0.bytes.total == $1.bytes.total ? $0.id < $1.id : $0.bytes.total > $1.bytes.total }
    }
}

nonisolated enum TrafficFormat {
    static func bytes(_ value: Double) -> String {
        let value = max(0, value)
        if value < 1_000 { return String(format: "%.0f B", value) }
        if value < 1_000_000 { return String(format: "%.1f KB", value / 1_000) }
        if value < 1_000_000_000 { return String(format: "%.2f MB", value / 1_000_000) }
        return String(format: "%.2f GB", value / 1_000_000_000)
    }

    static func speed(_ value: Double?) -> String {
        value.map { bytes($0) + "/s" } ?? "—"
    }
}
