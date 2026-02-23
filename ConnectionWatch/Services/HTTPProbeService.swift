import Foundation

actor HTTPProbeService {
    private let session: URLSession
    private var currentIndex = 0

    static let defaultEndpoints = [
        "https://www.google.com/generate_204",
        "https://github.com",
        "https://www.cloudflare.com",
        "https://www.apple.com",
        "https://www.amazon.com",
    ]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    func probe(endpoints: [String] = defaultEndpoints) async -> PingResult {
        let list = endpoints.isEmpty ? Self.defaultEndpoints : endpoints
        let endpoint = list[currentIndex % list.count]
        currentIndex += 1

        let timestamp = Date()

        guard let url = URL(string: endpoint) else {
            return PingResult(timestamp: timestamp, latency: nil, endpoint: endpoint, probeType: .http)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...499).contains(httpResponse.statusCode) else {
                return PingResult(timestamp: timestamp, latency: nil, endpoint: endpoint, probeType: .http)
            }

            return PingResult(timestamp: timestamp, latency: elapsed, endpoint: endpoint, probeType: .http)
        } catch {
            return PingResult(timestamp: timestamp, latency: nil, endpoint: endpoint, probeType: .http)
        }
    }
}
