import Foundation

/// Reads live Antigravity quota groups from the running local Antigravity language server
/// over loopback Connect-RPC (`RetrieveUserQuotaSummary` with `GetUserStatus` fallback).
final class AntigravityQuotaClient {
    enum ClientError: Error {
        case serverNotRunning
        case unavailable
        case invalidResponse
    }

    struct ServerInstance: Equatable {
        let pid: Int32
        let csrfToken: String
        let hintPort: Int?
    }

    private struct CachedEndpoint {
        let pid: Int32
        let csrfToken: String
        let scheme: String
        let port: Int
    }

    private let lock = NSLock()
    private var cachedEndpoint: CachedEndpoint?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 2.0) {
        self.timeout = timeout
    }

    func fetchQuotaGroups() throws -> [QuotaGroup] {
        let instances = Self.discoverServerInstances()
        guard !instances.isEmpty else {
            clearCache()
            throw ClientError.serverNotRunning
        }

        // Fast path: reuse previously verified (pid, scheme, port) if the process is still alive.
        if let cached = currentCache(),
           instances.contains(where: { $0.pid == cached.pid && $0.csrfToken == cached.csrfToken }) {
            if let groups = tryQuery(scheme: cached.scheme, port: cached.port, csrfToken: cached.csrfToken),
               !groups.isEmpty {
                return groups
            }
            clearCache()
        }

        for instance in instances {
            let ports = Self.listeningPorts(for: instance.pid, preferred: instance.hintPort)
            for port in ports {
                for scheme in ["https", "http"] {
                    if let groups = tryQuery(scheme: scheme, port: port, csrfToken: instance.csrfToken),
                       !groups.isEmpty {
                        saveCache(CachedEndpoint(pid: instance.pid, csrfToken: instance.csrfToken, scheme: scheme, port: port))
                        return groups
                    }
                }
            }
        }

        throw ClientError.unavailable
    }

    private func tryQuery(scheme: String, port: Int, csrfToken: String) -> [QuotaGroup]? {
        if let summaryJSON = postConnectJSON(
            scheme: scheme,
            port: port,
            path: "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
            csrfToken: csrfToken,
            body: [:]
        ) {
            let groups = Self.parseQuotaSummary(summaryJSON)
            if !groups.isEmpty {
                return groups
            }
        }

        if let statusJSON = postConnectJSON(
            scheme: scheme,
            port: port,
            path: "/exa.language_server_pb.LanguageServerService/GetUserStatus",
            csrfToken: csrfToken,
            body: [
                "metadata": [
                    "ideName": "antigravity",
                    "extensionName": "antigravity",
                    "locale": "en",
                ]
            ]
        ) {
            let groups = Self.parseUserStatus(statusJSON)
            if !groups.isEmpty {
                return groups
            }
        }

        return nil
    }

    private func postConnectJSON(
        scheme: String,
        port: Int,
        path: String,
        csrfToken: String,
        body: [String: Any]
    ) -> [String: Any]? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)\(path)"),
              let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue(csrfToken, forHTTPHeaderField: "x-antigravity-csrf-token")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.connectionProxyDictionary = [:]

        let delegate = LoopbackTLSDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var statusCode = 0

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil, let http = response as? HTTPURLResponse else { return }
            statusCode = http.statusCode
            responseData = data
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout + 0.5) == .timedOut {
            task.cancel()
            return nil
        }

        guard statusCode == 200,
              let responseData,
              responseData.count <= 2 * 1_024 * 1_024,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func currentCache() -> CachedEndpoint? {
        lock.lock()
        defer { lock.unlock() }
        return cachedEndpoint
    }

    private func saveCache(_ endpoint: CachedEndpoint) {
        lock.lock()
        cachedEndpoint = endpoint
        lock.unlock()
    }

    private func clearCache() {
        lock.lock()
        cachedEndpoint = nil
        lock.unlock()
    }

    // MARK: - Process & Port Discovery

    private static func discoverServerInstances() -> [ServerInstance] {
        guard let output = runCommand("/bin/ps", arguments: ["-axo", "pid=,command="]) else {
            return []
        }
        return parseServerInstances(from: output)
    }

    static func parseServerInstances(from psOutput: String) -> [ServerInstance] {
        var preferred: [ServerInstance] = []
        var fallback: [ServerInstance] = []

        for rawLine in psOutput.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            guard lower.contains("language_server"),
                  lower.contains("--csrf_token") else {
                continue
            }

            guard let firstSpace = line.firstIndex(where: { $0.isWhitespace }),
                  let pid = Int32(line[..<firstSpace]) else {
                continue
            }
            let command = String(line[firstSpace...])
            guard let token = extractFlag("--csrf_token", from: command), !token.isEmpty else {
                continue
            }
            let hintPort = extractFlag("--extension_server_port", from: command).flatMap(Int.init)
            let instance = ServerInstance(pid: pid, csrfToken: token, hintPort: hintPort)
            if lower.contains("antigravity") {
                preferred.append(instance)
            } else {
                fallback.append(instance)
            }
        }

        return preferred + fallback
    }

    private static func listeningPorts(for pid: Int32, preferred: Int?) -> [Int] {
        let output = runCommand(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"]
        ) ?? ""
        return parseListeningPorts(from: output, preferred: preferred)
    }

    static func parseListeningPorts(from lsofOutput: String, preferred: Int? = nil) -> [Int] {
        var ports: [Int] = []
        var seen = Set<Int>()

        for line in lsofOutput.split(separator: "\n") {
            let text = String(line)
            guard text.contains("LISTEN") else { continue }
            for token in text.split(whereSeparator: \.isWhitespace) {
                guard let colon = token.lastIndex(of: ":") else { continue }
                let host = token[..<colon]
                guard host.contains("127.0.0.1") || host.contains("localhost") || host == "*" || host == "[::1]" else {
                    continue
                }
                let portStr = token[token.index(after: colon)...]
                if let port = Int(portStr), (1...65_535).contains(port), seen.insert(port).inserted {
                    ports.append(port)
                }
            }
        }

        if let preferred, (1...65_535).contains(preferred) {
            ports.removeAll { $0 == preferred }
            ports.append(preferred)
        }
        return ports
    }

    static func extractFlag(_ flag: String, from command: String) -> String? {
        guard let range = command.range(of: flag) else { return nil }
        var rest = command[range.upperBound...]
        if rest.first == "=" {
            rest = rest.dropFirst()
        } else {
            rest = rest.drop(while: \.isWhitespace)
        }
        guard !rest.isEmpty else { return nil }

        if rest.first == "\"" || rest.first == "'" {
            let quote = rest.removeFirst()
            guard let end = rest.firstIndex(of: quote) else { return String(rest) }
            return String(rest[..<end])
        }

        let value = rest.prefix { !$0.isWhitespace }
        return value.isEmpty ? nil : String(value)
    }

    private static func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Response Parsing

    static func parseQuotaSummary(_ json: [String: Any]) -> [QuotaGroup] {
        let rawGroups: [[String: Any]]? =
            (json["groups"] as? [[String: Any]])
            ?? ((json["response"] as? [String: Any])?["groups"] as? [[String: Any]])
            ?? ((json["quotaSummary"] as? [String: Any])?["groups"] as? [[String: Any]])
            ?? ((json["userQuotaSummary"] as? [String: Any])?["groups"] as? [[String: Any]])
            ?? (json["quotaGroups"] as? [[String: Any]])
            ?? ((json["response"] as? [String: Any])?["quotaGroups"] as? [[String: Any]])

        guard let rawGroups, !rawGroups.isEmpty else { return [] }

        var parsed: [QuotaGroup] = []
        for (index, item) in rawGroups.enumerated() {
            let name = (item["displayName"] as? String)
                ?? (item["name"] as? String)
                ?? (item["title"] as? String)
                ?? "Group \(index + 1)"

            let buckets = (item["buckets"] as? [[String: Any]])
                ?? (item["limits"] as? [[String: Any]])
                ?? (item["windows"] as? [[String: Any]])
                ?? []

            var fiveHourPercent: Double?
            var fiveHourReset: Date?
            var weeklyPercent: Double?
            var weeklyReset: Date?

            for bucket in buckets {
                let percent = remainingPercent(from: bucket)
                let resetAt = date(from: bucket["resetTime"] ?? bucket["resetsAt"] ?? bucket["reset_time"])
                guard percent != nil || resetAt != nil else { continue }

                let label = [
                    bucket["window"] as? String,
                    bucket["displayName"] as? String,
                    bucket["bucketId"] as? String,
                    bucket["id"] as? String,
                    bucket["name"] as? String,
                ]
                    .compactMap { $0?.lowercased() }
                    .joined(separator: " ")

                if label.contains("week") || label.contains("7d") || label.contains("168h") {
                    weeklyPercent = percent
                    weeklyReset = resetAt
                } else if label.contains("5h") || label.contains("5 h") || label.contains("five") || label.contains("hour") || label.contains("short") {
                    fiveHourPercent = percent
                    fiveHourReset = resetAt
                } else if weeklyPercent == nil {
                    weeklyPercent = percent
                    weeklyReset = resetAt
                } else if fiveHourPercent == nil {
                    fiveHourPercent = percent
                    fiveHourReset = resetAt
                }
            }

            guard fiveHourPercent != nil || weeklyPercent != nil || fiveHourReset != nil || weeklyReset != nil else {
                continue
            }

            let id = (item["groupId"] as? String)
                ?? (item["id"] as? String)
                ?? name.lowercased().replacingOccurrences(of: " ", with: "-")
            parsed.append(QuotaGroup(
                id: id,
                name: name,
                fiveHourRemainingPercent: fiveHourPercent,
                fiveHourResetAt: fiveHourReset,
                weeklyRemainingPercent: weeklyPercent,
                weeklyResetAt: weeklyReset
            ))
        }

        return sortGroups(parsed)
    }

    static func parseUserStatus(_ json: [String: Any]) -> [QuotaGroup] {
        // Some builds embed quota summary groups inside GetUserStatus too.
        if let userStatus = json["userStatus"] as? [String: Any] {
            let embedded = parseQuotaSummary(userStatus)
            if !embedded.isEmpty {
                return embedded
            }
        }

        guard let userStatus = json["userStatus"] as? [String: Any],
              let cascadeData = userStatus["cascadeModelConfigData"] as? [String: Any],
              let configs = cascadeData["clientModelConfigs"] as? [[String: Any]],
              !configs.isEmpty else {
            return []
        }

        struct BucketReading {
            var minRemaining: Double?
            var resetAt: Date?
        }

        var gemini = BucketReading()
        var thirdParty = BucketReading()

        func record(_ reading: inout BucketReading, percent: Double?, resetAt: Date?) {
            if let percent {
                if let existing = reading.minRemaining {
                    if percent < existing {
                        reading.minRemaining = percent
                        reading.resetAt = resetAt ?? reading.resetAt
                    }
                } else {
                    reading.minRemaining = percent
                    reading.resetAt = resetAt
                }
            } else if reading.resetAt == nil {
                reading.resetAt = resetAt
            }
        }

        for config in configs {
            guard let quotaInfo = config["quotaInfo"] as? [String: Any] else { continue }
            let percent = remainingPercent(from: quotaInfo)
            let resetAt = date(from: quotaInfo["resetTime"] ?? quotaInfo["resetsAt"])
            guard percent != nil || resetAt != nil else { continue }

            let label = ((config["label"] as? String) ?? "").lowercased()
            let alias = (((config["modelOrAlias"] as? [String: Any])?["model"] as? String) ?? "").lowercased()
            let combined = "\(label) \(alias)"

            if combined.contains("claude") || combined.contains("gpt") || combined.contains("openai") {
                record(&thirdParty, percent: percent, resetAt: resetAt)
            } else {
                record(&gemini, percent: percent, resetAt: resetAt)
            }
        }

        var groups: [QuotaGroup] = []
        if gemini.minRemaining != nil || gemini.resetAt != nil {
            groups.append(QuotaGroup(
                id: "gemini",
                name: "Gemini Models",
                fiveHourRemainingPercent: gemini.minRemaining,
                fiveHourResetAt: gemini.resetAt,
                weeklyRemainingPercent: nil,
                weeklyResetAt: nil
            ))
        }
        if thirdParty.minRemaining != nil || thirdParty.resetAt != nil {
            groups.append(QuotaGroup(
                id: "claude-gpt",
                name: "Claude and GPT models",
                fiveHourRemainingPercent: thirdParty.minRemaining,
                fiveHourResetAt: thirdParty.resetAt,
                weeklyRemainingPercent: nil,
                weeklyResetAt: nil
            ))
        }
        return groups
    }

    private static func sortGroups(_ groups: [QuotaGroup]) -> [QuotaGroup] {
        groups.sorted { lhs, rhs in
            let lIsGemini = lhs.name.lowercased().contains("gemini")
            let rIsGemini = rhs.name.lowercased().contains("gemini")
            if lIsGemini != rIsGemini { return lIsGemini }
            return false
        }
    }

    private static func remainingPercent(from dict: [String: Any]) -> Double? {
        if let fraction = number(dict["remainingFraction"] ?? dict["remaining_fraction"]) {
            let scaled = fraction <= 1.0 ? fraction * 100.0 : fraction
            return UsageMath.clampPercent(scaled)
        }
        if let pct = number(dict["remainingPercent"] ?? dict["remaining_percent"] ?? dict["remainingPercentage"]) {
            return UsageMath.clampPercent(pct)
        }
        if let usedFraction = number(dict["usedFraction"] ?? dict["used_fraction"]) {
            let usedPercent = usedFraction <= 1.0 ? usedFraction * 100.0 : usedFraction
            return UsageMath.remainingPercent(fromUsedPercent: usedPercent)
        }
        if let usedPct = number(dict["usedPercent"] ?? dict["used_percent"]) {
            return UsageMath.remainingPercent(fromUsedPercent: usedPct)
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Float: Double(value)
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }

    private static func date(from value: Any?) -> Date? {
        if let seconds = number(value) {
            let normalized = seconds > 10_000_000_000 ? seconds / 1_000 : seconds
            return Date(timeIntervalSince1970: normalized)
        }
        guard let string = value as? String, !string.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

private final class LoopbackTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           (host == "127.0.0.1" || host == "localhost"),
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
