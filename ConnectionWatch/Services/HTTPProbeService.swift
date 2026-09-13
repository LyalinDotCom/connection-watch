import Foundation

actor HTTPProbeService {
    private let session: URLSession
    private var currentIndex = 0

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

    func probe(endpoints: [String] = defaultEndpoints) async -> PingResult {
        let list = endpoints.isEmpty ? Self.defaultEndpoints : endpoints
        let primaryIndex = currentIndex % list.count
        currentIndex += 1

        let primaryEndpoint = list[primaryIndex]
        if let result = await performSingleProbe(endpoint: primaryEndpoint), result.succeeded {
            return result
        }

        // Fallback to a second distinct endpoint to avoid false alarms on single CDN hiccups
        if list.count > 1 {
            let fallbackEndpoint = list[(primaryIndex + 1) % list.count]
            if let fallbackResult = await performSingleProbe(endpoint: fallbackEndpoint), fallbackResult.succeeded {
                return fallbackResult
            }
        }

        return PingResult(timestamp: Date(), latency: nil, endpoint: primaryEndpoint, probeType: .http)
    }

    private func performSingleProbe(endpoint: String) async -> PingResult? {
        let timestamp = Date()
        guard let url = URL(string: endpoint) else {
            return PingResult(timestamp: timestamp, latency: nil, endpoint: endpoint, probeType: .http)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
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
                  (200...499).contains(httpResponse.statusCode) else {
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
