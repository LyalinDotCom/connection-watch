import Foundation

enum ProbeType: String, Sendable {
    case ping
    case http
    case speed
}

struct PingResult: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let latency: Double?          // nil means probe failed (ms)
    let jitter: Double?           // stddev in ms from ping burst
    let packetLossPercent: Double? // 0...100 from ping burst
    let downloadSpeedMbps: Double? // download throughput in Mbps
    let endpoint: String?
    let probeType: ProbeType

    init(
        timestamp: Date,
        latency: Double?,
        jitter: Double? = nil,
        packetLossPercent: Double? = nil,
        downloadSpeedMbps: Double? = nil,
        endpoint: String? = nil,
        probeType: ProbeType = .ping
    ) {
        self.timestamp = timestamp
        self.latency = latency
        self.jitter = jitter
        self.packetLossPercent = packetLossPercent
        self.downloadSpeedMbps = downloadSpeedMbps
        self.endpoint = endpoint
        self.probeType = probeType
    }

    var succeeded: Bool {
        switch probeType {
        case .ping, .http:
            return latency != nil
        case .speed:
            return downloadSpeedMbps != nil
        }
    }
}
