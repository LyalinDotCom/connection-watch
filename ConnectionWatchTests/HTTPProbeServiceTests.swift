import Foundation
import Testing

@Suite(.serialized)
struct HTTPProbeServiceTests {
    @Test func failedPrimaryUsesAndRemembersIndependentFallback() async {
        let fixture = ProbeFixture { request in
            request.url?.host == "primary.test" ? .init(status: 503) : .init(status: 204)
        }
        let service = HTTPProbeService(session: fixture.session)
        let endpoints = ["https://primary.test/generate_204", "https://fallback.test/generate_204"]
        let result = await service.probe(endpoints: endpoints)
        #expect(result.succeeded)
        #expect(result.endpoint == endpoints[1])
        #expect(fixture.requests.map { $0.url?.host } == ["primary.test", "fallback.test"])

        _ = await service.probe(endpoints: endpoints)
        #expect(fixture.requests.map { $0.url?.host } == ["primary.test", "fallback.test", "fallback.test"])
    }

    @Test func allEndpointTimeoutsReportOfflineEvenWithFastPing() async {
        let fixture = ProbeFixture { _ in .init(error: URLError(.timedOut)) }
        let service = HTTPProbeService(session: fixture.session)
        let result = await service.probe()
        #expect(!result.succeeded)
        #expect(fixture.requests.compactMap { $0.url?.absoluteString } == HTTPProbeService.defaultEndpoints)
        let health = NetworkHealth.evaluate(
            isConnected: true, pingLatency: 5, jitter: 1, recentPacketLoss: 0,
            httpLatency: result.latency, downloadSpeedMbps: nil,
            goodThreshold: 150, degradedThreshold: 600, isICMPBlocked: false
        )
        #expect(health.state == .disconnected)
        #expect(health.score == 0)
    }

    @Test func latencyIncludesFailedAttemptsBeforeFallbackSuccess() async {
        let fixture = ProbeFixture { request in
            request.url?.host == "primary.test" ? .init(delay: 0.12, error: URLError(.timedOut)) : .init(status: 204)
        }
        let result = await HTTPProbeService(session: fixture.session).probe(endpoints: [
            "https://primary.test/generate_204", "https://fallback.test/generate_204"
        ])
        #expect(result.succeeded)
        #expect((result.latency ?? 0) >= 110)
    }

    @Test func unsupportedHEADRetriesGET() async {
        let fixture = ProbeFixture { request in
            .init(status: request.httpMethod == "HEAD" ? 405 : 204)
        }
        let result = await HTTPProbeService(session: fixture.session).probe(endpoints: ["https://probe.test/generate_204"])
        #expect(result.succeeded)
        #expect(fixture.requests.map(\.httpMethod) == ["HEAD", "GET"])
    }

    @Test(arguments: [200, 302, 500])
    func unexpectedConnectivityResponseIsFailure(status: Int) async {
        let fixture = ProbeFixture { _ in .init(status: status) }
        let result = await HTTPProbeService(session: fixture.session).probe(endpoints: ["https://probe.test/generate_204"])
        #expect(!result.succeeded)
    }

    @Test func redirectedLoginResponseIsNotInternetAccess() async {
        let fixture = ProbeFixture { _ in .init(status: 200, responseURL: URL(string: "https://login.test/")) }
        let result = await HTTPProbeService(session: fixture.session).probe(endpoints: ["https://probe.test/success.html"])
        #expect(!result.succeeded)
    }

    @Test func successfulNon204EndpointStillWorks() async {
        let fixture = ProbeFixture { _ in .init(status: 200) }
        let timestamp = Date(timeIntervalSince1970: 1234)
        let result = await HTTPProbeService(session: fixture.session).probe(
            endpoints: ["https://probe.test/success.html"], timestamp: timestamp
        )
        #expect(result.succeeded)
        #expect(result.timestamp == timestamp)
        #expect(result.probeType == .http)
    }
}

private struct StubResponse {
    var status = 204
    var delay: TimeInterval = 0
    var error: Error?
    var responseURL: URL?
}

private final class ProbeFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    let session: URLSession

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    init(handler: @escaping (URLRequest) -> StubResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProbeURLProtocol.self]
        session = URLSession(configuration: config)
        ProbeURLProtocol.setHandler { [weak self] request in
            if let self {
                self.lock.lock()
                self.recordedRequests.append(request)
                self.lock.unlock()
            }
            return handler(request)
        }
    }

    deinit { session.invalidateAndCancel() }
}

private final class ProbeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> StubResponse)?

    static func setHandler(_ value: @escaping (URLRequest) -> StubResponse) {
        lock.lock()
        defer { lock.unlock() }
        handler = value
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        guard let stub = handler?(request), let url = stub.responseURL ?? request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if stub.delay > 0 { Thread.sleep(forTimeInterval: stub.delay) }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
