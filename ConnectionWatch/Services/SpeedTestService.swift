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

        // Stage 1 calibrates the link. If it fails there is nothing measured to report,
        // and nothing was transferred.
        guard !Task.isCancelled,
              let calibration = await downloadProbe(urlString: Self.warmupPayloadURL),
              !Task.isCancelled else {
            return PingResult(
                timestamp: timestamp,
                latency: nil,
                downloadSpeedMbps: nil,
                bytesTransferred: nil,
                endpoint: "speed.cloudflare.com",
                probeType: .speed
            )
        }

        var totalBytes = calibration.bytesTransferred ?? 0
        var bestMbps = calibration.downloadSpeedMbps
        var bestLatency = calibration.latency

        // Each stage only runs if the previous one measured fast enough to justify the
        // extra bandwidth, so slow links never download the larger payloads.
        let escalation = [
            (minimumMbps: 4.0, url: Self.standardPayloadURL),
            (minimumMbps: 30.0, url: Self.largePayloadURL),
        ]

        var previousMbps = calibration.downloadSpeedMbps
        for stage in escalation {
            guard let mbps = previousMbps, mbps > stage.minimumMbps, !Task.isCancelled else { break }
            guard let result = await downloadProbe(urlString: stage.url), !Task.isCancelled else { break }

            totalBytes += result.bytesTransferred ?? 0
            if let measured = result.downloadSpeedMbps {
                bestMbps = max(bestMbps ?? 0, measured)
            }
            bestLatency = result.latency ?? bestLatency
            previousMbps = result.downloadSpeedMbps
        }

        if Task.isCancelled {
            return PingResult(
                timestamp: timestamp,
                latency: nil,
                downloadSpeedMbps: nil,
                bytesTransferred: nil,
                endpoint: "speed.cloudflare.com",
                probeType: .speed
            )
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

    private func downloadProbe(urlString: String) async -> PingResult? {
        let timestamp = Date()
        guard !Task.isCancelled, let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 18.0

        let metricsDelegate = URLSessionMetricsDelegate()
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (data, response) = try await session.data(for: request, delegate: metricsDelegate)
            guard !Task.isCancelled else { return nil }
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
