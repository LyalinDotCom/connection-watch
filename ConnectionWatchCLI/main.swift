import Foundation

// MARK: - CLI Entry Point

enum CLICommand: String {
    case status
    case summary
    case outages
    case samples
    case speedtests
    case lifecycle
    case sql
    case schema
    case skill
    case help
}

struct CLIOptions {
    var command: CLICommand = .status
    var sinceWindow: String = "24h"
    var limit: Int = 50
    var stateFilter: String?
    var minLatency: Double?
    var lossOnly: Bool = false
    var interfaceFilter: String?
    var ssidFilter: String?
    var sqlQuery: String?
    var jsonOutput: Bool = false
}

func parseArguments(_ args: [String]) -> CLIOptions {
    var opts = CLIOptions()
    var index = 1

    if args.count > 1 {
        let first = args[1].lowercased()
        if first == "--help" || first == "-h" || first == "help" {
            opts.command = .help
            return opts
        }
        if let cmd = CLICommand(rawValue: first) {
            opts.command = cmd
            index = 2
        }
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--help", "-h":
            opts.command = .help
            return opts
        case "--json", "-j":
            opts.jsonOutput = true
        case "--loss-only":
            opts.lossOnly = true
        case "--since", "-s":
            if index + 1 < args.count {
                opts.sinceWindow = args[index + 1]
                index += 1
            }
        case "--limit", "-n":
            if index + 1 < args.count, let val = Int(args[index + 1]) {
                opts.limit = val
                index += 1
            }
        case "--state":
            if index + 1 < args.count {
                opts.stateFilter = args[index + 1]
                index += 1
            }
        case "--min-latency":
            if index + 1 < args.count, let val = Double(args[index + 1]) {
                opts.minLatency = val
                index += 1
            }
        case "--interface", "-i":
            if index + 1 < args.count {
                opts.interfaceFilter = args[index + 1]
                index += 1
            }
        case "--ssid":
            if index + 1 < args.count {
                opts.ssidFilter = args[index + 1]
                index += 1
            }
        default:
            if opts.command == .sql && opts.sqlQuery == nil && !arg.hasPrefix("-") {
                opts.sqlQuery = arg
            }
        }
        index += 1
    }

    return opts
}

func parseSinceTimestamp(_ window: String) -> (timestamp: Double?, description: String) {
    let w = window.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if w == "all" || w == "7d" {
        let ts = Date().timeIntervalSince1970 - 7 * 86400
        return (ts, "Last 7 days")
    }
    let now = Date().timeIntervalSince1970
    if w.hasSuffix("m"), let mins = Double(w.dropLast()) {
        return (now - mins * 60, "Last \(Int(mins)) minutes")
    }
    if w.hasSuffix("h"), let hours = Double(w.dropLast()) {
        return (now - hours * 3600, "Last \(Int(hours)) hours")
    }
    if w.hasSuffix("d"), let days = Double(w.dropLast()) {
        let clampedDays = min(7.0, days)
        return (now - clampedDays * 86400, "Last \(Int(clampedDays)) days")
    }
    if let hours = Double(w) {
        return (now - hours * 3600, "Last \(Int(hours)) hours")
    }
    return (now - 24 * 3600, "Last 24 hours")
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

func printHelp() {
    let executablePath = CommandLine.arguments.first ?? "connection-watch"
    let dbPath = TelemetryStore.databaseURL.path
    let statusPath = TelemetryStore.latestStatusURL.path

    let helpText = """
    connection-watch — Companion CLI & AI Agent Telemetry Utility for Connection Watch.app

    PURPOSE & PARENT APPLICATION
      `connection-watch` is the command-line interface bundled alongside Connection Watch.app
      (the macOS menu bar network health monitor).

      Why this utility exists:
      Connection Watch.app continuously captures passive ICMP ping bursts, HTTP TTFB probes,
      network interface transitions (Wi-Fi, Personal Hotspot / Tether, Ethernet, VPN), Wi-Fi SSID
      names, app start/stop lifecycle events, and on-demand Cloudflare download speed benchmarks.
      All telemetry is stored locally in a rolling 7-day SQLite database so developers, power users,
      and AI agents can inspect historical network performance and diagnose intermittent issues.

    DATA STORAGE LOCATIONS (7-DAY ROLLING TELEMETRY)
      SQLite Database : \(dbPath)
      Live Status JSON: \(statusPath)
      CLI Binary      : \(executablePath)

    USAGE
      connection-watch <subcommand> [options]

    SUBCOMMANDS
      status        Show current live network status, active interface/SSID, and database stats (default)
      summary       Compute analytical summary, percentiles (P50/P95), uptime %, and per-SSID/interface breakdown
      outages       List all degraded or disconnected incidents with timestamps and diagnostic reasons
      samples       Query raw Ping & HTTP probe samples with filtering options
      speedtests    List all on-demand download speed benchmarks run in the last 7 days
      lifecycle     List app start/stop, pause/resume, state transitions, and network handoffs
      sql "<QUERY>" Run any read-only SELECT SQL query directly against the 7-day SQLite database
      schema        Print the SQLite database table schemas and sample analytical queries
      skill         Output the complete Markdown AI Agent Skill instructions for this utility
      help          Show this help documentation (--help, -h)

    OPTIONS
      --since, -s <window>     Time window: e.g. 30m, 1h, 6h, 12h, 24h (default), 3d, 7d, all
      --limit, -n <count>      Maximum number of rows to return (default: 50)
      --state <state>          Filter samples by state: good, degraded, disconnected
      --min-latency <ms>       Filter samples where Ping or HTTP latency >= <ms>
      --loss-only              Filter samples to only those with packet loss > 0%
      --interface, -i <type>   Filter by connection type (e.g. "Wi-Fi", "Hotspot", "Ethernet", "VPN")
      --ssid <name>            Filter by Wi-Fi network name (SSID)
      --json, -j               Output results as structured JSON for AI agents and scripts

    EXAMPLES FOR AI AGENTS & USERS
      # Check current network state & live metrics
      connection-watch status

      # 7-day analytical summary comparing Wi-Fi vs. Hotspot performance
      connection-watch summary --since 7d

      # Find all outages and degraded incidents in the last 24 hours as JSON
      connection-watch outages --since 24h --json

      # Inspect high-latency (>150ms) or packet-loss samples over the last 6 hours
      connection-watch samples --since 6h --min-latency 150
      connection-watch samples --since 24h --loss-only

      # View all speed test benchmarks run this week
      connection-watch speedtests --since 7d

      # Run a custom SQL query to group packet loss by hour of day
      connection-watch sql "SELECT strftime('%Y-%m-%d %H:00', timestamp, 'unixepoch', 'localtime') AS hour, ROUND(AVG(ping_latency_ms),1) AS avg_ping, ROUND(AVG(packet_loss_pct),1) AS avg_loss FROM telemetry_samples GROUP BY hour ORDER BY hour DESC LIMIT 24;"
    """
    print(helpText)
}

func runStatusCommand(store: TelemetryStore, options: CLIOptions) {
    let counts = store.totalRecordCounts()
    if let snapshot = store.readLatestStatus() {
        if options.jsonOutput {
            printJSON(snapshot)
            return
        }
        print("==================================================================")
        print(" CONNECTION WATCH — LIVE NETWORK STATUS")
        print("==================================================================")
        print(" Parent App Version : \(snapshot.appVersion)")
        print(" Last Updated       : \(snapshot.updatedAt)")
        print(" Connection State   : \(snapshot.connectionState.uppercased()) (Score: \(snapshot.healthScore)% • \(snapshot.ratingLabel))")
        let ssidInfo = snapshot.wifiSSID.map { " [SSID: \($0)]" } ?? ""
        let tetherInfo = snapshot.isExpensive ? " [Metered / Hotspot / Tether]" : ""
        let ifaceInfo = snapshot.interfaceName.map { " (\($0))" } ?? ""
        print(" Active Connection  : \(snapshot.connectionType)\(ifaceInfo)\(ssidInfo)\(tetherInfo)")
        print("------------------------------------------------------------------")
        print(String(format: " Ping Latency       : %@", snapshot.pingLatencyMs.map { String(format: "%.1f ms (target: %@)", $0, snapshot.pingTarget) } ?? (snapshot.isICMPBlocked ? "Filtered (ICMP blocked)" : "Failed / Offline")))
        print(String(format: " Jitter             : %@", snapshot.jitterMs.map { String(format: "±%.1f ms", $0) } ?? "—"))
        print(String(format: " Packet Loss (rec.) : %.1f%%", snapshot.packetLossPct))
        print(String(format: " HTTP Probe Latency : %@", snapshot.httpLatencyMs.map { String(format: "%.1f ms (%@)", $0, snapshot.httpEndpoint ?? "probe") } ?? "Failed"))
        print(String(format: " Last Speed Test    : %@", snapshot.latestDownloadSpeedMbps.map { String(format: "%.1f Mbps (%@)", $0, snapshot.latestSpeedTestDate ?? "") } ?? "Not tested yet"))
        if !snapshot.reasons.isEmpty {
            print(" Diagnostic Notes   : \(snapshot.reasons.joined(separator: " • "))")
        }
        print("------------------------------------------------------------------")
        print(" 7-Day Telemetry DB : \(TelemetryStore.databaseURL.path)")
        print(" Stored Records     : \(counts.samples) probe/speed samples, \(counts.lifecycle) lifecycle events")
        print("==================================================================")
    } else {
        // Fallback to latest database row if latest_status.json doesn't exist yet
        let latest = store.querySamples(limit: 1).first
        if options.jsonOutput {
            printJSON(["status": "no_snapshot_file", "databasePath": TelemetryStore.databaseURL.path, "sampleCount": "\(counts.samples)"])
            return
        }
        print("Connection Watch Telemetry Store")
        print("Database Path  : \(TelemetryStore.databaseURL.path)")
        print("Stored Records : \(counts.samples) samples, \(counts.lifecycle) lifecycle events")
        if let latest {
            print("Latest Sample  : \(latest.isoTimestamp) | State: \(latest.connectionState.uppercased()) (\(latest.healthScore)%) | Type: \(latest.connectionType)")
        } else {
            print("No telemetry samples recorded yet. Ensure Connection Watch.app is running.")
        }
    }
}

func runSummaryCommand(store: TelemetryStore, options: CLIOptions) {
    let (sinceTs, windowDesc) = parseSinceTimestamp(options.sinceWindow)
    let report = store.computeSummary(
        sinceTimestamp: sinceTs,
        windowDescription: windowDesc,
        interfaceFilter: options.interfaceFilter,
        ssidFilter: options.ssidFilter
    )

    if options.jsonOutput {
        printJSON(report)
        return
    }

    print("==================================================================")
    print(" CONNECTION WATCH — ANALYTICAL SUMMARY (\(report.windowDescription.uppercased()))")
    print("==================================================================")
    if let start = report.startTimeISO, let end = report.endTimeISO {
        print(" Time Span Covered  : \(start)  ->  \(end)")
    }
    print(" Total Probe Cycles : \(report.totalProbeSamples) samples")
    print(String(format: " Network Uptime     : %.2f%% online  (%.2f%% in Good state)", report.uptimePercentage, report.healthyPercentage))
    print(" State Breakdown    : \(report.goodSamples) Good | \(report.degradedSamples) Degraded | \(report.disconnectedSamples) Disconnected")
    print(" Incidents & Events : \(report.outageEventCount) Outages | \(report.degradationEventCount) Degradations | \(report.appStartCount) App Starts / \(report.appStopCount) Stops")
    print("------------------------------------------------------------------")
    print(" LATENCY & STABILITY METRICS")
    print(String(format: "   ICMP Ping        : Avg: %@ | Min: %@ | P50: %@ | P95: %@ | Max: %@",
                 report.avgPingMs.map { String(format: "%.1fms", $0) } ?? "—",
                 report.minPingMs.map { String(format: "%.1fms", $0) } ?? "—",
                 report.p50PingMs.map { String(format: "%.1fms", $0) } ?? "—",
                 report.p95PingMs.map { String(format: "%.1fms", $0) } ?? "—",
                 report.maxPingMs.map { String(format: "%.1fms", $0) } ?? "—"))
    print(String(format: "   HTTP Probe       : Avg: %@ | Min: %@ | P95: %@ | Max: %@",
                 report.avgHttpMs.map { String(format: "%.1fms", $0) } ?? "—",
                 report.minHttpMs.map { String(format: "%.1fms", $0) } ?? "—",
                 report.p95HttpMs.map { String(format: "%.1fms", $0) } ?? "—",
                 report.maxHttpMs.map { String(format: "%.1fms", $0) } ?? "—"))
    print(String(format: "   Avg Jitter       : %@", report.avgJitterMs.map { String(format: "±%.1f ms", $0) } ?? "—"))
    print(String(format: "   Avg Packet Loss  : %@", report.avgPacketLossPct.map { String(format: "%.2f%%", $0) } ?? "0.00%"))
    print(String(format: "   Speed Benchmarks : %d run(s) | Avg: %@ | Min: %@ | Max: %@",
                 report.speedTestCount,
                 report.avgDownloadMbps.map { String(format: "%.1f Mbps", $0) } ?? "—",
                 report.minDownloadMbps.map { String(format: "%.1f Mbps", $0) } ?? "—",
                 report.maxDownloadMbps.map { String(format: "%.1f Mbps", $0) } ?? "—"))

    if !report.breakdownByConnection.isEmpty {
        print("------------------------------------------------------------------")
        print(" BREAKDOWN BY CONNECTION TYPE & WI-FI SSID")
        print("   " + "CONNECTION / SSID".padding(toLength: 32, withPad: " ", startingAt: 0)
              + "SAMPLES".padding(toLength: 10, withPad: " ", startingAt: 0)
              + "AVG PING".padding(toLength: 11, withPad: " ", startingAt: 0)
              + "AVG HTTP".padding(toLength: 11, withPad: " ", startingAt: 0)
              + "LOSS %".padding(toLength: 9, withPad: " ", startingAt: 0)
              + "AVG SPEED")
        for b in report.breakdownByConnection {
            let label = b.wifiSSID.map { "\(b.connectionType) (\($0))" } ?? b.connectionType
            let col1 = String(label.prefix(30)).padding(toLength: 32, withPad: " ", startingAt: 0)
            let col2 = "\(b.sampleCount)".padding(toLength: 10, withPad: " ", startingAt: 0)
            let col3 = (b.avgPingMs.map { String(format: "%.1fms", $0) } ?? "—").padding(toLength: 11, withPad: " ", startingAt: 0)
            let col4 = (b.avgHttpMs.map { String(format: "%.1fms", $0) } ?? "—").padding(toLength: 11, withPad: " ", startingAt: 0)
            let col5 = (b.avgLossPct.map { String(format: "%.1f%%", $0) } ?? "0.0%").padding(toLength: 9, withPad: " ", startingAt: 0)
            let col6 = b.avgDownloadMbps.map { String(format: "%.1f Mbps", $0) } ?? "—"
            print("   \(col1)\(col2)\(col3)\(col4)\(col5)\(col6)")
        }
    }
    print("==================================================================")
}

func runOutagesCommand(store: TelemetryStore, options: CLIOptions) {
    let (sinceTs, windowDesc) = parseSinceTimestamp(options.sinceWindow)
    let allSamples = store.querySamples(
        sinceTimestamp: sinceTs,
        limit: options.limit * 4,
        interfaceFilter: options.interfaceFilter,
        ssidFilter: options.ssidFilter
    )
    let issues = allSamples.filter { $0.connectionState == "disconnected" || $0.connectionState == "degraded" || ($0.packetLossPct ?? 0) > 0 }
        .prefix(options.limit)

    if options.jsonOutput {
        printJSON(Array(issues))
        return
    }

    print("==================================================================================")
    print(" OUTAGES & DEGRADED INCIDENTS (\(windowDesc)) — Showing \(issues.count) record(s)")
    print("==================================================================================")
    if issues.isEmpty {
        print(" No outages or degraded connection samples recorded during this window.")
        return
    }

    print(" " + "TIMESTAMP".padding(toLength: 26, withPad: " ", startingAt: 0)
          + "STATE".padding(toLength: 14, withPad: " ", startingAt: 0)
          + "CONNECTION / SSID".padding(toLength: 24, withPad: " ", startingAt: 0)
          + "PING".padding(toLength: 9, withPad: " ", startingAt: 0)
          + "HTTP".padding(toLength: 9, withPad: " ", startingAt: 0)
          + "LOSS".padding(toLength: 8, withPad: " ", startingAt: 0)
          + "DIAGNOSTIC REASONS")
    print(" " + String(repeating: "-", count: 105))

    for s in issues {
        let ts = String(s.isoTimestamp.prefix(24)).padding(toLength: 26, withPad: " ", startingAt: 0)
        let st = s.connectionState.uppercased().padding(toLength: 14, withPad: " ", startingAt: 0)
        let connLabel = s.wifiSSID.map { "\(s.connectionType) (\($0))" } ?? s.connectionType
        let conn = String(connLabel.prefix(22)).padding(toLength: 24, withPad: " ", startingAt: 0)
        let ping = (s.pingLatencyMs.map { String(format: "%.0fms", $0) } ?? "FAIL").padding(toLength: 9, withPad: " ", startingAt: 0)
        let http = (s.httpLatencyMs.map { String(format: "%.0fms", $0) } ?? "FAIL").padding(toLength: 9, withPad: " ", startingAt: 0)
        let loss = (s.packetLossPct.map { String(format: "%.0f%%", $0) } ?? "0%").padding(toLength: 8, withPad: " ", startingAt: 0)
        let reasons = s.reasons ?? "—"
        print(" \(ts)\(st)\(conn)\(ping)\(http)\(loss)\(reasons)")
    }
}

func runSamplesCommand(store: TelemetryStore, options: CLIOptions) {
    let (sinceTs, windowDesc) = parseSinceTimestamp(options.sinceWindow)
    let samples = store.querySamples(
        sinceTimestamp: sinceTs,
        limit: options.limit,
        stateFilter: options.stateFilter,
        minLatency: options.minLatency,
        lossOnly: options.lossOnly,
        interfaceFilter: options.interfaceFilter,
        ssidFilter: options.ssidFilter
    )

    if options.jsonOutput {
        printJSON(samples)
        return
    }

    print("==================================================================================")
    print(" TELEMETRY PROBE SAMPLES (\(windowDesc)) — Showing \(samples.count) sample(s)")
    print("==================================================================================")
    if samples.isEmpty {
        print(" No matching samples found.")
        return
    }

    print(" " + "TIMESTAMP".padding(toLength: 26, withPad: " ", startingAt: 0)
          + "STATE".padding(toLength: 13, withPad: " ", startingAt: 0)
          + "SCORE".padding(toLength: 7, withPad: " ", startingAt: 0)
          + "PING".padding(toLength: 9, withPad: " ", startingAt: 0)
          + "JITTER".padding(toLength: 8, withPad: " ", startingAt: 0)
          + "LOSS".padding(toLength: 7, withPad: " ", startingAt: 0)
          + "HTTP".padding(toLength: 9, withPad: " ", startingAt: 0)
          + "CONNECTION / SSID")
    print(" " + String(repeating: "-", count: 100))

    for s in samples {
        let ts = String(s.isoTimestamp.prefix(24)).padding(toLength: 26, withPad: " ", startingAt: 0)
        let st = s.connectionState.uppercased().padding(toLength: 13, withPad: " ", startingAt: 0)
        let sc = "\(s.healthScore)%".padding(toLength: 7, withPad: " ", startingAt: 0)
        let ping = (s.pingLatencyMs.map { String(format: "%.0fms", $0) } ?? (s.isICMPBlocked ? "FILT" : "FAIL")).padding(toLength: 9, withPad: " ", startingAt: 0)
        let jit = (s.jitterMs.map { String(format: "±%.0f", $0) } ?? "—").padding(toLength: 8, withPad: " ", startingAt: 0)
        let loss = (s.packetLossPct.map { String(format: "%.0f%%", $0) } ?? "0%").padding(toLength: 7, withPad: " ", startingAt: 0)
        let http = (s.httpLatencyMs.map { String(format: "%.0fms", $0) } ?? "FAIL").padding(toLength: 9, withPad: " ", startingAt: 0)
        let connLabel = s.wifiSSID.map { "\(s.connectionType) (\($0))" } ?? s.connectionType
        print(" \(ts)\(st)\(sc)\(ping)\(jit)\(loss)\(http)\(connLabel)")
    }
}

func runSpeedTestsCommand(store: TelemetryStore, options: CLIOptions) {
    let (sinceTs, windowDesc) = parseSinceTimestamp(options.sinceWindow)
    let speedTests = store.querySamples(
        sinceTimestamp: sinceTs,
        limit: options.limit,
        eventTypeFilter: "speed_test",
        interfaceFilter: options.interfaceFilter,
        ssidFilter: options.ssidFilter
    )

    if options.jsonOutput {
        printJSON(speedTests)
        return
    }

    print("==================================================================================")
    print(" ON-DEMAND DOWNLOAD SPEED BENCHMARKS (\(windowDesc)) — \(speedTests.count) test(s)")
    print("==================================================================================")
    if speedTests.isEmpty {
        print(" No download speed tests recorded during this window.")
        return
    }

    print(" " + "TIMESTAMP".padding(toLength: 26, withPad: " ", startingAt: 0)
          + "SPEED (MBPS)".padding(toLength: 15, withPad: " ", startingAt: 0)
          + "TTFB LATENCY".padding(toLength: 14, withPad: " ", startingAt: 0)
          + "DATA USED".padding(toLength: 12, withPad: " ", startingAt: 0)
          + "CONNECTION / SSID")
    print(" " + String(repeating: "-", count: 85))

    for s in speedTests {
        let ts = String(s.isoTimestamp.prefix(24)).padding(toLength: 26, withPad: " ", startingAt: 0)
        let speed = (s.downloadSpeedMbps.map { String(format: "%.1f Mbps", $0) } ?? "FAILED").padding(toLength: 15, withPad: " ", startingAt: 0)
        let ttfb = (s.pingLatencyMs.map { String(format: "%.0f ms", $0) } ?? "—").padding(toLength: 14, withPad: " ", startingAt: 0)
        let mb = (s.bytesTransferred.map { String(format: "%.1f MB", Double($0) / 1_000_000.0) } ?? "—").padding(toLength: 12, withPad: " ", startingAt: 0)
        let connLabel = s.wifiSSID.map { "\(s.connectionType) (\($0))" } ?? s.connectionType
        print(" \(ts)\(speed)\(ttfb)\(mb)\(connLabel)")
    }
}

func runLifecycleCommand(store: TelemetryStore, options: CLIOptions) {
    let (sinceTs, windowDesc) = parseSinceTimestamp(options.sinceWindow)
    let events = store.queryLifecycleEvents(sinceTimestamp: sinceTs, limit: options.limit)

    if options.jsonOutput {
        printJSON(events)
        return
    }

    print("==================================================================================")
    print(" APP & CONNECTION LIFECYCLE EVENTS (\(windowDesc)) — \(events.count) event(s)")
    print("==================================================================================")
    if events.isEmpty {
        print(" No lifecycle events recorded during this window.")
        return
    }

    print(" " + "TIMESTAMP".padding(toLength: 26, withPad: " ", startingAt: 0)
          + "EVENT TYPE".padding(toLength: 20, withPad: " ", startingAt: 0)
          + "CONNECTION / SSID".padding(toLength: 24, withPad: " ", startingAt: 0)
          + "DETAILS")
    print(" " + String(repeating: "-", count: 95))

    for e in events {
        let ts = String(e.isoTimestamp.prefix(24)).padding(toLength: 26, withPad: " ", startingAt: 0)
        let ev = e.eventType.uppercased().padding(toLength: 20, withPad: " ", startingAt: 0)
        let connLabel = e.wifiSSID.map { "\(e.connectionType ?? "Network") (\($0))" } ?? (e.connectionType ?? "—")
        let conn = String(connLabel.prefix(22)).padding(toLength: 24, withPad: " ", startingAt: 0)
        let details = e.details ?? "—"
        print(" \(ts)\(ev)\(conn)\(details)")
    }
}

func runSQLCommand(store: TelemetryStore, options: CLIOptions) {
    guard let query = options.sqlQuery, !query.isEmpty else {
        print("Error: Please provide a SELECT SQL query string. Example:")
        print("  connection-watch sql \"SELECT * FROM telemetry_samples ORDER BY timestamp DESC LIMIT 5;\"")
        exit(1)
    }

    do {
        let rows = try store.executeReadOnlySQL(query)
        if options.jsonOutput {
            if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            return
        }

        if rows.isEmpty {
            print("Query returned 0 rows.")
            return
        }

        let columns = Array(rows[0].keys).sorted()
        let header = columns.map { $0.padding(toLength: 18, withPad: " ", startingAt: 0) }.joined(separator: " | ")
        print(header)
        print(String(repeating: "-", count: header.count))

        for row in rows {
            let line = columns.map { col -> String in
                let val = row[col]
                let str = (val is NSNull || val == nil) ? "NULL" : "\(val!)"
                return String(str.prefix(18)).padding(toLength: 18, withPad: " ", startingAt: 0)
            }.joined(separator: " | ")
            print(line)
        }
    } catch {
        print("Error executing SQL: \(error.localizedDescription)")
        exit(1)
    }
}

func runSchemaCommand() {
    let schemaInfo = """
    ==================================================================
     CONNECTION WATCH — SQLITE DATABASE SCHEMA (7-DAY ROLLING STORE)
    ==================================================================
     Database File: \(TelemetryStore.databaseURL.path)

     TABLE 1: telemetry_samples
       id                  INTEGER PRIMARY KEY AUTOINCREMENT
       timestamp           REAL NOT NULL          -- Unix epoch seconds
       iso_timestamp       TEXT NOT NULL          -- ISO8601 local timestamp
       event_type          TEXT NOT NULL          -- 'probe' or 'speed_test'
       connection_state    TEXT NOT NULL          -- 'good', 'degraded', 'disconnected', 'paused'
       health_score        INTEGER NOT NULL       -- 0 to 100 composite health score
       rating_label        TEXT NOT NULL          -- 'Excellent', 'Good', 'Fair', 'Poor', 'Offline'
       ping_latency_ms     REAL                   -- ICMP RTT in ms (NULL if failed/filtered)
       jitter_ms           REAL                   -- Ping burst stddev in ms
       packet_loss_pct     REAL                   -- 0.0 to 100.0 packet loss percentage
       ping_target         TEXT                   -- e.g. '1.1.1.1'
       http_latency_ms     REAL                   -- HTTP TTFB latency in ms
       http_endpoint       TEXT                   -- e.g. 'https://www.google.com/generate_204'
       download_speed_mbps REAL                   -- Download throughput in Mbps (speed tests)
       bytes_transferred   INTEGER                -- Bytes downloaded during speed test
       is_icmp_blocked     INTEGER NOT NULL       -- 1 if firewall blocks ICMP while HTTP works
       connection_type     TEXT NOT NULL          -- 'Wi-Fi', 'Wi-Fi (Hotspot/Tether)', 'Ethernet', 'USB Tether', 'Cellular', 'VPN / Other', 'Offline'
       interface_name      TEXT                   -- BSD interface name (e.g. 'en0', 'en5')
       wifi_ssid           TEXT                   -- Wi-Fi network SSID name if available
       is_expensive        INTEGER NOT NULL       -- 1 if Hotspot/Tether or Cellular
       is_constrained      INTEGER NOT NULL       -- 1 if Low Data Mode active
       reasons             TEXT                   -- Diagnostic reasons when degraded/offline

     TABLE 2: lifecycle_events
       id                  INTEGER PRIMARY KEY AUTOINCREMENT
       timestamp           REAL NOT NULL          -- Unix epoch seconds
       iso_timestamp       TEXT NOT NULL          -- ISO8601 local timestamp
       event_type          TEXT NOT NULL          -- 'app_start', 'app_stop', 'monitoring_pause', 'monitoring_resume', 'state_change', 'network_change'
       previous_state      TEXT
       new_state           TEXT
       connection_type     TEXT
       interface_name      TEXT
       wifi_ssid           TEXT
       is_expensive        INTEGER NOT NULL
       details             TEXT                   -- Human-readable transition summary
    ==================================================================
    """
    print(schemaInfo)
}

// MARK: - Main Execution

let options = parseArguments(CommandLine.arguments)
let store = TelemetryStore.shared

switch options.command {
case .help:
    printHelp()
case .status:
    runStatusCommand(store: store, options: options)
case .summary:
    runSummaryCommand(store: store, options: options)
case .outages:
    runOutagesCommand(store: store, options: options)
case .samples:
    runSamplesCommand(store: store, options: options)
case .speedtests:
    runSpeedTestsCommand(store: store, options: options)
case .lifecycle:
    runLifecycleCommand(store: store, options: options)
case .sql:
    runSQLCommand(store: store, options: options)
case .schema:
    runSchemaCommand()
case .skill:
    let cliPath = CommandLine.arguments.first ?? TelemetryStore.installedCLISymlinkURL.path
    print(AgentSkillGenerator.generateSkillMarkdown(cliPath: cliPath))
}
