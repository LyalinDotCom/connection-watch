import Foundation

struct PingHistory: Sendable {
    private var buffer: [PingResult]
    private let capacity: Int

    init(capacity: Int = 240) {
        self.capacity = capacity
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }

    var entries: [PingResult] { buffer }
    var count: Int { buffer.count }
    var isEmpty: Bool { buffer.isEmpty }

    var latest: PingResult? { buffer.last }

    var latestPing: PingResult? { buffer.last { $0.probeType == .ping } }
    var latestHTTP: PingResult? { buffer.last { $0.probeType == .http } }
    var latestSpeed: PingResult? { buffer.last { $0.probeType == .speed } }

    var latestDownloadSpeedMbps: Double? {
        buffer.last { $0.probeType == .speed && $0.downloadSpeedMbps != nil }?.downloadSpeedMbps
    }

    var latestJitter: Double? {
        latestPing?.jitter
    }

    /// Single source of truth for whether ICMP is filtered while HTTP connectivity works.
    /// True if at least 3 recent ping probes in the window failed while at least one recent HTTP probe succeeded.
    var isICMPLikelyBlocked: Bool {
        let recentPings = buffer.filter { $0.probeType == .ping }.suffix(6)
        let recentHTTPs = buffer.filter { $0.probeType == .http }.suffix(6)
        guard recentPings.count >= 3, !recentHTTPs.isEmpty else { return false }
        let allPingsFailed = recentPings.allSatisfy { !$0.succeeded }
        let anyHTTPSucceeded = recentHTTPs.contains { $0.succeeded }
        return allPingsFailed && anyHTTPSucceeded
    }

    func entries(ofType type: ProbeType) -> [PingResult] {
        buffer.filter { $0.probeType == type }
    }

    var successfulEntries: [PingResult] {
        buffer.filter { $0.succeeded }
    }

    private var primaryLatencyEntries: [Double] {
        let pingLatencies = buffer.filter { $0.probeType == .ping }.compactMap(\.latency)
        if !pingLatencies.isEmpty {
            return pingLatencies
        }
        return buffer.filter { $0.probeType == .http }.compactMap(\.latency)
    }

    var averageLatency: Double? {
        let latencies = primaryLatencyEntries
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    var minLatency: Double? {
        primaryLatencyEntries.min()
    }

    var maxLatency: Double? {
        primaryLatencyEntries.max()
    }

    var packetLoss: Double {
        if isICMPLikelyBlocked {
            let httpEntries = buffer.filter { $0.probeType == .http }
            guard !httpEntries.isEmpty else { return 0 }
            let failedHTTP = httpEntries.filter { !$0.succeeded }.count
            return Double(failedHTTP) / Double(httpEntries.count) * 100
        }
        let pings = buffer.filter { $0.probeType == .ping }
        guard !pings.isEmpty else { return 0 }
        let failed = pings.filter { !$0.succeeded }.count
        return Double(failed) / Double(pings.count) * 100
    }

    /// Raw packet loss over the most recent `window` ICMP ping probes.
    func rawRecentPingPacketLoss(window: Int = 8) -> Double {
        let pingEntries = buffer.filter { $0.probeType == .ping }.suffix(window)
        guard !pingEntries.isEmpty else { return 0 }
        var totalLoss: Double = 0
        for entry in pingEntries {
            if let explicitLoss = entry.packetLossPercent {
                totalLoss += explicitLoss
            } else {
                totalLoss += entry.succeeded ? 0.0 : 100.0
            }
        }
        return totalLoss / Double(pingEntries.count)
    }

    /// Effective packet loss percentage over the most recent `window` probes.
    /// If ICMP is blocked (all pings fail while HTTP succeeds), falls back to HTTP probe failure rate.
    func recentPacketLoss(window: Int = 8) -> Double {
        if isICMPLikelyBlocked {
            let httpEntries = buffer.filter { $0.probeType == .http }.suffix(window)
            guard !httpEntries.isEmpty else { return 0 }
            let failedHTTP = httpEntries.filter { !$0.succeeded }.count
            return Double(failedHTTP) / Double(httpEntries.count) * 100.0
        }
        return rawRecentPingPacketLoss(window: window)
    }

    func averageLatency(ofType type: ProbeType) -> Double? {
        let latencies = buffer.filter { $0.probeType == type }.compactMap(\.latency)
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    mutating func append(_ result: PingResult) {
        if buffer.count >= capacity {
            buffer.removeFirst()
        }
        buffer.append(result)
    }

    mutating func clear() {
        buffer.removeAll(keepingCapacity: true)
    }
}
