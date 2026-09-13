import Foundation

private final class SpeedMetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

actor SpeedTestService {
    private let session: URLSession
    private let delegate = SpeedMetricsDelegate()

    static let smallPayloadURL = "https://speed.cloudflare.com/__down?bytes=250000"    // 250 KB (safe even on 1-2 Mbps links)
    static let mediumPayloadURL = "https://speed.cloudflare.com/__down?bytes=2000000"  // 2 MB (for fast links)

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 8.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    /// Strictly on-demand download speed measurement in Mbps.
    /// Starts with a 250 KB probe so slow links (1-3 Mbps) complete accurately;
    /// if the link is fast (> 8 Mbps), follows up with a 2 MB sample.
    func measureDownloadSpeed() async -> PingResult {
        let timestamp = Date()

        if let smallResult = await downloadProbe(urlString: Self.smallPayloadURL) {
            if let mbps = smallResult.downloadSpeedMbps, mbps > 8.0 {
                if let mediumResult = await downloadProbe(urlString: Self.mediumPayloadURL),
                   let mediumMbps = mediumResult.downloadSpeedMbps {
                    return PingResult(
                        timestamp: timestamp,
                        latency: mediumResult.latency ?? smallResult.latency,
                        downloadSpeedMbps: max(mbps, mediumMbps),
                        endpoint: "speed.cloudflare.com",
                        probeType: .speed
                    )
                }
            }
            return smallResult
        }

        return PingResult(
            timestamp: timestamp,
            latency: nil,
            downloadSpeedMbps: nil,
            endpoint: "speed.cloudflare.com",
            probeType: .speed
        )
    }

    private func downloadProbe(urlString: String) async -> PingResult? {
        let timestamp = Date()
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 8.0

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (data, response, taskID) = try await runDownloadTask(request: request)
            let metrics = delegate.takeMetrics(for: taskID)
            let wallElapsed = max(0.001, CFAbsoluteTimeGetCurrent() - start)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  data.count >= 10_000 else {
                return nil
            }

            var transferDuration = wallElapsed
            var bytesReceived = Double(data.count)
            var ttfbMs: Double?

            if let metrics,
               let transaction = metrics.transactionMetrics.last {
                if let reqStart = transaction.requestStartDate,
                   let respStart = transaction.responseStartDate {
                    ttfbMs = respStart.timeIntervalSince(reqStart) * 1000
                }
                if let respStart = transaction.responseStartDate,
                   let respEnd = transaction.responseEndDate {
                    let payloadDuration = respEnd.timeIntervalSince(respStart)
                    if payloadDuration > 0.005 {
                        transferDuration = payloadDuration
                    }
                }
                if transaction.countOfResponseBodyBytesReceived > 0 {
                    bytesReceived = Double(transaction.countOfResponseBodyBytesReceived)
                }
            }

            let mbps = (bytesReceived * 8.0) / (transferDuration * 1_000_000.0)
            let host = url.host() ?? urlString

            return PingResult(
                timestamp: timestamp,
                latency: ttfbMs,
                downloadSpeedMbps: mbps,
                endpoint: host,
                probeType: .speed
            )
        } catch {
            return nil
        }
    }

    private func runDownloadTask(request: URLRequest) async throws -> (Data, URLResponse, Int) {
        try await withCheckedThrowingContinuation { continuation in
            var taskID = 0
            let task = session.dataTask(with: request) { [delegate] data, response, error in
                if let error {
                    _ = delegate.takeMetrics(for: taskID)
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response, taskID))
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
