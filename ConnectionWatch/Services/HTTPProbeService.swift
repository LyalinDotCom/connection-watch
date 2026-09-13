import Foundation

private final class HTTPMetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var metricsByTaskIdentifier: [Int: URLSessionTaskMetrics] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        metricsByTaskIdentifier[task.taskIdentifier] = metrics
        lock.unlock()
    }

    func takeMetrics(for taskIdentifier: Int) -> URLSessionTaskMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return metricsByTaskIdentifier.removeValue(forKey: taskIdentifier)
    }
}

actor HTTPProbeService {
    private let session: URLSession
    private let delegate = HTTPMetricsDelegate()
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
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
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

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (response, taskID) = try await runDataTask(request: request)
            let metrics = delegate.takeMetrics(for: taskID)
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

    private func runDataTask(request: URLRequest) async throws -> (URLResponse, Int) {
        try await withCheckedThrowingContinuation { continuation in
            var taskID = 0
            let task = session.dataTask(with: request) { [delegate] _, response, error in
                if let error {
                    _ = delegate.takeMetrics(for: taskID)
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: (response, taskID))
                } else {
                    _ = delegate.takeMetrics(for: taskID)
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            taskID = task.taskIdentifier
            task.resume()
        }
    }
}
