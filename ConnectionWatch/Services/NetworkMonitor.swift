import Foundation
import Network

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    private(set) var interfaceType: NWInterface.InterfaceType?
    private(set) var interfaceName: String = "Network"

    var onStatusChange: ((Bool) -> Void)?

    private var monitor: NWPathMonitor?
    private var lastPathSignature: String?

    func start() {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let interface = path.availableInterfaces.first?.type
            let signature = Self.makePathSignature(path)
            let name = Self.describeInterface(interface)

            Task { @MainActor [weak self] in
                guard let self else { return }
                let signatureChanged = self.lastPathSignature != signature
                let statusChanged = self.isConnected != connected

                self.isConnected = connected
                self.interfaceType = interface
                self.interfaceName = name
                self.lastPathSignature = signature

                if statusChanged || signatureChanged {
                    self.onStatusChange?(connected)
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        lastPathSignature = nil
    }

    private nonisolated static func makePathSignature(_ path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
        let gateways = path.gateways.map { "\($0)" }.joined(separator: ",")
        return "\(path.status)|\(interfaces)|exp:\(path.isExpensive)|con:\(path.isConstrained)|gw:\(gateways)"
    }

    private nonisolated static func describeInterface(_ type: NWInterface.InterfaceType?) -> String {
        switch type {
        case .wifi: return "Wi-Fi"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .loopback: return "Loopback"
        case .other: return "VPN / Other"
        case nil: return "Offline"
        @unknown default: return "Network"
        }
    }
}
