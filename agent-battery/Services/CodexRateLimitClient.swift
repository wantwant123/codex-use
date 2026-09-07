import Darwin
import Foundation

/// Reads account quota through Codex's authenticated app-server protocol.
/// No conversation is started and no credentials are read by Agent Battery.
struct CodexRateLimitClient {
    var executableURL: URL? = nil
    var timeout: TimeInterval = 10

    func fetch(codexHomeURL: URL) throws -> [String: Any] {
        guard let executable = executableURL ?? Self.findExecutable() else {
            throw ClientError.unavailable
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let exited = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHomeURL.path
        process.environment = environment
        process.currentDirectoryURL = codexHomeURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        // A server exiting between a reply and our next write must not kill the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            try? output.fileHandleForReading.close()
        }

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send([
            "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "agent_battery", "title": "Agent Battery", "version": "1.0"]],
        ])
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var buffer = Data()
        var initialized = false
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 {
                if errno == EINTR { continue }
                throw ClientError.unavailable
            }
            guard ready > 0 else { continue }
            // FileHandle.read(upToCount:) can wait to fill the buffer on a pipe.
            // A single POSIX read consumes only ready bytes, preserving the deadline.
            let count = chunk.withUnsafeMutableBytes {
                Darwin.read(descriptor.fd, $0.baseAddress, $0.count)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ClientError.unavailable }
            buffer.append(contentsOf: chunk.prefix(count))
            guard buffer.count <= 1_048_576 else { throw ClientError.invalidResponse }
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = message["id"] as? Int else { continue }
                guard message["error"] == nil else { throw ClientError.unavailable }
                if id == 1, !initialized {
                    initialized = true
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2, initialized {
                    guard let result = message["result"] as? [String: Any] else {
                        throw ClientError.invalidResponse
                    }
                    return result
                }
            }
        }
        throw ClientError.timedOut
    }

    static func codexLimit(in response: [String: Any]) -> [String: Any]? {
        if let buckets = response["rateLimitsByLimitId"] as? [String: Any] {
            return buckets["codex"] as? [String: Any]
        }
        guard let limit = response["rateLimits"] as? [String: Any],
              limit["limitId"] == nil || limit["limitId"] as? String == "codex" else { return nil }
        return limit
    }

    private static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
            + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    enum ClientError: Error {
        case unavailable, invalidResponse, timedOut
    }
}
