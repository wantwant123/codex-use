import Foundation

actor ProxyTrafficClient {
    enum ClientError: Error, Equatable {
        case invalidAddress, unauthorized, unavailable, oversized, invalidResponse
    }

    private let session: URLSession
    private let request: URLRequest
    private var accumulator = TrafficAccumulator()
    static let maxResponseBytes = 4 * 1_024 * 1_024

    init(address: String, secret: String = "", configuration: URLSessionConfiguration = .ephemeral) throws {
        request = try Self.makeRequest(address: address, secret: secret)
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
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
            guard http.statusCode != 401 && http.statusCode != 403 else { throw ClientError.unauthorized }
            guard http.statusCode == 200 else { throw ClientError.unavailable }
            guard response.expectedContentLength <= Int64(Self.maxResponseBytes) else { throw ClientError.oversized }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maxResponseBytes else { throw ClientError.oversized }
                data.append(byte)
            }
            try Task.checkCancellation()
            let sample = try Self.decode(data)
            return accumulator.ingest(sample, at: Date(), time: ProcessInfo.processInfo.systemUptime)
        } catch {
            accumulator.interrupt()
            throw error
        }
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

    func close() { session.invalidateAndCancel() }
}

nonisolated private final class LocalControllerDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    // A controller redirect must never forward its bearer credential to another endpoint.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
