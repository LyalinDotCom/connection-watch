import SwiftUI
import ServiceManagement

@MainActor
@Observable
final class StatusViewModel {
    let monitor = ConnectionMonitorService()

    init(autoStart: Bool = true) {
        if autoStart {
            Task { @MainActor [weak self] in
                self?.start()
            }
        }
    }

    var currentState: ConnectionState { monitor.currentState }
    var health: NetworkHealth { monitor.health }
    var history: PingHistory { monitor.history }
    var isPaused: Bool { monitor.isPaused }

    var latestPingLatency: Double? {
        monitor.health.pingLatency
    }
    var latestJitter: Double? {
        monitor.health.jitter
    }
    var latestHTTPLatency: Double? {
        monitor.health.httpLatency
    }
    var latestHTTPEndpoint: String? { monitor.history.latestHTTP?.endpoint }
    var latestDownloadSpeedMbps: Double? { monitor.history.latestDownloadSpeedMbps }
    var latestSpeedTestFailed: Bool {
        if let latest = monitor.history.latestSpeed {
            return !latest.succeeded
        }
        return false
    }
    var latestDownloadSpeedDate: Date? { monitor.history.latestSpeed?.timestamp }
    var latestSpeedBytesTransferred: Int? { monitor.history.latestSpeed?.bytesTransferred }
    var recentPacketLoss: Double { monitor.history.recentPacketLoss(window: 8) }

    var interfaceName: String { monitor.interfaceName }
    var isProbing: Bool { monitor.isProbing }
    var isTestingSpeed: Bool { monitor.isTestingSpeed }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user can check System Settings
            }
        }
    }

    var notificationsEnabled: Bool {
        get { monitor.notificationsEnabled }
        set { monitor.notificationsEnabled = newValue }
    }

    var pingTarget: String {
        get { monitor.pingTarget }
        set { monitor.pingTarget = newValue }
    }

    var pingInterval: Double {
        get { monitor.pingInterval }
        set { monitor.pingInterval = newValue }
    }

    var goodThreshold: Double {
        get { monitor.goodThreshold }
        set { monitor.goodThreshold = newValue }
    }

    var degradedThreshold: Double {
        get { monitor.degradedThreshold }
        set { monitor.degradedThreshold = newValue }
    }

    @discardableResult
    func applySettings(
        pingTarget: String,
        pingInterval: Double,
        goodThreshold: Double,
        degradedThreshold: Double
    ) -> [String] {
        monitor.applySettings(
            pingTarget: pingTarget,
            pingInterval: pingInterval,
            goodThreshold: goodThreshold,
            degradedThreshold: degradedThreshold
        )
    }

    func start() {
        monitor.start()
    }

    func togglePause() {
        monitor.togglePause()
    }

    func refreshNow() {
        monitor.refreshNow()
    }

    func runSpeedTestNow() {
        monitor.runSpeedTestNow()
    }

    func copyAgentSkill() {
        CLIInstallerService.copyAgentSkillToClipboard()
    }

    var preferredCLIPath: String {
        CLIInstallerService.preferredCLIPathForAgent
    }

    var telemetryDatabasePath: String {
        TelemetryStore.databaseURL.path
    }
}
