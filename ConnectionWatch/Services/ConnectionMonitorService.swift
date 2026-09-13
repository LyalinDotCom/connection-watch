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
    private var probeGeneration: Int = 0

    @ObservationIgnored
    var pingTarget: String = UserDefaults.standard.string(forKey: "pingTarget") ?? "1.1.1.1" {
        didSet {
            if isMonitoring && !isPaused && pingTarget != oldValue {
                refreshNow()
            }
        }
    }

    @ObservationIgnored
    var pingInterval: TimeInterval = UserDefaults.standard.double(forKey: "pingInterval").clamped(to: 5...120, default: 10) {
        didSet {
            let clampedVal = pingInterval.clamped(to: 5...120, default: 10)
            if pingInterval != clampedVal {
                pingInterval = clampedVal
                return
            }
            if isMonitoring && !isPaused && pingInterval != oldValue {
                restartPollingLoop()
            }
        }
    }

    @ObservationIgnored
    var goodThreshold: Double = UserDefaults.standard.double(forKey: "goodThreshold").clamped(to: 50...2000, default: 150) {
        didSet {
            let clampedVal = goodThreshold.clamped(to: 50...2000, default: 150)
            if goodThreshold != clampedVal {
                goodThreshold = clampedVal
                return
            }
            if degradedThreshold < goodThreshold + 50 {
                degradedThreshold = min(5000, goodThreshold + 50)
            }
            recalculateHealth()
        }
    }

    @ObservationIgnored
    var degradedThreshold: Double = UserDefaults.standard.double(forKey: "degradedThreshold").clamped(to: 100...5000, default: 600) {
        didSet {
            let clampedVal = max(goodThreshold + 50, degradedThreshold.clamped(to: 100...5000, default: 600))
            if degradedThreshold != clampedVal {
                degradedThreshold = clampedVal
                return
            }
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

        networkMonitor.onPathChange = { [weak self] connected in
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
        isProbing = false
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
    func effectivePollingInterval() -> TimeInterval {
        let recentlyChanged = Date().timeIntervalSince(lastPathChangeDate) < 20
        let hasEffectiveLoss = !health.isICMPBlocked && health.recentPacketLoss > 0
        if currentState == .degraded || currentState == .disconnected || hasEffectiveLoss || recentlyChanged {
            return min(pingInterval, 5.0)
        }
        return pingInterval
    }

    private func performProbes() async {
        guard !isPaused else { return }
        probeGeneration += 1
        let myGeneration = probeGeneration
        isProbing = true
        defer {
            if probeGeneration == myGeneration {
                isProbing = false
            }
        }

        // Run passive Ping burst and HTTP HEAD probe in parallel (~100 bytes total)
        async let pingResult = pingService.ping(target: pingTarget)
        async let httpResult = httpProbeService.probe()

        let ping = await pingResult
        let http = await httpResult

        guard !Task.isCancelled, !isPaused, probeGeneration == myGeneration else { return }

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
        let rawPingLoss = history.rawRecentPingPacketLoss(window: 8)
        let icmpBlocked = history.isICMPLikelyBlocked

        let evaluated = NetworkHealth.evaluate(
            isConnected: networkMonitor.isConnected,
            pingLatency: latestPing?.latency,
            jitter: latestPing?.jitter,
            recentPacketLoss: rawPingLoss,
            httpLatency: latestHTTP?.latency,
            downloadSpeedMbps: latestSpeed,
            goodThreshold: goodThreshold,
            degradedThreshold: degradedThreshold,
            isICMPBlocked: icmpBlocked,
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
