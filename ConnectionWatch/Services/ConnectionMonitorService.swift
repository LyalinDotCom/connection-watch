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

    var pingTarget: String = UserDefaults.standard.string(forKey: "pingTarget") ?? "1.1.1.1" {
        didSet {
            UserDefaults.standard.set(pingTarget, forKey: "pingTarget")
            if isMonitoring && !isPaused && pingTarget != oldValue {
                restartPollingLoop(isManualRefresh: false)
            }
        }
    }

    var pingInterval: TimeInterval = UserDefaults.standard.double(forKey: "pingInterval").clamped(to: 5...120, default: 10) {
        didSet {
            let clampedVal = pingInterval.clamped(to: 5...120, default: 10)
            if pingInterval != clampedVal {
                pingInterval = clampedVal
                return
            }
            UserDefaults.standard.set(pingInterval, forKey: "pingInterval")
            if isMonitoring && !isPaused && pingInterval != oldValue {
                restartPollingLoop(isManualRefresh: false)
            }
        }
    }

    var goodThreshold: Double = UserDefaults.standard.double(forKey: "goodThreshold").clamped(to: 50...2000, default: 150) {
        didSet {
            let clampedVal = goodThreshold.clamped(to: 50...2000, default: 150)
            if goodThreshold != clampedVal {
                goodThreshold = clampedVal
                return
            }
            UserDefaults.standard.set(goodThreshold, forKey: "goodThreshold")
            if degradedThreshold < goodThreshold + 50 {
                degradedThreshold = min(5000, goodThreshold + 50)
            }
            recalculateHealth()
        }
    }

    var degradedThreshold: Double = UserDefaults.standard.double(forKey: "degradedThreshold").clamped(to: 100...5000, default: 600) {
        didSet {
            let clampedVal = max(goodThreshold + 50, degradedThreshold.clamped(to: 100...5000, default: 600))
            if degradedThreshold != clampedVal {
                degradedThreshold = clampedVal
                return
            }
            UserDefaults.standard.set(degradedThreshold, forKey: "degradedThreshold")
            recalculateHealth()
        }
    }

    var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled {
                notificationService.requestAuthorization()
            } else {
                notificationService.cancelPending()
            }
        }
    }

    /// Atomically applies, clamps, and cross-validates numeric and target settings, returning any adjustment notes.
    @discardableResult
    func applySettings(
        pingTarget newTarget: String,
        pingInterval inputInterval: Double,
        goodThreshold inputGood: Double,
        degradedThreshold inputDegraded: Double
    ) -> [String] {
        var adjustments: [String] = []

        let trimmedTarget = newTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTarget.isEmpty && trimmedTarget != pingTarget {
            pingTarget = trimmedTarget
        }

        let actualInterval = inputInterval.clamped(to: 5...120, default: 10)
        let actualGood = inputGood.clamped(to: 50...2000, default: 150)
        let actualDegraded = max(actualGood + 50, inputDegraded.clamped(to: 100...5000, default: 600))

        if inputInterval != actualInterval {
            adjustments.append("Interval clamped to \(Int(actualInterval))s (5–120s)")
        }
        if inputGood != actualGood {
            adjustments.append("Good threshold clamped to \(Int(actualGood))ms")
        }
        if inputDegraded != actualDegraded {
            adjustments.append("Degraded set to ≥ Good + 50ms (\(Int(actualDegraded))ms)")
        }

        pingInterval = actualInterval
        goodThreshold = actualGood
        degradedThreshold = actualDegraded

        return adjustments
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
                self.restartPollingLoop(isManualRefresh: false)
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
        isTestingSpeed = false
        networkMonitor.stop()
        notificationService.cancelPending()
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
        isTestingSpeed = false
        notificationService.cancelPending()
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
        restartPollingLoop(isManualRefresh: true)
    }

    /// Strictly on-demand download speed test triggered only by explicit user action.
    func runSpeedTestNow() {
        guard !isTestingSpeed && !isPaused else { return }
        speedTestTask?.cancel()
        speedTestTask = Task { [weak self] in
            await self?.performSpeedTest()
        }
    }

    private func restartPollingLoop(isManualRefresh: Bool = false) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            var firstIteration = true
            while !Task.isCancelled && !self.isPaused {
                let manual = firstIteration && isManualRefresh
                firstIteration = false
                await self.performProbes(isManual: manual)

                let sleepInterval = self.effectivePollingInterval()
                try? await Task.sleep(for: .seconds(sleepInterval))
            }
        }
    }

    /// Adaptive interval: probe every 5s when degraded/after path change, back off when offline, or `pingInterval` (default 10s) when healthy.
    func effectivePollingInterval() -> TimeInterval {
        if !networkMonitor.isConnected {
            return min(60.0, max(15.0, pingInterval * 2.0))
        }
        let recentlyChanged = Date().timeIntervalSince(lastPathChangeDate) < 20
        let hasEffectiveLoss = !health.isICMPBlocked && health.recentPacketLoss > 0
        if currentState == .degraded || currentState == .disconnected || hasEffectiveLoss || recentlyChanged {
            return min(pingInterval, 5.0)
        }
        return pingInterval
    }

    private func performProbes(isManual: Bool = false) async {
        guard !isPaused else { return }
        probeGeneration += 1
        let myGeneration = probeGeneration
        if isManual {
            isProbing = true
        }
        defer {
            if isManual && probeGeneration == myGeneration {
                isProbing = false
            }
        }

        let cycleTimestamp = Date()

        // When network link is down, only run lightweight HTTP recovery probe without spawning /sbin/ping subprocess
        if !networkMonitor.isConnected {
            let http = await httpProbeService.probe(timestamp: cycleTimestamp)
            guard !Task.isCancelled, !isPaused, probeGeneration == myGeneration else { return }
            if http.succeeded {
                history.append(http)
            }
            recalculateHealth()
            return
        }

        // Run passive Ping burst and HTTP HEAD probe in parallel (~100 bytes total) with shared cycle timestamp
        async let pingResult = pingService.ping(target: pingTarget, timestamp: cycleTimestamp)
        async let httpResult = httpProbeService.probe(timestamp: cycleTimestamp)

        let ping = await pingResult
        let http = await httpResult

        guard !Task.isCancelled, !isPaused, probeGeneration == myGeneration else { return }

        history.append(ping)
        history.append(http)

        recalculateHealth()
    }

    private func performSpeedTest() async {
        guard networkMonitor.isConnected && !isPaused else { return }
        isTestingSpeed = true
        defer { isTestingSpeed = false }

        let speedResult = await speedTestService.measureDownloadSpeed()
        guard !Task.isCancelled, !isPaused, isMonitoring else { return }
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
