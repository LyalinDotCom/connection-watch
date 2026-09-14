import XCTest

final class TelemetryStoreTests: XCTestCase {
    private var tempDBURL: URL!
    private var store: TelemetryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnectionWatchTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDBURL = tempDir.appendingPathComponent("telemetry.sqlite")
        store = TelemetryStore(customDatabasePath: tempDBURL.path)
    }

    override func tearDownWithError() throws {
        store = nil
        if let tempDBURL = tempDBURL {
            try? FileManager.default.removeItem(at: tempDBURL.deletingLastPathComponent())
        }
        try super.tearDownWithError()
    }

    func testRecordAndQuerySamples() throws {
        let now = Date()
        store.recordSample(TelemetrySampleRecord(
            timestamp: now.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(now),
            eventType: "probe",
            connectionState: "good",
            healthScore: 98,
            ratingLabel: "Excellent",
            pingLatencyMs: 14.5,
            jitterMs: 2.1,
            packetLossPct: 0.0,
            pingTarget: "1.1.1.1",
            httpLatencyMs: 28.4,
            httpEndpoint: "https://cloudflare.com/cdn-cgi/trace",
            downloadSpeedMbps: nil,
            bytesTransferred: nil,
            isICMPBlocked: false,
            connectionType: "Wi-Fi",
            interfaceName: "en0",
            wifiSSID: "HomeNetwork_5G",
            isExpensive: false,
            isConstrained: false,
            reasons: nil
        ))

        let later = now.addingTimeInterval(5)
        store.recordSample(TelemetrySampleRecord(
            timestamp: later.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(later),
            eventType: "speed_test",
            connectionState: "good",
            healthScore: 99,
            ratingLabel: "Excellent",
            pingLatencyMs: 15.0,
            jitterMs: 1.8,
            packetLossPct: 0.0,
            pingTarget: "1.1.1.1",
            httpLatencyMs: 26.0,
            httpEndpoint: "https://cloudflare.com/cdn-cgi/trace",
            downloadSpeedMbps: 342.5,
            bytesTransferred: 25_000_000,
            isICMPBlocked: false,
            connectionType: "Wi-Fi",
            interfaceName: "en0",
            wifiSSID: "HomeNetwork_5G",
            isExpensive: false,
            isConstrained: false,
            reasons: nil
        ))

        let samples = store.querySamples(limit: 10)
        XCTAssertEqual(samples.count, 2)

        let speedTests = store.querySamples(limit: 10, eventTypeFilter: "speed_test")
        XCTAssertEqual(speedTests.count, 1)
        XCTAssertEqual(speedTests.first?.downloadSpeedMbps, 342.5)
        XCTAssertEqual(speedTests.first?.wifiSSID, "HomeNetwork_5G")
        XCTAssertEqual(speedTests.first?.connectionType, "Wi-Fi")
    }

    func testRecordAndQueryLifecycleEvents() throws {
        let now = Date()
        store.recordLifecycleEvent(LifecycleEventRecord(
            timestamp: now.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(now),
            eventType: "app_start",
            previousState: nil,
            newState: "good",
            connectionType: "Wi-Fi",
            interfaceName: "en0",
            wifiSSID: "OfficeWiFi",
            isExpensive: false,
            details: "App launched"
        ))

        let later = now.addingTimeInterval(10)
        store.recordLifecycleEvent(LifecycleEventRecord(
            timestamp: later.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(later),
            eventType: "state_change",
            previousState: "good",
            newState: "degraded",
            connectionType: "Wi-Fi (Hotspot/Tether)",
            interfaceName: "en0",
            wifiSSID: "iPhone Hotspot",
            isExpensive: true,
            details: "High packet loss detected"
        ))

        let events = store.queryLifecycleEvents(limit: 10)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.eventType, "state_change")
        XCTAssertEqual(events.first?.wifiSSID, "iPhone Hotspot")
        XCTAssertEqual(events.first?.isExpensive, true)
    }

    func testComputeSummaryAndBreakdown() throws {
        let now = Date()
        let t1 = now.addingTimeInterval(-120)
        let t2 = now.addingTimeInterval(-60)

        store.recordSample(TelemetrySampleRecord(
            timestamp: t1.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(t1),
            eventType: "probe",
            connectionState: "good",
            healthScore: 99,
            ratingLabel: "Excellent",
            pingLatencyMs: 12.0,
            jitterMs: 1.0,
            packetLossPct: 0.0,
            pingTarget: "1.1.1.1",
            httpLatencyMs: 25.0,
            httpEndpoint: "https://1.1.1.1",
            downloadSpeedMbps: nil,
            bytesTransferred: nil,
            isICMPBlocked: false,
            connectionType: "Wi-Fi",
            interfaceName: "en0",
            wifiSSID: "HomeWiFi",
            isExpensive: false,
            isConstrained: false,
            reasons: nil
        ))

        store.recordSample(TelemetrySampleRecord(
            timestamp: t2.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(t2),
            eventType: "probe",
            connectionState: "disconnected",
            healthScore: 0,
            ratingLabel: "Disconnected",
            pingLatencyMs: nil,
            jitterMs: 0.0,
            packetLossPct: 100.0,
            pingTarget: "1.1.1.1",
            httpLatencyMs: nil,
            httpEndpoint: nil,
            downloadSpeedMbps: nil,
            bytesTransferred: nil,
            isICMPBlocked: false,
            connectionType: "Wi-Fi",
            interfaceName: "en0",
            wifiSSID: "HomeWiFi",
            isExpensive: false,
            isConstrained: false,
            reasons: "Ping failed; HTTP unreachable"
        ))

        let summary = store.computeSummary(sinceTimestamp: now.addingTimeInterval(-300).timeIntervalSince1970, windowDescription: "Last 5m")
        XCTAssertEqual(summary.totalProbeSamples, 2)
        XCTAssertEqual(summary.goodSamples, 1)
        XCTAssertEqual(summary.disconnectedSamples, 1)
        XCTAssertEqual(summary.breakdownByConnection.first?.wifiSSID, "HomeWiFi")
    }

    func testPruneOldRecords() throws {
        let nineDaysAgo = Date().addingTimeInterval(-9 * 86400)
        let oneDayAgo = Date().addingTimeInterval(-1 * 86400)

        store.recordSample(TelemetrySampleRecord(
            timestamp: nineDaysAgo.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(nineDaysAgo),
            eventType: "probe",
            connectionState: "good",
            healthScore: 100,
            ratingLabel: "Excellent",
            pingLatencyMs: 10.0,
            jitterMs: 1.0,
            packetLossPct: 0.0,
            pingTarget: "1.1.1.1",
            httpLatencyMs: 20.0,
            httpEndpoint: nil,
            downloadSpeedMbps: nil,
            bytesTransferred: nil,
            isICMPBlocked: false,
            connectionType: "Ethernet",
            interfaceName: "en1",
            wifiSSID: nil,
            isExpensive: false,
            isConstrained: false,
            reasons: nil
        ))

        store.recordSample(TelemetrySampleRecord(
            timestamp: oneDayAgo.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(oneDayAgo),
            eventType: "probe",
            connectionState: "good",
            healthScore: 98,
            ratingLabel: "Excellent",
            pingLatencyMs: 12.0,
            jitterMs: 1.5,
            packetLossPct: 0.0,
            pingTarget: "1.1.1.1",
            httpLatencyMs: 22.0,
            httpEndpoint: nil,
            downloadSpeedMbps: nil,
            bytesTransferred: nil,
            isICMPBlocked: false,
            connectionType: "Wi-Fi",
            interfaceName: "en0",
            wifiSSID: "MyWiFi",
            isExpensive: false,
            isConstrained: false,
            reasons: nil
        ))

        XCTAssertEqual(store.totalRecordCounts().samples, 2)
        store.pruneOldRecords(olderThanDays: 7)
        XCTAssertEqual(store.totalRecordCounts().samples, 1)

        let remaining = store.querySamples(limit: 10)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.wifiSSID, "MyWiFi")
    }

    func testReadOnlySQLQueryAndSkillGenerator() throws {
        let now = Date()
        store.recordSample(TelemetrySampleRecord(
            timestamp: now.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(now),
            eventType: "probe",
            connectionState: "good",
            healthScore: 99,
            ratingLabel: "Excellent",
            pingLatencyMs: 11.2,
            jitterMs: 0.9,
            packetLossPct: 0.0,
            pingTarget: "1.1.1.1",
            httpLatencyMs: 19.5,
            httpEndpoint: nil,
            downloadSpeedMbps: nil,
            bytesTransferred: nil,
            isICMPBlocked: false,
            connectionType: "Wi-Fi",
            interfaceName: "en0",
            wifiSSID: "Studio5G",
            isExpensive: false,
            isConstrained: false,
            reasons: nil
        ))

        let rows = try store.executeReadOnlySQL("SELECT connection_state, wifi_ssid FROM telemetry_samples")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["wifi_ssid"] as? String, "Studio5G")

        XCTAssertThrowsError(try store.executeReadOnlySQL("DROP TABLE telemetry_samples"))

        let skillMarkdown = AgentSkillGenerator.generateSkillMarkdown(cliPath: "/usr/local/bin/connection-watch")
        XCTAssertTrue(skillMarkdown.contains("connection-watch"))
        XCTAssertTrue(skillMarkdown.contains("telemetry.sqlite"))
        XCTAssertTrue(skillMarkdown.contains("Connection Watch.app"))
    }
}
