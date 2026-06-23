import SwiftUI
import ServiceManagement

@MainActor
@Observable
final class StatusViewModel {
    let monitor = ConnectionMonitorService()

    var currentState: ConnectionState { monitor.currentState }
    var history: PingHistory { monitor.history }

    var latestPingLatency: Double? { monitor.history.latestPing?.latency }
    var latestHTTPLatency: Double? { monitor.history.latestHTTP?.latency }
    var latestHTTPEndpoint: String? { monitor.history.latestHTTP?.endpoint }

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
        set {
            monitor.notificationsEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "notificationsEnabled")
        }
    }

    var pingTarget: String {
        get { monitor.pingTarget }
        set {
            monitor.pingTarget = newValue
            UserDefaults.standard.set(newValue, forKey: "pingTarget")
        }
    }

    var pingInterval: Double {
        get { monitor.pingInterval }
        set {
            monitor.pingInterval = newValue
            UserDefaults.standard.set(newValue, forKey: "pingInterval")
        }
    }

    var goodThreshold: Double {
        get { monitor.goodThreshold }
        set {
            monitor.goodThreshold = newValue
            UserDefaults.standard.set(newValue, forKey: "goodThreshold")
        }
    }

    var degradedThreshold: Double {
        get { monitor.degradedThreshold }
        set {
            monitor.degradedThreshold = newValue
            UserDefaults.standard.set(newValue, forKey: "degradedThreshold")
        }
    }

    func start() {
        monitor.start()
    }
}
