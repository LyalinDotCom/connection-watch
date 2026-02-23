import Foundation

enum ProbeType: String, Sendable {
    case ping
    case http
}

struct PingResult: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let latency: Double?  // nil means probe failed
    let endpoint: String?
    let probeType: ProbeType

    init(timestamp: Date, latency: Double?, endpoint: String? = nil, probeType: ProbeType = .ping) {
        self.timestamp = timestamp
        self.latency = latency
        self.endpoint = endpoint
        self.probeType = probeType
    }

    var succeeded: Bool { latency != nil }
}
