import ClashHTTP
import Foundation

nonisolated struct ClashVergeAPI: Sendable {
    static let controller = "clash-verge:\(getuid())"
    // Service mode and user-launched sidecar mode use different sockets.
    var socketPaths = [
        "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock",
        FileManager.default.temporaryDirectory.appendingPathComponent("verge-mihomo.sock").path
    ]

    func read(_ path: String, limit: Int) async throws -> Data {
        guard let socket = socketPaths.first(where: FileManager.default.fileExists(atPath:)) else {
            throw ProxyTrafficClient.ClientError.unavailable
        }
        return try await Self.get("http://localhost" + path, socket: socket, limit: limit)
    }

    func exitCountry() async throws -> String {
        struct Ports: Decodable {
            let mixed: Int?
            let http: Int?
            enum CodingKeys: String, CodingKey { case mixed = "mixed-port", http = "port" }
        }
        let ports = try JSONDecoder().decode(Ports.self, from: await read("/configs", limit: 128 * 1024))
        guard let port = [ports.mixed, ports.http].compactMap({ $0 }).first(where: (1...65535).contains) else {
            throw ProxyTrafficClient.ClientError.unavailable
        }
        let country = try await Self.get("https://ipinfo.io/country", proxy: "http://127.0.0.1:\(port)", limit: 64)
        let code = String(decoding: country, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard Locale.Region.isoRegions.contains(Locale.Region(code)) else { throw ProxyTrafficClient.ClientError.invalidResponse }
        return code
    }

    private final class Body {
        let limit: Int
        var data = Data()
        var oversized = false
        init(limit: Int) { self.limit = limit }
    }

    private static func get(_ url: String, socket: String? = nil, proxy: String = "", limit: Int) async throws -> Data {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let body = Body(limit: limit)
            var status = 0
            let result = withExtendedLifetime(body) {
                clash_get(url, socket, proxy, limit, { bytes, size, count, context in
                    guard let bytes, let context else { return 0 }
                    let body = Unmanaged<Body>.fromOpaque(context).takeUnretainedValue()
                    let length = size * count
                    guard length <= body.limit - body.data.count else { body.oversized = true; return 0 }
                    body.data.append(UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self), count: length)
                    return length
                }, Unmanaged.passUnretained(body).toOpaque(), { _, _, _, _, _ in Task.isCancelled ? 1 : 0 }, &status)
            }
            try Task.checkCancellation()
            if body.oversized || result == CURLE_FILESIZE_EXCEEDED { throw ProxyTrafficClient.ClientError.oversized }
            guard result == CURLE_OK, status == 200 else { throw ProxyTrafficClient.ClientError.unavailable }
            return body.data
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
