import Foundation

@MainActor
@Observable
final class ConnectionMonitorService {
    private let pingService = PingService()
    private let httpProbeService = HTTPProbeService()
    private let speedTestService = SpeedTestService()
    private let networkMonitor = NetworkMonitor()
    private let notificationService = NotificationService()

    private(set) var currentState: ConnectionState = .good
    private(set) var health: NetworkHealth = .initial
    private(set) var history = PingHistory()
    private(set) var isMonitoring = false
    private(set) var isPaused = false
    private(set) var isProbing = false
    private(set) var isTestingSpeed = false

    var interfaceName: String { networkMonitor.interfaceName }

    private var pollingTask: Task<Void, Never>?
    private var speedTestTask: Task<Void, Never>?
    private var lastPathChangeDate: Date = .distantPast

    @ObservationIgnored
    var pingTarget: String = UserDefaults.standard.string(forKey: "pingTarget") ?? "1.1.1.1" {
        didSet {
            if isMonitoring && !isPaused {
                refreshNow()
            }
        }
    }

    @ObservationIgnored
    var pingInterval: TimeInterval = UserDefaults.standard.double(forKey: "pingInterval").clamped(to: 5...120, default: 10) {
        didSet {
            if isMonitoring && !isPaused {
                restartPollingLoop()
            }
        }
    }

    @ObservationIgnored
    var goodThreshold: Double = UserDefaults.standard.double(forKey: "goodThreshold").clamped(to: 50...2000, default: 150) {
        didSet {
            recalculateHealth()
        }
    }

    @ObservationIgnored
    var degradedThreshold: Double = UserDefaults.standard.double(forKey: "degradedThreshold").clamped(to: 100...5000, default: 600) {
        didSet {
            recalculateHealth()
        }
    }

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
        isPaused = false
        if notificationsEnabled {
            notificationService.requestAuthorization()
        }
        notificationService.setStateProvider { [weak self] in
            self?.currentState ?? .disconnected
        }

        networkMonitor.onStatusChange = { [weak self] connected in
            guard let self, !self.isPaused else { return }
            self.lastPathChangeDate = Date()
            if !connected {
                self.recalculateHealth()
            } else {
                self.refreshNow()
            }
        }
        networkMonitor.start()

        restartPollingLoop()
    }

    func stop() {
        isMonitoring = false
        isPaused = false
        pollingTask?.cancel()
        pollingTask = nil
        speedTestTask?.cancel()
        speedTestTask = nil
        networkMonitor.stop()
        notificationService.setStateProvider { .disconnected }
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pollingTask?.cancel()
        pollingTask = nil
        speedTestTask?.cancel()
        speedTestTask = nil
        currentState = .paused
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        restartPollingLoop()
    }

    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    /// Triggers an immediate passive Ping + HTTP probe cycle (no download speed test).
    func refreshNow() {
        guard !isPaused else { return }
        restartPollingLoop()
    }

    /// Strictly on-demand download speed test triggered only by explicit user action.
    func runSpeedTestNow() {
        guard !isTestingSpeed else { return }
        speedTestTask?.cancel()
        speedTestTask = Task { [weak self] in
            await self?.performSpeedTest()
        }
    }

    private func restartPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && !self.isPaused {
                await self.performProbes()

                let sleepInterval = self.effectivePollingInterval()
                try? await Task.sleep(for: .seconds(sleepInterval))
            }
        }
    }

    /// Adaptive interval: probe every 5s when degraded/disconnected/after path change, or `pingInterval` (default 10s) when healthy.
    private func effectivePollingInterval() -> TimeInterval {
        let recentlyChanged = Date().timeIntervalSince(lastPathChangeDate) < 20
        if currentState == .degraded || currentState == .disconnected || health.recentPacketLoss > 0 || recentlyChanged {
            return min(pingInterval, 5.0)
        }
        return pingInterval
    }

    private func performProbes() async {
        guard !isProbing, !isPaused else { return }
        isProbing = true
        defer { isProbing = false }

        // Run passive Ping burst and HTTP HEAD probe in parallel (~100 bytes total)
        async let pingResult = pingService.ping(target: pingTarget)
        async let httpResult = httpProbeService.probe()

        let ping = await pingResult
        let http = await httpResult

        guard !isPaused else { return }

        history.append(ping)
        history.append(http)

        recalculateHealth()
    }

    private func performSpeedTest() async {
        guard networkMonitor.isConnected else { return }
        isTestingSpeed = true
        defer { isTestingSpeed = false }

        let speedResult = await speedTestService.measureDownloadSpeed()
        if speedResult.succeeded {
            history.append(speedResult)
            recalculateHealth()
        }
    }

    private func recalculateHealth() {
        guard !isPaused else {
            currentState = .paused
            return
        }

        let latestPing = history.latestPing
        let latestHTTP = history.latestHTTP
        let latestSpeed = history.latestDownloadSpeedMbps
        let recentLoss = history.recentPacketLoss(window: 8)

        let evaluated = NetworkHealth.evaluate(
            isConnected: networkMonitor.isConnected,
            pingLatency: latestPing?.latency,
            jitter: latestPing?.jitter,
            recentPacketLoss: recentLoss,
            httpLatency: latestHTTP?.latency,
            downloadSpeedMbps: latestSpeed,
            goodThreshold: goodThreshold,
            degradedThreshold: degradedThreshold,
            previousState: currentState
        )

        self.health = evaluated
        updateState(evaluated.state)
    }

    private func updateState(_ newState: ConnectionState) {
        currentState = newState
        if notificationsEnabled && newState != .paused {
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
