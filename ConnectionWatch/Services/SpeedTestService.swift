import Foundation

actor SpeedTestService {
    private let session: URLSession

    static let warmupPayloadURL = "https://speed.cloudflare.com/__down?bytes=1000000"    // 1 MB warm-up / slow link
    static let standardPayloadURL = "https://speed.cloudflare.com/__down?bytes=10000000" // 10 MB sustained
    static let largePayloadURL = "https://speed.cloudflare.com/__down?bytes=25000000"    // 25 MB high-speed sustained

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 20.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    /// Multi-stage realistic on-demand download speed measurement in Mbps.
    /// - Stage 1: 1 MB calibration probe
    /// - Stage 2: 10 MB sustained probe (if > 4 Mbps)
    /// - Stage 3: 25 MB sustained probe (if > 30 Mbps)
    /// Records the cumulative bytes downloaded across all stages so the UI can report exact bandwidth usage.
    func measureDownloadSpeed() async -> PingResult {
        let timestamp = Date()
        var totalBytes = 0
        var bestMbps: Double?
        var bestLatency: Double?

        // Stage 1: 1 MB warmup probe
        if let stage1 = await downloadProbe(urlString: Self.warmupPayloadURL) {
            totalBytes += stage1.bytesTransferred ?? 0
            bestMbps = stage1.downloadSpeedMbps
            bestLatency = stage1.latency

            // Stage 2: 10 MB sustained probe if link is > 4 Mbps
            if let mbps1 = stage1.downloadSpeedMbps, mbps1 > 4.0, !Task.isCancelled {
                if let stage2 = await downloadProbe(urlString: Self.standardPayloadURL) {
                    totalBytes += stage2.bytesTransferred ?? 0
                    if let mbps2 = stage2.downloadSpeedMbps {
                        bestMbps = max(bestMbps ?? 0, mbps2)
                    }
                    bestLatency = stage2.latency ?? bestLatency

                    // Stage 3: 25 MB high-speed sustained probe if link is > 30 Mbps
                    if let mbps2 = stage2.downloadSpeedMbps, mbps2 > 30.0, !Task.isCancelled {
                        if let stage3 = await downloadProbe(urlString: Self.largePayloadURL) {
                            totalBytes += stage3.bytesTransferred ?? 0
                            if let mbps3 = stage3.downloadSpeedMbps {
                                bestMbps = max(bestMbps ?? 0, mbps3)
                            }
                            bestLatency = stage3.latency ?? bestLatency
                        }
                    }
                }
            }

            return PingResult(
                timestamp: timestamp,
                latency: bestLatency,
                downloadSpeedMbps: bestMbps,
                bytesTransferred: totalBytes,
                endpoint: "speed.cloudflare.com",
                probeType: .speed
            )
        }

        return PingResult(
            timestamp: timestamp,
            latency: nil,
            downloadSpeedMbps: nil,
            bytesTransferred: totalBytes > 0 ? totalBytes : nil,
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
        request.timeoutInterval = 18.0

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
                    if payloadDuration > 0.01 {
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
                bytesTransferred: Int(bytesReceived),
                endpoint: host,
                probeType: .speed
            )
        } catch {
            return nil
        }
    }
}
