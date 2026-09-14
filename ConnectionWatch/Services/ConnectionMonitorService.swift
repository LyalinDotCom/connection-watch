import Foundation
import AppKit

@MainActor
@Observable
final class ConnectionMonitorService {
    private let pingService = PingService()
    private let httpProbeService = HTTPProbeService()
    private let speedTestService = SpeedTestService()
    private let networkMonitor = NetworkMonitor()
    private let notificationService = NotificationService()
    private let telemetryStore = TelemetryStore.shared

    private(set) var currentState: ConnectionState = .good
    private(set) var health: NetworkHealth = .initial
    private(set) var history = PingHistory()
    private(set) var isMonitoring = false
    private(set) var isPaused = false
    private(set) var isProbing = false
    private(set) var isTestingSpeed = false

    var interfaceName: String { networkMonitor.interfaceName }
    var connectionTypeDescription: String { networkMonitor.connectionTypeDescription }
    var wifiSSID: String? { networkMonitor.wifiSSID }
    var isExpensive: Bool { networkMonitor.isExpensive }

    private var pollingTask: Task<Void, Never>?
    private var speedTestTask: Task<Void, Never>?
    private var lastPathChangeDate: Date = .distantPast
    private var probeGeneration: Int = 0

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recordLifecycle("app_stop", details: "Application terminating")
            }
        }
    }

    static func sanitizePingTarget(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: s), let host = url.host(), !host.isEmpty {
            s = host
        } else {
            if let schemeRange = s.range(of: "://") {
                s = String(s[schemeRange.upperBound...])
            }
            if let slashIndex = s.firstIndex(of: "/") {
                s = String(s[..<slashIndex])
            }
        }
        while s.hasPrefix("-") {
            s.removeFirst()
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "1.1.1.1" : s
    }

    var pingTarget: String = UserDefaults.standard.string(forKey: "pingTarget").map(ConnectionMonitorService.sanitizePingTarget) ?? "1.1.1.1" {
        didSet {
            let sanitized = Self.sanitizePingTarget(pingTarget)
            if pingTarget != sanitized {
                pingTarget = sanitized
                return
            }
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
        let sanitizedTarget = Self.sanitizePingTarget(trimmedTarget)
        if !trimmedTarget.isEmpty && sanitizedTarget != trimmedTarget {
            adjustments.append("Target normalized to \(sanitizedTarget)")
        }
        if sanitizedTarget != pingTarget {
            pingTarget = sanitizedTarget
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
        CLIInstallerService.installSymlinkIfNeeded()
        telemetryStore.pruneOldRecords(olderThanDays: 7)

        if notificationsEnabled {
            notificationService.requestAuthorization()
        }
        notificationService.setStateProvider { [weak self] in
            self?.currentState ?? .disconnected
        }

        networkMonitor.onPathChange = { [weak self] connected in
            guard let self, !self.isPaused else { return }
            self.lastPathChangeDate = Date()
            self.recordLifecycle(
                "network_change",
                details: "Network path changed to \(self.networkMonitor.connectionTypeDescription)\(self.networkMonitor.wifiSSID.map { " (\($0))" } ?? "")"
            )
            if !connected {
                self.recalculateHealth()
            }
            self.restartPollingLoop(isManualRefresh: false)
        }
        networkMonitor.start()
        recordLifecycle("app_start", details: "Monitoring started")

        restartPollingLoop()
    }

    func stop() {
        if isMonitoring {
            recordLifecycle("app_stop", details: "Monitoring stopped")
        }
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
        recordLifecycle("monitoring_pause", details: "Monitoring paused by user")
        writeStatusSnapshot()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        currentState = health.state
        recordLifecycle("monitoring_resume", details: "Monitoring resumed by user")
        recalculateHealth()
        restartPollingLoop(isManualRefresh: true)
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
        let hasEffectiveLoss = health.recentPacketLoss > 0
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
        networkMonitor.refreshWiFiSSID()

        // When network link is down, only run lightweight HTTP recovery probe without spawning /sbin/ping subprocess
        if !networkMonitor.isConnected {
            let http = await httpProbeService.probe(timestamp: cycleTimestamp)
            guard !Task.isCancelled, !isPaused, probeGeneration == myGeneration else { return }
            if http.succeeded {
                history.append(http)
            } else {
                history.append(
                    PingResult(
                        timestamp: cycleTimestamp,
                        latency: nil,
                        packetLossPercent: 100.0,
                        endpoint: pingTarget,
                        probeType: .ping
                    )
                )
                history.append(http)
            }
            recalculateHealth()
            recordTelemetrySample(eventType: "probe", cycleTimestamp: cycleTimestamp)
            writeStatusSnapshot()
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
        recordTelemetrySample(eventType: "probe", cycleTimestamp: cycleTimestamp)
        writeStatusSnapshot()
    }

    private func performSpeedTest() async {
        guard networkMonitor.isConnected && !isPaused else { return }
        isTestingSpeed = true
        defer { isTestingSpeed = false }

        let speedResult = await speedTestService.measureDownloadSpeed()
        guard !Task.isCancelled, !isPaused, isMonitoring else { return }
        history.append(speedResult)
        recalculateHealth()
        recordTelemetrySample(eventType: "speed_test", cycleTimestamp: speedResult.timestamp, speedResult: speedResult)
        writeStatusSnapshot()
    }

    private func recalculateHealth() {
        guard !isPaused else {
            currentState = .paused
            return
        }

        let latestPing = history.latestPing
        let latestHTTP = history.latestHTTP
        let latestSpeed = history.latestDownloadSpeedMbps
        let effectiveLoss = history.recentPacketLoss(window: 8)
        let icmpBlocked = history.isICMPLikelyBlocked
        let prevState = currentState == .paused ? health.state : currentState

        let evaluated = NetworkHealth.evaluate(
            isConnected: networkMonitor.isConnected,
            pingLatency: latestPing?.latency,
            jitter: latestPing?.jitter,
            recentPacketLoss: effectiveLoss,
            httpLatency: latestHTTP?.latency,
            downloadSpeedMbps: latestSpeed,
            goodThreshold: goodThreshold,
            degradedThreshold: degradedThreshold,
            isICMPBlocked: icmpBlocked,
            previousState: prevState
        )

        self.health = evaluated
        updateState(evaluated.state)
    }

    private func updateState(_ newState: ConnectionState) {
        let oldState = currentState
        currentState = newState
        if oldState != newState && isMonitoring {
            let reasonDetail = health.reasons.isEmpty ? "" : " (\(health.reasons.joined(separator: ", ")))"
            recordLifecycle(
                "state_change",
                previousState: oldState.rawValue,
                newState: newState.rawValue,
                details: "State transitioned from \(oldState.label) to \(newState.label)\(reasonDetail)"
            )
        }
        if newState != .paused {
            notificationService.notify(state: newState, isEnabled: notificationsEnabled)
        }
    }

    // MARK: - Persistent Telemetry Recording

    private func recordTelemetrySample(eventType: String, cycleTimestamp: Date, speedResult: PingResult? = nil) {
        let latestPing = history.latestPing
        let latestHTTP = history.latestHTTP
        let sample = TelemetrySampleRecord(
            timestamp: cycleTimestamp.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(cycleTimestamp),
            eventType: eventType,
            connectionState: currentState.rawValue,
            healthScore: health.score,
            ratingLabel: health.ratingLabel,
            pingLatencyMs: speedResult != nil ? speedResult?.latency : latestPing?.latency,
            jitterMs: latestPing?.jitter,
            packetLossPct: health.recentPacketLoss,
            pingTarget: pingTarget,
            httpLatencyMs: latestHTTP?.latency,
            httpEndpoint: latestHTTP?.endpoint,
            downloadSpeedMbps: speedResult?.downloadSpeedMbps ?? history.latestDownloadSpeedMbps,
            bytesTransferred: speedResult?.bytesTransferred,
            isICMPBlocked: health.isICMPBlocked,
            connectionType: networkMonitor.connectionTypeDescription,
            interfaceName: networkMonitor.bsdInterfaceName,
            wifiSSID: networkMonitor.wifiSSID,
            isExpensive: networkMonitor.isExpensive,
            isConstrained: networkMonitor.isConstrained,
            reasons: health.reasons.isEmpty ? nil : health.reasons.joined(separator: " • ")
        )
        telemetryStore.recordSample(sample)
    }

    private func recordLifecycle(
        _ type: String,
        previousState: String? = nil,
        newState: String? = nil,
        details: String? = nil
    ) {
        let now = Date()
        let event = LifecycleEventRecord(
            timestamp: now.timeIntervalSince1970,
            isoTimestamp: TelemetryStore.formatISO(now),
            eventType: type,
            previousState: previousState,
            newState: newState,
            connectionType: networkMonitor.connectionTypeDescription,
            interfaceName: networkMonitor.bsdInterfaceName,
            wifiSSID: networkMonitor.wifiSSID,
            isExpensive: networkMonitor.isExpensive,
            details: details
        )
        telemetryStore.recordLifecycleEvent(event)
    }

    private func writeStatusSnapshot() {
        let now = Date()
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "18"
        let snapshot = LatestStatusSnapshot(
            updatedAt: TelemetryStore.formatISO(now),
            timestamp: now.timeIntervalSince1970,
            appVersion: "v\(shortVersion) (build \(buildNumber))",
            connectionState: currentState.rawValue,
            healthScore: health.score,
            ratingLabel: health.ratingLabel,
            connectionType: networkMonitor.connectionTypeDescription,
            interfaceName: networkMonitor.bsdInterfaceName,
            wifiSSID: networkMonitor.wifiSSID,
            isExpensive: networkMonitor.isExpensive,
            isConstrained: networkMonitor.isConstrained,
            pingLatencyMs: currentState == .disconnected ? nil : history.latestPing?.latency,
            jitterMs: currentState == .disconnected ? nil : history.latestPing?.jitter,
            packetLossPct: health.recentPacketLoss,
            pingTarget: pingTarget,
            httpLatencyMs: currentState == .disconnected ? nil : history.latestHTTP?.latency,
            httpEndpoint: history.latestHTTP?.endpoint,
            latestDownloadSpeedMbps: history.latestDownloadSpeedMbps,
            latestSpeedTestDate: history.latestSpeed.map { TelemetryStore.formatISO($0.timestamp) },
            isICMPBlocked: health.isICMPBlocked,
            reasons: health.reasons,
            databasePath: TelemetryStore.databaseURL.path,
            cliExecutablePath: CLIInstallerService.preferredCLIPathForAgent
        )
        telemetryStore.writeLatestStatus(snapshot)
    }
}
