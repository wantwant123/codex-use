import Foundation
import Network

/// Serves one HTTP response per connection on a private Unix socket, like the Clash core.
final class ClashSocketFixture: @unchecked Sendable {
    typealias Reply = @Sendable (_ target: String) -> Data?
    let path = "/tmp/ab-\(UUID().uuidString).sock"
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ClashSocketFixture")

    init(reply: @escaping Reply) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: path)
        listener = try NWListener(using: parameters)
        let queue = self.queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                guard let data, let request = String(data: data, encoding: .utf8),
                      let target = request.split(separator: " ").dropFirst().first else {
                    connection.cancel()
                    return
                }
                if let response = reply(String(target)) {
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                } else {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in connection.cancel() }
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    listener?.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener?.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    static func response(_ body: String, status: Int = 200) -> Data {
        Data("HTTP/1.1 \(status) Reply\r\nConnection: close\r\n\r\n\(body)".utf8)
    }

    deinit {
        listener.cancel()
        unlink(path)
    }
}
