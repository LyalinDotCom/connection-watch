import Foundation

actor HTTPProbeService {
    private let session: URLSession
    private var preferredIndex = 0

    static let defaultEndpoints = [
        "https://www.google.com/generate_204",
        "https://cp.cloudflare.com/generate_204",
        "https://www.apple.com/library/test/success.html",
    ]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 3.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    func probe(endpoints: [String] = defaultEndpoints, timestamp: Date = Date()) async -> PingResult {
        let start = ProcessInfo.processInfo.systemUptime
        let list = endpoints.isEmpty ? Self.defaultEndpoints : endpoints
        let primaryIndex = preferredIndex % list.count
        let primaryEndpoint = list[primaryIndex]

        guard !Task.isCancelled else {
            return PingResult(timestamp: timestamp, latency: nil, endpoint: primaryEndpoint, probeType: .http)
        }

        // Include DNS, connection setup, and all failed attempts in the user-visible wait.
        func success(endpoint: String) -> PingResult {
            PingResult(
                timestamp: timestamp,
                latency: (ProcessInfo.processInfo.systemUptime - start) * 1000,
                endpoint: endpoint,
                probeType: .http
            )
        }

        if await performSingleProbe(endpoint: primaryEndpoint, timeout: 3.0) {
            return success(endpoint: primaryEndpoint)
        }

        // Fallback to distinct endpoints on failure and update preferredIndex to the working endpoint
        if list.count > 1 {
            for offset in 1..<list.count {
                guard !Task.isCancelled else { break }
                let candidateIndex = (primaryIndex + offset) % list.count
                let fallbackEndpoint = list[candidateIndex]
                if await performSingleProbe(endpoint: fallbackEndpoint, timeout: 2.0) {
                    preferredIndex = candidateIndex
                    return success(endpoint: fallbackEndpoint)
                }
            }
        }

        return PingResult(timestamp: timestamp, latency: nil, endpoint: primaryEndpoint, probeType: .http)
    }

    private func performSingleProbe(endpoint: String, timeout: TimeInterval) async -> Bool {
        guard !Task.isCancelled else { return false }
        let (succeeded, shouldRetryWithGET) = await performRequest(endpoint: endpoint, method: "HEAD", timeout: timeout)
        if succeeded { return true }
        guard shouldRetryWithGET, !Task.isCancelled else { return false }
        // Retry only when HEAD is unsupported, not on every server or proxy failure.
        let (getSucceeded, _) = await performRequest(endpoint: endpoint, method: "GET", timeout: timeout)
        return getSucceeded
    }

    private func performRequest(
        endpoint: String,
        method: String,
        timeout: TimeInterval
    ) async -> (succeeded: Bool, shouldRetryWithGET: Bool) {
        guard !Task.isCancelled, let url = URL(string: endpoint) else {
            return (false, false)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = timeout

        do {
            let (_, response) = try await session.data(for: request)
            guard !Task.isCancelled, let httpResponse = response as? HTTPURLResponse,
                  httpResponse.url == url else {
                // A redirected sign-in page is not a successful connectivity check.
                return (false, false)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return (false, method == "HEAD" && [405, 501].contains(httpResponse.statusCode))
            }
            if url.lastPathComponent == "generate_204", httpResponse.statusCode != 204 {
                return (false, false)
            }
            return (true, false)
        } catch {
            return (false, false)
        }
    }
}
