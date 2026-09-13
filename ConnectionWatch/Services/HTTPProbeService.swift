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
        if let result = await performSingleProbe(endpoint: primaryEndpoint, timestamp: timestamp), result.succeeded {
            return result
        }

        // Fallback to distinct endpoints on failure and update preferredIndex to the working endpoint
        if list.count > 1 {
            for offset in 1..<list.count {
                let candidateIndex = (primaryIndex + offset) % list.count
                let fallbackEndpoint = list[candidateIndex]
                if let fallbackResult = await performSingleProbe(endpoint: fallbackEndpoint, timestamp: timestamp), fallbackResult.succeeded {
                    preferredIndex = candidateIndex
                    return fallbackResult
                }
            }
        }

        return PingResult(timestamp: timestamp, latency: nil, endpoint: primaryEndpoint, probeType: .http)
    }

    private func performSingleProbe(endpoint: String, timestamp: Date) async -> PingResult? {
        if let headResult = await performRequest(endpoint: endpoint, method: "HEAD", timestamp: timestamp),
           headResult.succeeded {
            return headResult
        }
        // Fallback once to GET if a corporate proxy or server rejects HEAD
        return await performRequest(endpoint: endpoint, method: "GET", timestamp: timestamp)
    }

    private func performRequest(endpoint: String, method: String, timestamp: Date) async -> PingResult? {
        guard let url = URL(string: endpoint) else {
            return PingResult(timestamp: timestamp, latency: nil, endpoint: endpoint, probeType: .http)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 3.0

        let metricsDelegate = URLSessionMetricsDelegate()
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (_, response) = try await session.data(for: request, delegate: metricsDelegate)
            let metrics = metricsDelegate.collectedMetrics
            let wallElapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                return PingResult(timestamp: timestamp, latency: nil, endpoint: endpoint, probeType: .http)
            }

            // Prefer exact TTFB (responseStartDate - requestStartDate) from URLSessionTaskMetrics if available
            var finalLatency = wallElapsedMs
            if let metrics,
               let transaction = metrics.transactionMetrics.last,
               let reqStart = transaction.requestStartDate,
               let respStart = transaction.responseStartDate {
                let ttfbMs = respStart.timeIntervalSince(reqStart) * 1000
                if ttfbMs > 0.5 && ttfbMs <= wallElapsedMs {
                    finalLatency = ttfbMs
                }
            }

            return PingResult(timestamp: timestamp, latency: finalLatency, endpoint: endpoint, probeType: .http)
        } catch {
            return PingResult(timestamp: timestamp, latency: nil, endpoint: endpoint, probeType: .http)
        }
    }
}
