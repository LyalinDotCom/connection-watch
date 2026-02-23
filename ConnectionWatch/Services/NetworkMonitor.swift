import Foundation
import Network

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    private(set) var interfaceType: NWInterface.InterfaceType?

    var onStatusChange: ((Bool) -> Void)?

    private var monitor: NWPathMonitor?

    func start() {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let interface = path.availableInterfaces.first?.type

            Task { @MainActor [weak self] in
                guard let self else { return }
                let changed = self.isConnected != connected
                self.isConnected = connected
                self.interfaceType = interface
                if changed {
                    self.onStatusChange?(connected)
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
