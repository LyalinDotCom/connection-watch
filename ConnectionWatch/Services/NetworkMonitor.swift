import Foundation
import Network
import CoreWLAN
import CoreLocation

@MainActor
@Observable
final class NetworkMonitor: NSObject, CLLocationManagerDelegate {
    private(set) var isConnected = true
    private(set) var interfaceType: NWInterface.InterfaceType?
    private(set) var bsdInterfaceName: String?
    private(set) var wifiSSID: String?
    private(set) var isExpensive: Bool = false
    private(set) var isConstrained: Bool = false
    private(set) var connectionTypeDescription: String = "Network"
    private(set) var interfaceName: String = "Network"

    var onPathChange: ((Bool) -> Void)?

    private var monitor: NWPathMonitor?
    private var lastPathSignature: String?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func start() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let primaryIface = path.availableInterfaces.first
            let interface = primaryIface?.type
            let bsdName = primaryIface?.name
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            let signature = Self.makePathSignature(path)

            Task { @MainActor [weak self] in
                guard let self else { return }
                let ssid = (connected && interface == .wifi) ? Self.fetchCurrentWiFiSSID() : nil
                let connDesc = Self.describeConnectionType(
                    connected: connected,
                    type: interface,
                    bsdName: bsdName,
                    isExpensive: expensive
                )
                let displayLabel = Self.makeDisplayLabel(connDesc: connDesc, ssid: ssid)

                let signatureChanged = self.lastPathSignature != signature
                let statusChanged = self.isConnected != connected
                let ssidChanged = self.wifiSSID != ssid

                self.isConnected = connected
                self.interfaceType = interface
                self.bsdInterfaceName = bsdName
                self.wifiSSID = ssid
                self.isExpensive = expensive
                self.isConstrained = constrained
                self.connectionTypeDescription = connDesc
                self.interfaceName = displayLabel
                self.lastPathSignature = signature

                if statusChanged || signatureChanged || ssidChanged {
                    self.onPathChange?(connected)
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

    func refreshWiFiSSID() {
        guard isConnected, interfaceType == .wifi else {
            if wifiSSID != nil {
                wifiSSID = nil
                interfaceName = Self.makeDisplayLabel(connDesc: connectionTypeDescription, ssid: nil)
            }
            return
        }
        let newSSID = Self.fetchCurrentWiFiSSID()
        if newSSID != wifiSSID {
            wifiSSID = newSSID
            interfaceName = Self.makeDisplayLabel(connDesc: connectionTypeDescription, ssid: newSSID)
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.refreshWiFiSSID()
        }
    }

    // MARK: - Helpers

    private nonisolated static func fetchCurrentWiFiSSID() -> String? {
        if let ssid = CWWiFiClient.shared().interface()?.ssid(),
           !ssid.isEmpty,
           ssid != "<redacted>" {
            return ssid
        }
        if let interfaces = CWWiFiClient.shared().interfaces() {
            for iface in interfaces {
                if let ssid = iface.ssid(), !ssid.isEmpty, ssid != "<redacted>" {
                    return ssid
                }
            }
        }
        return nil
    }

    private nonisolated static func makePathSignature(_ path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
        let gateways = path.gateways.map { "\($0)" }.joined(separator: ",")
        return "\(path.status)|\(interfaces)|exp:\(path.isExpensive)|con:\(path.isConstrained)|gw:\(gateways)"
    }

    private nonisolated static func describeConnectionType(
        connected: Bool,
        type: NWInterface.InterfaceType?,
        bsdName: String?,
        isExpensive: Bool
    ) -> String {
        guard connected else { return "Offline" }
        switch type {
        case .wifi:
            return isExpensive ? "Wi-Fi (Hotspot/Tether)" : "Wi-Fi"
        case .wiredEthernet:
            if isExpensive || (bsdName?.hasPrefix("ipheth") == true) {
                return "USB Tether"
            }
            return "Ethernet"
        case .cellular:
            return "Cellular"
        case .loopback:
            return "Loopback"
        case .other:
            return isExpensive ? "Tether / Hotspot" : "VPN / Other"
        case nil:
            return "Offline"
        @unknown default:
            return "Network"
        }
    }

    private nonisolated static func makeDisplayLabel(connDesc: String, ssid: String?) -> String {
        if let ssid, !ssid.isEmpty {
            return "\(connDesc) • \(ssid)"
        }
        return connDesc
    }
}
