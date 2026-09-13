import Foundation

actor SpeedTestService {
    private let session: URLSession

    static let smallPayloadURL = "https://speed.cloudflare.com/__down?bytes=250000"    // 250 KB (safe even on 1-2 Mbps links)
    static let mediumPayloadURL = "https://speed.cloudflare.com/__down?bytes=2000000"  // 2 MB (for fast links)

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 8.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
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

        let metricsDelegate = URLSessionMetricsDelegate()
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (data, response) = try await session.data(for: request, delegate: metricsDelegate)
            let metrics = metricsDelegate.collectedMetrics
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
}
