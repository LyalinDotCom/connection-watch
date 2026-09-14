import Foundation

actor HTTPProbeService {
    private let session: URLSession
    private var preferredIndex = 0

    static let defaultEndpoints = [
        "https://www.google.com/generate_204",
        "https://cp.cloudflare.com/generate_204",
        "https://www.apple.com/library/test/success.html",
        "https://www.cloudflare.com/cdn-cgi/trace",
    ]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 3.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    func probe(endpoints: [String] = defaultEndpoints, timestamp: Date = Date()) async -> PingResult {
        let list = endpoints.isEmpty ? Self.defaultEndpoints : endpoints
        let primaryIndex = preferredIndex % list.count
        let primaryEndpoint = list[primaryIndex]

        guard !Task.isCancelled else {
            return PingResult(timestamp: timestamp, latency: nil, endpoint: primaryEndpoint, probeType: .http)
        }

        if let result = await performSingleProbe(endpoint: primaryEndpoint, timeout: 3.0, timestamp: timestamp), result.succeeded {
            return result
        }

        // Fallback to distinct endpoints on failure and update preferredIndex to the working endpoint
        if list.count > 1 {
            for offset in 1..<list.count {
                guard !Task.isCancelled else { break }
                let candidateIndex = (primaryIndex + offset) % list.count
                let fallbackEndpoint = list[candidateIndex]
                if let fallbackResult = await performSingleProbe(endpoint: fallbackEndpoint, timeout: 2.0, timestamp: timestamp), fallbackResult.succeeded {
                    preferredIndex = candidateIndex
                    return fallbackResult
                }
            }
        }

        return PingResult(timestamp: timestamp, latency: nil, endpoint: primaryEndpoint, probeType: .http)
    }

    private func performSingleProbe(endpoint: String, timeout: TimeInterval, timestamp: Date) async -> PingResult? {
        guard !Task.isCancelled else { return nil }
        let (headResult, shouldRetryWithGET) = await performRequest(endpoint: endpoint, method: "HEAD", timeout: timeout, timestamp: timestamp)
        if headResult.succeeded {
            return headResult
        }
        guard shouldRetryWithGET, !Task.isCancelled else {
            return headResult
        }
        // Fallback once to GET only when server/proxy responded with an HTTP error status rejecting HEAD
        let (getResult, _) = await performRequest(endpoint: endpoint, method: "GET", timeout: timeout, timestamp: timestamp)
        return getResult
    }

    private func performRequest(
        endpoint: String,
        method: String,
        timeout: TimeInterval,
        timestamp: Date
    ) async -> (result: PingResult, shouldRetryWithGET: Bool) {
        let failed = PingResult(timestamp: timestamp, latency: nil, endpoint: endpoint, probeType: .http)
        guard !Task.isCancelled, let url = URL(string: endpoint) else {
            return (failed, false)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = timeout

        let metricsDelegate = URLSessionMetricsDelegate()
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (_, response) = try await session.data(for: request, delegate: metricsDelegate)
            let metrics = metricsDelegate.collectedMetrics
            let wallElapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

            guard let httpResponse = response as? HTTPURLResponse else {
                return (failed, false)
            }

            guard (200...399).contains(httpResponse.statusCode) else {
                // Server responded with HTTP error (e.g. 405 Method Not Allowed) — retry with GET if this was HEAD
                return (failed, method == "HEAD")
            }

            // Prefer exact TTFB (responseStartDate - requestStartDate) from URLSessionTaskMetrics if available
            var finalLatency = wallElapsedMs
            if let metrics,
               let transaction = metrics.transactionMetrics.last,
               let reqStart = transaction.requestStartDate,
               let respStart = transaction.responseStartDate {
                let ttfbMs = respStart.timeIntervalSince(reqStart) * 1000
                if ttfbMs > 0.5 && ttfbMs <= wallElapsedMs && ttfbMs.isFinite {
                    finalLatency = ttfbMs
                }
            }

            return (PingResult(timestamp: timestamp, latency: finalLatency, endpoint: endpoint, probeType: .http), false)
        } catch {
            return (failed, false)
        }
    }
}
