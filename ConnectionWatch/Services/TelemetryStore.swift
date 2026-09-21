import Foundation
import SQLite3

// MARK: - Data Models

public struct TelemetrySampleRecord: Codable, Sendable {
    public let id: Int64
    public let timestamp: Double
    public let isoTimestamp: String
    public let eventType: String          // "probe" or "speed_test"
    public let connectionState: String    // "good", "degraded", "disconnected", "paused"
    public let healthScore: Int
    public let ratingLabel: String
    public let pingLatencyMs: Double?
    public let jitterMs: Double?
    public let packetLossPct: Double?
    public let pingTarget: String?
    public let httpLatencyMs: Double?
    public let httpEndpoint: String?
    public let downloadSpeedMbps: Double?
    public let bytesTransferred: Int?
    public let isICMPBlocked: Bool
    public let connectionType: String     // e.g. "Wi-Fi", "Wi-Fi (Hotspot/Tether)", "Ethernet", "Cellular", "VPN / Other", "Offline"
    public let interfaceName: String?     // e.g. "en0"
    public let wifiSSID: String?          // e.g. "HomeNet-5G"
    public let isExpensive: Bool          // true on Hotspot/Tether or Cellular
    public let isConstrained: Bool        // true on Low Data Mode
    public let reasons: String?

    public init(
        id: Int64 = 0,
        timestamp: Double,
        isoTimestamp: String,
        eventType: String,
        connectionState: String,
        healthScore: Int,
        ratingLabel: String,
        pingLatencyMs: Double?,
        jitterMs: Double?,
        packetLossPct: Double?,
        pingTarget: String?,
        httpLatencyMs: Double?,
        httpEndpoint: String?,
        downloadSpeedMbps: Double?,
        bytesTransferred: Int?,
        isICMPBlocked: Bool,
        connectionType: String,
        interfaceName: String?,
        wifiSSID: String?,
        isExpensive: Bool,
        isConstrained: Bool,
        reasons: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.isoTimestamp = isoTimestamp
        self.eventType = eventType
        self.connectionState = connectionState
        self.healthScore = healthScore
        self.ratingLabel = ratingLabel
        self.pingLatencyMs = pingLatencyMs
        self.jitterMs = jitterMs
        self.packetLossPct = packetLossPct
        self.pingTarget = pingTarget
        self.httpLatencyMs = httpLatencyMs
        self.httpEndpoint = httpEndpoint
        self.downloadSpeedMbps = downloadSpeedMbps
        self.bytesTransferred = bytesTransferred
        self.isICMPBlocked = isICMPBlocked
        self.connectionType = connectionType
        self.interfaceName = interfaceName
        self.wifiSSID = wifiSSID
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.reasons = reasons
    }
}

public struct LifecycleEventRecord: Codable, Sendable {
    public let id: Int64
    public let timestamp: Double
    public let isoTimestamp: String
    public let eventType: String          // "app_start", "app_stop", "monitoring_pause", "monitoring_resume", "state_change", "network_change"
    public let previousState: String?
    public let newState: String?
    public let connectionType: String?
    public let interfaceName: String?
    public let wifiSSID: String?
    public let isExpensive: Bool
    public let details: String?

    public init(
        id: Int64 = 0,
        timestamp: Double,
        isoTimestamp: String,
        eventType: String,
        previousState: String? = nil,
        newState: String? = nil,
        connectionType: String? = nil,
        interfaceName: String? = nil,
        wifiSSID: String? = nil,
        isExpensive: Bool = false,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.isoTimestamp = isoTimestamp
        self.eventType = eventType
        self.previousState = previousState
        self.newState = newState
        self.connectionType = connectionType
        self.interfaceName = interfaceName
        self.wifiSSID = wifiSSID
        self.isExpensive = isExpensive
        self.details = details
    }
}

public struct LatestStatusSnapshot: Codable, Sendable {
    public let updatedAt: String
    public let timestamp: Double
    public let appVersion: String
    public let connectionState: String
    public let healthScore: Int
    public let ratingLabel: String
    public let connectionType: String
    public let interfaceName: String?
    public let wifiSSID: String?
    public let isExpensive: Bool
    public let isConstrained: Bool
    public let pingLatencyMs: Double?
    public let jitterMs: Double?
    public let packetLossPct: Double
    public let pingTarget: String
    public let httpLatencyMs: Double?
    public let httpEndpoint: String?
    public let latestDownloadSpeedMbps: Double?
    public let latestSpeedTestDate: String?
    public let isICMPBlocked: Bool
    public let reasons: [String]
    public let databasePath: String
    public let cliExecutablePath: String
}

public struct ConnectionBreakdown: Codable, Sendable {
    public let connectionType: String
    public let wifiSSID: String?
    public let sampleCount: Int
    public let avgPingMs: Double?
    public let avgHttpMs: Double?
    public let avgLossPct: Double?
    public let avgDownloadMbps: Double?
}

public struct TelemetrySummaryReport: Codable, Sendable {
    public let windowDescription: String
    public let startTimeISO: String?
    public let endTimeISO: String?
    public let totalProbeSamples: Int
    public let goodSamples: Int
    public let degradedSamples: Int
    public let disconnectedSamples: Int
    public let uptimePercentage: Double
    public let healthyPercentage: Double
    public let avgPingMs: Double?
    public let minPingMs: Double?
    public let maxPingMs: Double?
    public let p50PingMs: Double?
    public let p95PingMs: Double?
    public let avgJitterMs: Double?
    public let avgPacketLossPct: Double?
    public let avgHttpMs: Double?
    public let minHttpMs: Double?
    public let maxHttpMs: Double?
    public let p95HttpMs: Double?
    public let speedTestCount: Int
    public let avgDownloadMbps: Double?
    public let maxDownloadMbps: Double?
    public let minDownloadMbps: Double?
    public let outageEventCount: Int
    public let degradationEventCount: Int
    public let appStartCount: Int
    public let appStopCount: Int
    public let breakdownByConnection: [ConnectionBreakdown]
}

// MARK: - TelemetryStore

public final class TelemetryStore: @unchecked Sendable {
    public static let shared = TelemetryStore()

    public static var storageDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("ConnectionWatch", isDirectory: true)
    }

    public static var databaseURL: URL {
        storageDirectoryURL.appendingPathComponent("telemetry.sqlite")
    }

    public static var latestStatusURL: URL {
        storageDirectoryURL.appendingPathComponent("latest_status.json")
    }

    public static var installedCLISymlinkURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/connection-watch")
    }

    private let lock = NSLock()
    private var db: OpaquePointer?
    private var insertCountSincePrune = 0

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    public static func formatISO(_ date: Date = Date()) -> String {
        isoFormatter.string(from: date)
    }

    public init(customDatabasePath: String? = nil) {
        openDatabase(path: customDatabasePath ?? Self.databaseURL.path)
    }

    deinit {
        lock.lock()
        if let db {
            sqlite3_close(db)
        }
        lock.unlock()
    }

    private func openDatabase(path: String) {
        lock.lock()
        defer { lock.unlock() }

        let dirURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle {
            self.db = handle
            sqlite3_busy_timeout(handle, 5000)
            execSQL(handle, "PRAGMA journal_mode=WAL;")
            execSQL(handle, "PRAGMA synchronous=NORMAL;")
            createTablesIfNeeded(handle)
        }
    }

    private func execSQL(_ handle: OpaquePointer, _ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg {
                sqlite3_free(errMsg)
            }
        }
    }

    private func createTablesIfNeeded(_ handle: OpaquePointer) {
        let createSamplesSQL = """
        CREATE TABLE IF NOT EXISTS telemetry_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            iso_timestamp TEXT NOT NULL,
            event_type TEXT NOT NULL,
            connection_state TEXT NOT NULL,
            health_score INTEGER NOT NULL,
            rating_label TEXT NOT NULL,
            ping_latency_ms REAL,
            jitter_ms REAL,
            packet_loss_pct REAL,
            ping_target TEXT,
            http_latency_ms REAL,
            http_endpoint TEXT,
            download_speed_mbps REAL,
            bytes_transferred INTEGER,
            is_icmp_blocked INTEGER NOT NULL DEFAULT 0,
            connection_type TEXT NOT NULL,
            interface_name TEXT,
            wifi_ssid TEXT,
            is_expensive INTEGER NOT NULL DEFAULT 0,
            is_constrained INTEGER NOT NULL DEFAULT 0,
            reasons TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_samples_timestamp ON telemetry_samples(timestamp);
        CREATE INDEX IF NOT EXISTS idx_samples_state ON telemetry_samples(connection_state);
        CREATE INDEX IF NOT EXISTS idx_samples_type ON telemetry_samples(event_type);
        """

        let createLifecycleSQL = """
        CREATE TABLE IF NOT EXISTS lifecycle_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            iso_timestamp TEXT NOT NULL,
            event_type TEXT NOT NULL,
            previous_state TEXT,
            new_state TEXT,
            connection_type TEXT,
            interface_name TEXT,
            wifi_ssid TEXT,
            is_expensive INTEGER NOT NULL DEFAULT 0,
            details TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_lifecycle_timestamp ON lifecycle_events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_lifecycle_type ON lifecycle_events(event_type);
        """

        execSQL(handle, createSamplesSQL)
        execSQL(handle, createLifecycleSQL)
    }

    // MARK: - Write Operations

    public func recordSample(_ sample: TelemetrySampleRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        let sql = """
        INSERT INTO telemetry_samples (
            timestamp, iso_timestamp, event_type, connection_state, health_score, rating_label,
            ping_latency_ms, jitter_ms, packet_loss_pct, ping_target,
            http_latency_ms, http_endpoint, download_speed_mbps, bytes_transferred,
            is_icmp_blocked, connection_type, interface_name, wifi_ssid,
            is_expensive, is_constrained, reasons
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, sample.timestamp)
            bindText(stmt, 2, sample.isoTimestamp)
            bindText(stmt, 3, sample.eventType)
            bindText(stmt, 4, sample.connectionState)
            sqlite3_bind_int(stmt, 5, Int32(sample.healthScore))
            bindText(stmt, 6, sample.ratingLabel)
            bindOptionalDouble(stmt, 7, sample.pingLatencyMs)
            bindOptionalDouble(stmt, 8, sample.jitterMs)
            bindOptionalDouble(stmt, 9, sample.packetLossPct)
            bindOptionalText(stmt, 10, sample.pingTarget)
            bindOptionalDouble(stmt, 11, sample.httpLatencyMs)
            bindOptionalText(stmt, 12, sample.httpEndpoint)
            bindOptionalDouble(stmt, 13, sample.downloadSpeedMbps)
            bindOptionalInt(stmt, 14, sample.bytesTransferred)
            sqlite3_bind_int(stmt, 15, sample.isICMPBlocked ? 1 : 0)
            bindText(stmt, 16, sample.connectionType)
            bindOptionalText(stmt, 17, sample.interfaceName)
            bindOptionalText(stmt, 18, sample.wifiSSID)
            sqlite3_bind_int(stmt, 19, sample.isExpensive ? 1 : 0)
            sqlite3_bind_int(stmt, 20, sample.isConstrained ? 1 : 0)
            bindOptionalText(stmt, 21, sample.reasons)

            sqlite3_step(stmt)
        }

        insertCountSincePrune += 1
        if insertCountSincePrune >= 60 {
            insertCountSincePrune = 0
            pruneOldRecordsLocked(olderThanDays: 7)
        }
    }

    public func recordLifecycleEvent(_ event: LifecycleEventRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        let sql = """
        INSERT INTO lifecycle_events (
            timestamp, iso_timestamp, event_type, previous_state, new_state,
            connection_type, interface_name, wifi_ssid, is_expensive, details
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, event.timestamp)
            bindText(stmt, 2, event.isoTimestamp)
            bindText(stmt, 3, event.eventType)
            bindOptionalText(stmt, 4, event.previousState)
            bindOptionalText(stmt, 5, event.newState)
            bindOptionalText(stmt, 6, event.connectionType)
            bindOptionalText(stmt, 7, event.interfaceName)
            bindOptionalText(stmt, 8, event.wifiSSID)
            sqlite3_bind_int(stmt, 9, event.isExpensive ? 1 : 0)
            bindOptionalText(stmt, 10, event.details)

            sqlite3_step(stmt)
        }
    }

    public func writeLatestStatus(_ snapshot: LatestStatusSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: Self.latestStatusURL, options: .atomic)
        }
    }

    public func readLatestStatus() -> LatestStatusSnapshot? {
        guard let data = try? Data(contentsOf: Self.latestStatusURL) else { return nil }
        return try? JSONDecoder().decode(LatestStatusSnapshot.self, from: data)
    }

    public func pruneOldRecords(olderThanDays: Int = 7) {
        lock.lock()
        defer { lock.unlock() }
        pruneOldRecordsLocked(olderThanDays: olderThanDays)
    }

    private func pruneOldRecordsLocked(olderThanDays: Int) {
        guard let db else { return }
        let cutoff = Date().timeIntervalSince1970 - Double(olderThanDays * 86400)
        let sql1 = "DELETE FROM telemetry_samples WHERE timestamp < \(cutoff);"
        let sql2 = "DELETE FROM lifecycle_events WHERE timestamp < \(cutoff);"
        execSQL(db, sql1)
        execSQL(db, sql2)
    }

    // MARK: - Query Operations

    public func querySamples(
        sinceTimestamp: Double? = nil,
        limit: Int = 100,
        stateFilter: String? = nil,
        minLatency: Double? = nil,
        lossOnly: Bool = false,
        eventTypeFilter: String? = nil,
        interfaceFilter: String? = nil,
        ssidFilter: String? = nil
    ) -> [TelemetrySampleRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        var clauses: [String] = []
        if let since = sinceTimestamp {
            clauses.append("timestamp >= \(since)")
        }
        if let state = stateFilter, !state.isEmpty {
            clauses.append("LOWER(connection_state) = LOWER('\(escapeSQL(state))')")
        }
        if let minLat = minLatency {
            clauses.append("(ping_latency_ms >= \(minLat) OR http_latency_ms >= \(minLat))")
        }
        if lossOnly {
            clauses.append("packet_loss_pct > 0")
        }
        if let evType = eventTypeFilter, !evType.isEmpty {
            clauses.append("LOWER(event_type) = LOWER('\(escapeSQL(evType))')")
        }
        if let iface = interfaceFilter, !iface.isEmpty {
            clauses.append("LOWER(connection_type) LIKE '%\(escapeSQL(iface.lowercased()))%'")
        }
        if let ssid = ssidFilter, !ssid.isEmpty {
            clauses.append("LOWER(wifi_ssid) LIKE '%\(escapeSQL(ssid.lowercased()))%'")
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let limitClause = limit > 0 ? "LIMIT \(limit)" : ""
        let sql = "SELECT * FROM telemetry_samples \(whereClause) ORDER BY timestamp DESC \(limitClause);"

        var results: [TelemetrySampleRecord] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(readSampleRow(stmt))
            }
        }
        return results
    }

    public func queryLifecycleEvents(
        sinceTimestamp: Double? = nil,
        limit: Int = 100,
        eventTypeFilter: String? = nil
    ) -> [LifecycleEventRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        var clauses: [String] = []
        if let since = sinceTimestamp {
            clauses.append("timestamp >= \(since)")
        }
        if let evType = eventTypeFilter, !evType.isEmpty {
            clauses.append("LOWER(event_type) = LOWER('\(escapeSQL(evType))')")
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let limitClause = limit > 0 ? "LIMIT \(limit)" : ""
        let sql = "SELECT * FROM lifecycle_events \(whereClause) ORDER BY timestamp DESC \(limitClause);"

        var results: [LifecycleEventRecord] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(readLifecycleRow(stmt))
            }
        }
        return results
    }

    public func computeSummary(
        sinceTimestamp: Double?,
        windowDescription: String,
        interfaceFilter: String? = nil,
        ssidFilter: String? = nil
    ) -> TelemetrySummaryReport {
        let samples = querySamples(
            sinceTimestamp: sinceTimestamp,
            limit: 0,
            interfaceFilter: interfaceFilter,
            ssidFilter: ssidFilter
        )
        let lifecycle = queryLifecycleEvents(sinceTimestamp: sinceTimestamp, limit: 0)

        let probes = samples.filter { $0.eventType == "probe" }
        let speedTests = samples.filter { $0.eventType == "speed_test" && $0.downloadSpeedMbps != nil }

        let totalProbes = probes.count
        let goodCount = probes.filter { $0.connectionState == "good" }.count
        let degradedCount = probes.filter { $0.connectionState == "degraded" }.count
        let disconnectedCount = probes.filter { $0.connectionState == "disconnected" }.count

        let uptimePct = totalProbes > 0 ? Double(totalProbes - disconnectedCount) / Double(totalProbes) * 100.0 : 100.0
        let healthyPct = totalProbes > 0 ? Double(goodCount) / Double(totalProbes) * 100.0 : 100.0

        let pingLatencies = probes.compactMap(\.pingLatencyMs).sorted()
        let httpLatencies = probes.compactMap(\.httpLatencyMs).sorted()
        let jitters = probes.compactMap(\.jitterMs)
        let losses = probes.compactMap(\.packetLossPct)
        let speeds = speedTests.compactMap(\.downloadSpeedMbps).sorted()

        let startTimeISO = samples.last?.isoTimestamp ?? lifecycle.last?.isoTimestamp
        let endTimeISO = samples.first?.isoTimestamp ?? lifecycle.first?.isoTimestamp

        let outageEvents = lifecycle.filter {
            $0.eventType == "state_change" && $0.newState == "disconnected"
        }.count
        let degradationEvents = lifecycle.filter {
            $0.eventType == "state_change" && $0.newState == "degraded"
        }.count
        let appStarts = lifecycle.filter { $0.eventType == "app_start" }.count
        let appStops = lifecycle.filter { $0.eventType == "app_stop" }.count

        // Group breakdown by (connectionType, wifiSSID)
        var groups: [String: [TelemetrySampleRecord]] = [:]
        for s in samples {
            let key = "\(s.connectionType)|\(s.wifiSSID ?? "")"
            groups[key, default: []].append(s)
        }

        let breakdowns: [ConnectionBreakdown] = groups.values.compactMap { groupSamples in
            guard let first = groupSamples.first else { return nil }
            let gProbes = groupSamples.filter { $0.eventType == "probe" }
            let gSpeeds = groupSamples.filter { $0.eventType == "speed_test" }.compactMap(\.downloadSpeedMbps)
            let gPings = gProbes.compactMap(\.pingLatencyMs)
            let gHttps = gProbes.compactMap(\.httpLatencyMs)
            let gLosses = gProbes.compactMap(\.packetLossPct)
            return ConnectionBreakdown(
                connectionType: first.connectionType,
                wifiSSID: first.wifiSSID,
                sampleCount: groupSamples.count,
                avgPingMs: average(gPings),
                avgHttpMs: average(gHttps),
                avgLossPct: average(gLosses),
                avgDownloadMbps: average(gSpeeds)
            )
        }.sorted { $0.sampleCount > $1.sampleCount }

        return TelemetrySummaryReport(
            windowDescription: windowDescription,
            startTimeISO: startTimeISO,
            endTimeISO: endTimeISO,
            totalProbeSamples: totalProbes,
            goodSamples: goodCount,
            degradedSamples: degradedCount,
            disconnectedSamples: disconnectedCount,
            uptimePercentage: uptimePct,
            healthyPercentage: healthyPct,
            avgPingMs: average(pingLatencies),
            minPingMs: pingLatencies.first,
            maxPingMs: pingLatencies.last,
            p50PingMs: percentile(pingLatencies, 0.50),
            p95PingMs: percentile(pingLatencies, 0.95),
            avgJitterMs: average(jitters),
            avgPacketLossPct: average(losses),
            avgHttpMs: average(httpLatencies),
            minHttpMs: httpLatencies.first,
            maxHttpMs: httpLatencies.last,
            p95HttpMs: percentile(httpLatencies, 0.95),
            speedTestCount: speedTests.count,
            avgDownloadMbps: average(speeds),
            maxDownloadMbps: speeds.last,
            minDownloadMbps: speeds.first,
            outageEventCount: outageEvents,
            degradationEventCount: degradationEvents,
            appStartCount: appStarts,
            appStopCount: appStops,
            breakdownByConnection: breakdowns
        )
    }

    public func executeReadOnlySQL(_ sql: String) throws -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else {
            throw NSError(domain: "TelemetryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not open"])
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "TelemetryStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "SQL Error: \(msg)"])
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_stmt_readonly(stmt) != 0 else {
            throw NSError(domain: "TelemetryStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only read-only SELECT/PRAGMA queries are permitted via CLI"])
        }

        var rows: [[String: Any]] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<colCount {
                let colName = String(cString: sqlite3_column_name(stmt, i))
                let colType = sqlite3_column_type(stmt, i)
                switch colType {
                case SQLITE_INTEGER:
                    row[colName] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[colName] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    if let cStr = sqlite3_column_text(stmt, i) {
                        row[colName] = String(cString: cStr)
                    }
                case SQLITE_NULL:
                    row[colName] = NSNull()
                default:
                    if let cStr = sqlite3_column_text(stmt, i) {
                        row[colName] = String(cString: cStr)
                    }
                }
            }
            rows.append(row)
        }
        return rows
    }

    public func totalRecordCounts() -> (samples: Int, lifecycle: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return (0, 0) }
        return (
            scalarInt(db, "SELECT COUNT(*) FROM telemetry_samples;"),
            scalarInt(db, "SELECT COUNT(*) FROM lifecycle_events;")
        )
    }

    // MARK: - Helpers

    private func scalarInt(_ db: OpaquePointer, _ sql: String) -> Int {
        var stmt: OpaquePointer?
        var result = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = Int(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }
        return result
    }

    private func readSampleRow(_ stmt: OpaquePointer) -> TelemetrySampleRecord {
        let id = sqlite3_column_int64(stmt, 0)
        let timestamp = sqlite3_column_double(stmt, 1)
        let isoTimestamp = columnText(stmt, 2) ?? ""
        let eventType = columnText(stmt, 3) ?? "probe"
        let connectionState = columnText(stmt, 4) ?? "good"
        let healthScore = Int(sqlite3_column_int(stmt, 5))
        let ratingLabel = columnText(stmt, 6) ?? "Good"
        let pingLatencyMs = columnOptionalDouble(stmt, 7)
        let jitterMs = columnOptionalDouble(stmt, 8)
        let packetLossPct = columnOptionalDouble(stmt, 9)
        let pingTarget = columnText(stmt, 10)
        let httpLatencyMs = columnOptionalDouble(stmt, 11)
        let httpEndpoint = columnText(stmt, 12)
        let downloadSpeedMbps = columnOptionalDouble(stmt, 13)
        let bytesTransferred = columnOptionalInt(stmt, 14)
        let isICMPBlocked = sqlite3_column_int(stmt, 15) != 0
        let connectionType = columnText(stmt, 16) ?? "Network"
        let interfaceName = columnText(stmt, 17)
        let wifiSSID = columnText(stmt, 18)
        let isExpensive = sqlite3_column_int(stmt, 19) != 0
        let isConstrained = sqlite3_column_int(stmt, 20) != 0
        let reasons = columnText(stmt, 21)

        return TelemetrySampleRecord(
            id: id,
            timestamp: timestamp,
            isoTimestamp: isoTimestamp,
            eventType: eventType,
            connectionState: connectionState,
            healthScore: healthScore,
            ratingLabel: ratingLabel,
            pingLatencyMs: pingLatencyMs,
            jitterMs: jitterMs,
            packetLossPct: packetLossPct,
            pingTarget: pingTarget,
            httpLatencyMs: httpLatencyMs,
            httpEndpoint: httpEndpoint,
            downloadSpeedMbps: downloadSpeedMbps,
            bytesTransferred: bytesTransferred,
            isICMPBlocked: isICMPBlocked,
            connectionType: connectionType,
            interfaceName: interfaceName,
            wifiSSID: wifiSSID,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            reasons: reasons
        )
    }

    private func readLifecycleRow(_ stmt: OpaquePointer) -> LifecycleEventRecord {
        let id = sqlite3_column_int64(stmt, 0)
        let timestamp = sqlite3_column_double(stmt, 1)
        let isoTimestamp = columnText(stmt, 2) ?? ""
        let eventType = columnText(stmt, 3) ?? ""
        let previousState = columnText(stmt, 4)
        let newState = columnText(stmt, 5)
        let connectionType = columnText(stmt, 6)
        let interfaceName = columnText(stmt, 7)
        let wifiSSID = columnText(stmt, 8)
        let isExpensive = sqlite3_column_int(stmt, 9) != 0
        let details = columnText(stmt, 10)

        return LifecycleEventRecord(
            id: id,
            timestamp: timestamp,
            isoTimestamp: isoTimestamp,
            eventType: eventType,
            previousState: previousState,
            newState: newState,
            connectionType: connectionType,
            interfaceName: interfaceName,
            wifiSSID: wifiSSID,
            isExpensive: isExpensive,
            details: details
        )
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            bindText(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value, value.isFinite {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalInt(_ stmt: OpaquePointer, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cStr)
    }

    private func columnOptionalDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func columnOptionalInt(_ stmt: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, index))
    }

    private func escapeSQL(_ input: String) -> String {
        input.replacingOccurrences(of: "'", with: "''")
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func percentile(_ sortedValues: [Double], _ p: Double) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let idx = min(sortedValues.count - 1, max(0, Int(Double(sortedValues.count - 1) * p)))
        return sortedValues[idx]
    }
}

// MARK: - Agent Skill Markdown Generator

public enum AgentSkillGenerator {
    public static func generateSkillMarkdown(cliPath: String) -> String {
        let dbPath = TelemetryStore.databaseURL.path
        let statusPath = TelemetryStore.latestStatusURL.path
        let symlinkPath = TelemetryStore.installedCLISymlinkURL.path

        return """
        ---
        name: connection-watch
        description: Query and analyze 7 days of macOS network health telemetry (ping latency, jitter, packet loss, HTTP probes, download speed tests, Wi-Fi SSID, Hotspot/Tether detection, and app/connection lifecycle events) captured by Connection Watch.app.
        ---

        # Connection Watch (`connection-watch`) — AI Agent Skill

        ## Overview & Parent Application
        `connection-watch` is the companion CLI utility for **Connection Watch.app**, a native macOS menu bar network health monitor.
        Connection Watch continuously monitors internet quality in the background using lightweight ICMP ping bursts, HTTP connectivity probes, network interface handoff listeners, and on-demand multi-stage Cloudflare download speed benchmarks. All telemetry is persisted locally for a rolling **7-day window** in a WAL-mode SQLite database.

        Since v1.4.2, HTTP latency includes DNS lookup, connection setup, and fallback attempts. Older retained samples may contain response-only timings, so comparisons across this upgrade need that context.

        Use this tool whenever the user asks you to:
        - Diagnose recent internet drops, lag spikes, packet loss, or high jitter (e.g., *"Why did my call lag 10 minutes ago?"* or *"How many outages did I have today?"*)
        - Compare network performance across different interfaces or Wi-Fi networks (e.g., *"Is my Hotspot faster/more stable than Office Wi-Fi?"*)
        - Inspect download speed test history or check when Connection Watch was running/paused.

        ---

        ## Locations on This Machine
        - **CLI Executable (Primary)**: `\(cliPath)`
        - **CLI Symlink (`~/.local/bin`)**: `\(symlinkPath)`
        - **SQLite Telemetry Database (7-day rolling)**: `\(dbPath)`
        - **Live Status Snapshot (JSON)**: `\(statusPath)`

        *(Tip: You can invoke the CLI directly via `"\(cliPath)"` or `\(symlinkPath)`.)*

        ---

        ## CLI Command Reference

        ### 1. Current Live Status & Overview
        ```bash
        "\(cliPath)" status
        "\(cliPath)" status --json
        ```
        Returns current connection state (`good`, `degraded`, `disconnected`, `paused`), health score (0-100), active interface (`Wi-Fi`, `Wi-Fi (Hotspot/Tether)`, `Ethernet`, `Cellular`, `VPN / Other`), Wi-Fi SSID (if available), latest ping/jitter/loss, HTTP latency, and last speed test.

        ### 2. Statistical Summary & Interface/SSID Comparison
        ```bash
        # Summary over a time window (supports 1h, 6h, 12h, 24h, 3d, 7d, all)
        "\(cliPath)" summary --since 24h
        "\(cliPath)" summary --since 7d --json

        # Filter summary by interface type or Wi-Fi SSID
        "\(cliPath)" summary --since 7d --interface "Hotspot"
        "\(cliPath)" summary --since 7d --ssid "HomeNet"
        ```
        Computes uptime %, healthy %, Ping & HTTP latency percentiles (Avg, Min, Max, P50, P95), packet loss %, speed benchmark stats, outage/degradation counts, and a **per-connection breakdown table** comparing every Wi-Fi SSID, Hotspot/Tether, and Ethernet connection used during the window.

        ### 3. Outages & Degraded Incidents
        ```bash
        "\(cliPath)" outages --since 24h
        "\(cliPath)" outages --since 7d --json
        ```
        Lists all degraded or disconnected probe samples and state transitions so you can pinpoint exact timestamps and diagnostic causes (e.g., `High ping`, `Packet loss`, `Slow HTTP`, `Connection unreachable`).

        ### 4. Raw Probe Samples (Ping / HTTP / Loss Filtering)
        ```bash
        # Recent 30 probe samples
        "\(cliPath)" samples --limit 30

        # Filter for high latency (>100ms) or samples with packet loss
        "\(cliPath)" samples --since 6h --min-latency 100 --json
        "\(cliPath)" samples --since 24h --loss-only
        ```

        ### 5. Download Speed Benchmarks
        ```bash
        "\(cliPath)" speedtests --since 7d
        "\(cliPath)" speedtests --json
        ```
        Lists all on-demand speed tests run by the user, including Mbps throughput, TTFB latency, MB transferred, connection type (e.g. Wi-Fi vs. Tether), and Wi-Fi SSID.

        ### 6. App Start/Stop & Network Handoff Lifecycle Events
        ```bash
        "\(cliPath)" lifecycle --since 7d
        "\(cliPath)" lifecycle --json
        ```
        Lists app launches (`app_start`), terminations (`app_stop`), monitoring pause/resume events, state changes (`good -> degraded -> disconnected`), and network interface switches (`Wi-Fi -> Wi-Fi (Hotspot/Tether)`).

        ### 7. Direct Read-Only SQL Queries
        You can execute arbitrary read-only `SELECT` SQL queries against the SQLite database:
        ```bash
        "\(cliPath)" sql "SELECT datetime(timestamp, 'unixepoch', 'localtime') AS time, connection_type, wifi_ssid, ping_latency_ms, packet_loss_pct, http_latency_ms, reasons FROM telemetry_samples WHERE packet_loss_pct > 0 ORDER BY timestamp DESC LIMIT 20;" --json
        ```

        ---

        ## SQLite Database Schema
        - **Table `telemetry_samples`**:
          `id`, `timestamp` (epoch sec), `iso_timestamp`, `event_type` (`'probe'` | `'speed_test'`), `connection_state` (`'good'` | `'degraded'` | `'disconnected'`), `health_score` (0-100), `rating_label`, `ping_latency_ms`, `jitter_ms`, `packet_loss_pct`, `ping_target`, `http_latency_ms`, `http_endpoint`, `download_speed_mbps`, `bytes_transferred`, `is_icmp_blocked` (0/1), `connection_type` (`'Wi-Fi'`, `'Wi-Fi (Hotspot/Tether)'`, `'Ethernet'`, `'USB Tether'`, `'Cellular'`, `'VPN / Other'`, `'Offline'`), `interface_name` (`'en0'`), `wifi_ssid`, `is_expensive` (0/1 - true for Hotspot/Tether/Cellular), `is_constrained` (0/1), `reasons`.
        - **Table `lifecycle_events`**:
          `id`, `timestamp` (epoch sec), `iso_timestamp`, `event_type` (`'app_start'` | `'app_stop'` | `'monitoring_pause'` | `'monitoring_resume'` | `'state_change'` | `'network_change'`), `previous_state`, `new_state`, `connection_type`, `interface_name`, `wifi_ssid`, `is_expensive`, `details`.
        """
    }
}
