import Foundation

@MainActor
@Observable
final class ConnectionMonitorService {
    private let pingService = PingService()
    private let httpProbeService = HTTPProbeService()
    private let networkMonitor = NetworkMonitor()
    private let notificationService = NotificationService()

    private(set) var currentState: ConnectionState = .good
    private(set) var history = PingHistory()
    private(set) var isMonitoring = false

    private var pollingTask: Task<Void, Never>?

    @ObservationIgnored
    var pingTarget: String = UserDefaults.standard.string(forKey: "pingTarget") ?? "1.1.1.1"
    @ObservationIgnored
    var pingInterval: TimeInterval = UserDefaults.standard.double(forKey: "pingInterval").clamped(to: 5...120, default: 15)
    @ObservationIgnored
    var goodThreshold: Double = UserDefaults.standard.double(forKey: "goodThreshold").clamped(to: 50...2000, default: 200)
    @ObservationIgnored
    var degradedThreshold: Double = UserDefaults.standard.double(forKey: "degradedThreshold").clamped(to: 100...5000, default: 1000)
    @ObservationIgnored
    var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true {
        didSet {
            if notificationsEnabled {
                notificationService.requestAuthorization()
            }
        }
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        if notificationsEnabled {
            notificationService.requestAuthorization()
        }
        notificationService.setStateProvider { [weak self] in
            self?.currentState ?? .disconnected
        }

        networkMonitor.onStatusChange = { [weak self] connected in
            guard let self else { return }
            if !connected {
                self.updateState(.disconnected)
            } else {
                Task { await self.performProbes() }
            }
        }
        networkMonitor.start()

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.performProbes()
                try? await Task.sleep(for: .seconds(self.pingInterval))
            }
        }
    }

    func stop() {
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
        networkMonitor.stop()
        notificationService.setStateProvider { .disconnected }
    }

    private func performProbes() async {
        // Run both probes in parallel
        async let pingResult = pingService.ping(target: pingTarget)
        async let httpResult = httpProbeService.probe()

        let ping = await pingResult
        let http = await httpResult

        history.append(ping)
        history.append(http)

        let newState = evaluateComposite(ping: ping, http: http)
        updateState(newState)
    }

    /// Composite decision: HTTP probe is the primary signal (matches real user experience).
    /// Ping is supplementary — if HTTP works but ping fails, connection is still good.
    /// Only report disconnected if both fail.
    private func evaluateComposite(ping: PingResult, http: PingResult) -> ConnectionState {
        guard networkMonitor.isConnected else { return .disconnected }

        // If HTTP succeeds, that's the strongest signal of real connectivity
        if let httpLatency = http.latency {
            if httpLatency < goodThreshold { return .good }
            if httpLatency < degradedThreshold { return .degraded }
            // HTTP responded but very slowly
            return .degraded
        }

        // HTTP failed — check if ping works (partial connectivity)
        if ping.latency != nil {
            // Network layer works but application layer doesn't
            return .degraded
        }

        // Both failed
        return .disconnected
    }

    private func updateState(_ newState: ConnectionState) {
        currentState = newState
        if notificationsEnabled {
            notificationService.notify(state: newState)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
